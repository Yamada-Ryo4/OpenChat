export default {
    // AUTH_KEY 从 Cloudflare Workers 环境变量读取
    // 配置方式：Cloudflare Dashboard → Workers → Settings → Variables → 添加 AUTH_KEY
    async fetch(request, env)
    {
        const AUTH_KEY = env.AUTH_KEY ?? "";  // 从环境变量读取，勿在此处硬编码
        const MAX_BACKUPS = 100;
        const cors = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Auth-Key',
        };

        if (request.method === 'OPTIONS')
            return new Response(null, { status: 204, headers: cors });

        if (request.headers.get('X-Auth-Key') !== AUTH_KEY)
            return json({ status: 'error', message: 'Unauthorized' }, 401, cors);

        const pathname = new URL(request.url).pathname.slice(1);
        if (!pathname) return json({ status: 'error', message: 'Filename required' }, 400, cors);

        if (request.method === 'GET' && pathname.startsWith('list/'))
            return handleList(env, pathname.slice(5), cors);
        if (request.method === 'GET' && pathname.startsWith('preview/'))
            return handlePreview(env, pathname.slice(8), cors);
        if (request.method === 'POST' && pathname.startsWith('dedup/'))
            return handleDedup(env, pathname.slice(6), MAX_BACKUPS, cors);
        if (request.method === 'POST' && pathname.startsWith('rename/'))
            return handleRename(env, request, pathname.slice(7), cors);
        if (request.method === 'GET')
            return handleGet(env, pathname, cors);
        if (request.method === 'PUT')
            return handlePut(env, pathname, request, MAX_BACKUPS, cors);
        if (request.method === 'DELETE')
            return handleDelete(env, pathname, cors);

        return json({ status: 'error', message: 'Method Not Allowed' }, 405, cors);
    },
};

// ========== 基础操作 ==========
async function handleGet(env, key, cors) {
    const obj = await env.MY_R2_BUCKET.get(key);
    if (!obj) return json({ status: 'error', message: 'Not Found' }, 404, cors);
    const h = new Headers(cors);
    h.set('Content-Type', 'application/json');
    return new Response(obj.body, { headers: h });
}

async function handleDelete(env, key, cors) {
    await env.MY_R2_BUCKET.delete(key);
    return json({ status: 'success', message: `Deleted ${key}` }, 200, cors);
}

// ========== 重命名 (更新 metadata) ==========
async function handleRename(env, request, key, cors) {
    try {
        const { name } = await request.clone().json();
        if (!name) return json({ status: 'error', message: 'Name required' }, 400, cors);

        // 获取当前对象
        const obj = await env.MY_R2_BUCKET.get(key);
        if (!obj) return json({ status: 'error', message: 'File not found' }, 404, cors);

        // 更新 customName
        const meta = obj.customMetadata || {};
        await env.MY_R2_BUCKET.put(key, obj.body, {
            httpMetadata: { contentType: 'application/json' },
            customMetadata: { ...meta, customName: name }
        });

        return json({ status: 'success', message: 'Renamed', customName: name }, 200, cors);
    } catch (err) {
        return json({ status: 'error', message: err.message }, 500, cors);
    }
}

// ========== 上传 (只复制 v0→vN+1) ==========
async function handlePut(env, key, request, MAX_BACKUPS, cors) {
    try {
        const newContent = await request.text();
        const newHash = await sha256(newContent);
        const { name, ext } = splitFilename(key);

        const currentObj = await env.MY_R2_BUCKET.get(key);
        if (currentObj) {
            let currentText = await currentObj.text();

            // 如果内容完全一样且没有重命名请求，跳过？
            // 使用 normalizedHash 忽略 _backupTime 差异
            const curHash = await normalizedHash(currentText);
            const newNormHash = await normalizedHash(newContent);

            if (curHash === newNormHash) {
                return json({ status: 'skipped', message: '内容无变化' }, 200, cors);
            }

            // 注入时间参数到当前文件内容中 (如果是 JSON)
            const curMeta = currentObj.customMetadata || {};
            const originalTime = curMeta.originalTime || currentObj.uploaded.toISOString();

            try {
                const jsonContent = JSON.parse(currentText);
                // 确保 _backupTime 在最前面
                const { _backupTime, ...rest } = jsonContent;
                const newJson = { _backupTime: originalTime, ...rest };
                currentText = JSON.stringify(newJson);
                // 注意：这里改变了 content，所以 hash 也会变。但历史文件的 hash 是基于改变后的内容吗？
                // 通常历史文件保持原样。但用户希望文件里有时间。
                // 我们在保存为历史版本时修改它。
            } catch (e) {
                // 非 JSON 不处理
            }

            // 找到第一个可用的历史版本号 (填补空缺)
            const history = await listHistory(env, name, ext, key);
            const existingVers = new Set(history.map(v => v.ver));
            let nextVer = 1;
            while (existingVers.has(nextVer)) {
                nextVer++;
            }

            // 准备 Metadata (避免 null 被转为 "null" 字符串)
            const newMeta = {
                uuid: curMeta.uuid || crypto.randomUUID(),
                originalTime: originalTime,
                contentHash: await sha256(currentText),
            };
            if (curMeta.customName) {
                newMeta.customName = curMeta.customName;
            }

            // 保存当前 v0 → v(nextVer)
            await env.MY_R2_BUCKET.put(`${name}${nextVer}${ext}`, currentText, {
                httpMetadata: { contentType: 'application/json' },
                customMetadata: newMeta,
            });

            // 超限裁剪
            if (history.length + 1 > MAX_BACKUPS) {
                // 重新获取完整列表包括刚刚添加的? 
                // listHistory 是异步的，这里为了性能直接用旧列表判断 + 1 是不够准确的如果填补了空缺?
                // 实际上如果填补了空缺，并没有增加总是数? 不，增加了。
                // 简单起见，如果总量 > MAX，删掉最旧的一个或者没有名字的一个。
                // 我们刚刚加了一个，所以现在 total = history.length + 1.
                // 我们需要删除一个。

                // 这里逻辑稍微有点复杂因为我们刚刚填补了一个空缺，
                // 如果是填补空缺，那总数增加了。
                // 重新获取列表最稳妥
                const newHistory = await listHistory(env, name, ext, key);
                if (newHistory.length > MAX_BACKUPS) {
                    let sorted = [...newHistory].sort((a, b) => a.ver - b.ver);
                    // 优先删除未命名的
                    const unprotected = sorted.filter(v => !v.meta.customName);
                    if (unprotected.length > 0) {
                        await env.MY_R2_BUCKET.delete(unprotected[0].key);
                    } else {
                        await env.MY_R2_BUCKET.delete(sorted[0].key);
                    }
                }
            }
        }

        // 写入新 v0
        // 新文件也注入时间？通常当前文件就是最新。
        // 但为了保持一致性，可以在这里也注入，或者只在归档时注入。
        // 用户说“直接上传文件的时候...加一个时间参数”。
        // 如果 App 上传时没加，Worker 这里加。
        let finalContent = newContent;
        const nowTime = new Date().toISOString();
        try {
            const c = JSON.parse(newContent);
            // 确保 _backupTime 在最前面
            const { _backupTime, ...rest } = c;
            const newJson = { _backupTime: nowTime, ...rest };
            finalContent = JSON.stringify(newJson);
        } catch (e) { }

        await env.MY_R2_BUCKET.put(key, finalContent, {
            httpMetadata: { contentType: 'application/json' },
            customMetadata: {
                uuid: crypto.randomUUID(),
                originalTime: nowTime,
                contentHash: await sha256(finalContent),
            },
        });

        return json({
            status: 'success', filename: key,
            size: finalContent.length, ...extractSummary(finalContent),
        }, 200, cors);
    } catch (err) {
        return json({ status: 'error', message: err.message }, 500, cors);
    }
}

// ========== 列表 ==========
async function handleList(env, key, cors) {
    try {
        const { name, ext } = splitFilename(key);
        const result = [];

        // 当前版本
        const cur = await env.MY_R2_BUCKET.head(key);
        if (cur) {
            const m = cur.customMetadata || {};
            result.push({
                key, version: 0,
                uuid: m.uuid || null,
                customName: m.customName || null,
                label: m.customName || '当前配置',
                size: cur.size,
                uploaded: m.originalTime || cur.uploaded.toISOString(),
            });
        }

        // 历史版本
        const history = await listHistory(env, name, ext, key);
        history.sort((a, b) => b.ver - a.ver); // 倒序 (时间戳越大越新)

        for (const v of history) {
            result.push({
                key: v.key, version: v.ver, // 这里 version 可能是巨大整数(时间戳)
                uuid: v.meta.uuid || null,
                customName: v.meta.customName || null,
                label: v.meta.customName || '备份', // 简化，前端加序号
                size: v.size,
                // 如果 metadata 没时间，尝试从 ver 还原时间? 
                // ver 是 YYYYMMDDHHmmss (number) -> 转换回 ISO 字符串? 
                // 为了兼容性，最好还是优先用 meta.originalTime
                uploaded: v.meta.originalTime || v.uploaded,
            });
        }

        return json({
            status: 'success', filename: key,
            totalVersions: result.length, versions: result,
        }, 200, cors);
    } catch (err) {
        return json({ status: 'error', message: err.message }, 500, cors);
    }
}

// ========== 去重 (保护已命名文件) ==========
async function handleDedup(env, key, MAX_BACKUPS, cors) {
    try {
        const { name, ext } = splitFilename(key);
        const all = [];

        const cur = await env.MY_R2_BUCKET.get(key);
        if (cur) {
            const t = await cur.text();
            all.push({ key, ver: 0, hash: await normalizedHash(t), meta: cur.customMetadata || {} });
        }

        const history = await listHistory(env, name, ext, key);
        for (const v of history) {
            const obj = await env.MY_R2_BUCKET.get(v.key);
            if (!obj) continue;
            const t = await obj.text();
            all.push({ key: v.key, ver: v.ver, hash: await normalizedHash(t), meta: obj.customMetadata || {} });
        }

        // 按版本号升序
        all.sort((a, b) => a.ver - b.ver);
        const seenHashes = new Set();
        const toDelete = [];

        for (const item of all) {
            // 保护机制：有名字的绝不删除，且会占用 hash 位置防止后续重复
            if (item.meta && item.meta.customName) {
                seenHashes.add(item.hash);
                continue;
            }

            if (seenHashes.has(item.hash)) {
                toDelete.push(item);
            } else {
                seenHashes.add(item.hash);
            }
        }

        if (toDelete.length === 0) {
            return json({ status: 'success', message: '无重复版本', removed: 0, remaining: all.length }, 200, cors);
        }

        for (const d of toDelete) await env.MY_R2_BUCKET.delete(d.key);

        return json({
            status: 'success',
            message: `已删除 ${toDelete.length} 个重复版本`,
            removed: toDelete.length, remaining: all.length - toDelete.length,
        }, 200, cors);
    } catch (err) {
        return json({ status: 'error', message: err.message }, 500, cors);
    }
}

// ========== 预览 ==========
async function handlePreview(env, key, cors) {
    try {
        const obj = await env.MY_R2_BUCKET.get(key);
        if (!obj) return json({ status: 'error', message: 'Not Found' }, 404, cors);

        const content = await obj.text();
        const meta = obj.customMetadata || {};
        let details = {};
        try {
            const c = JSON.parse(content);
            details = {
                providerNames: Array.isArray(c.providers) ? c.providers.map(p => String(p.name || p.id || '')).slice(0, 10) : [],
                selectedModel: c.selectedGlobalModelID ? String(c.selectedGlobalModelID) : null,
                temperature: typeof c.temperature === 'number' ? c.temperature : null,
                historyCount: typeof c.historyMessageCount === 'number' ? Math.floor(c.historyMessageCount) : '',
                thinkingMode: typeof c.thinkingMode === 'boolean' ? c.thinkingMode : !!c.thinkingMode,
                memoryEnabled: typeof c.memoryEnabled === 'boolean' ? c.memoryEnabled : !!c.memoryEnabled,
                hasCustomPrompt: !!(c.customSystemPrompt && String(c.customSystemPrompt).length > 0),
            };
        } catch { }

        return json({
            status: 'success', key, uuid: meta.uuid || null,
            customName: meta.customName || null,
            size: content.length,
            uploaded: meta.originalTime || obj.uploaded.toISOString(),
            ...extractSummary(content), details,
        }, 200, cors);
    } catch (err) {
        return json({ status: 'error', message: err.message }, 500, cors);
    }
}

// ==================== 工具函数 ====================

async function listHistory(env, name, ext, mainKey) {
    const list = await env.MY_R2_BUCKET.list({ prefix: name, include: ['customMetadata'] });
    const result = [];
    for (const obj of list.objects) {
        if (obj.key === mainKey) continue;
        if (!obj.key.endsWith(ext)) continue;
        const mid = obj.key.slice(name.length, obj.key.length - ext.length);
        const v = parseInt(mid);
        if (isNaN(v) || v < 1) continue;
        result.push({
            key: obj.key, ver: v,
            meta: obj.customMetadata || {},
            size: obj.size,
            uploaded: obj.uploaded ? obj.uploaded.toISOString() : null,
        });
    }
    return result;
}

function splitFilename(key) {
    const i = key.lastIndexOf('.');
    return { name: i !== -1 ? key.substring(0, i) : key, ext: i !== -1 ? key.substring(i) : '' };
}

async function sha256(text) {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function normalizedHash(text) {
    try {
        const obj = JSON.parse(text);
        // 移除 _backupTime 字段后再计算 hash
        if (obj && typeof obj === 'object') {
            delete obj._backupTime;
        }
        const normalized = JSON.stringify(sortKeys(obj));
        return await sha256(normalized);
    } catch {
        return await sha256(text);
    }
}

function sortKeys(val) {
    if (val === null || typeof val !== 'object') return val;
    if (Array.isArray(val)) return val.map(sortKeys);
    const sorted = {};
    for (const k of Object.keys(val).sort()) sorted[k] = sortKeys(val[k]);
    return sorted;
}

function extractSummary(text) {
    try {
        const c = JSON.parse(text);
        return { providers: c.providers?.length ?? 0, memories: c.memories?.length ?? 0, sessions: c.sessions?.length ?? 0 };
    } catch { return {}; }
}

function json(data, status = 200, extra = {}) {
    return new Response(JSON.stringify(data), {
        status, headers: { 'Content-Type': 'application/json', ...extra },
    });
}
