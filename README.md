# OpenChat ⌚️🤖

<p align="center">
  <img src="https://img.shields.io/badge/Platform-watchOS_11.5+-lightgrey.svg?style=flat" alt="Platform watchOS">
  <img src="https://img.shields.io/badge/Language-Swift-orange.svg?style=flat" alt="Language Swift">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="License">
</p>

**OpenChat ** 是一款专为 Apple 设备打造的终极 AI 伴侣。它不仅仅是一个简单的 API 调用工具，而是一个针对腕上交互进行深度打磨、功能完备的智能终端。

无论您是开发者、学生还是 AI 爱好者，都能通过它在手腕上随时随地连接最强大的大语言模型。

---

## 🔥 核心特性

### 1. 极致的对话与交互体验

- **🚀 流畅流式响应 (Optimized Streaming)** *(v1.6 重构)*
  - 采用 Server-Sent Events (SSE) 技术，实现打字机效果，毫秒级响应。
  - **注视点渲染 (Foveated Rendering)**: 流式文本按行拆分，`LazyVStack` 仅渲染屏幕可见行，长文本性能恒定。
  - **流式状态隔离**: 流式期间不修改 `sessions`，只更新轻量 `streamingText`，零全量 diff。
  - **三种渲染模式**可选（设置 → 文本渲染）：
    - **实时渲染**: 流式时实时显示 Markdown 格式（默认）
    - **完成后渲染**: 流式时纯文本，完成后自动渲染（推荐⭐）
    - **手动渲染**: 流式时纯文本，点击按钮手动渲染（最佳性能）
  - 150ms 节流更新，O(N) 状态机解析。
- **🧠 深度思考**
  - 完美支持推理模型，实时流式显示 `<think>` 思考过程。
  - 独立的思考内容折叠视图，点击即可展开查看 AI 的推理逻辑。
- **🎨 个性化主题**
  - 支持切换多种气泡配色风格，打造专属手表界面。
- **⚡️ 智能上下文管理**
  - **滑动窗口**: 发送请求时自动截取最近可配置条数的消息作为上下文（5-50 条可选）。
  - **完整记录**: 您的所有聊天历史都完整保存在本地，随时可回溯查看。
- **🛠 强大的消息控制**
  - **行内编辑 (Inline Edit)**: 发错消息或想微调 Prompt？直接点击气泡上的 ✏️ 按钮，原地修改，AI 自动重新生成。
  - **重新生成 (Regenerate)**: 对回答不满意？点击用户消息下方的 🔄 按钮，立即换个角度回答。
  - **随时中断 (Stop Generation)**: 发现苗头不对或内容太长？点击输入框旁的 ⏹️ 按钮，立即终止生成。
- **⌨️ 原生级输入优化**
  - **键盘协同 (Continuity Keyboard)**: 完美解决 Apple Watch 与 iPhone 键盘连接不稳定的问题，打字不再"吞字"。
  - **Draft State 模式**: 采用临时草稿态设计，防止视图刷新打断输入流程。

### 2. 桌面级渲染引擎

在 40mm/44mm 的小屏幕上，也能获得不输桌面的阅读体验。

- **📝 Markdown 全解析**
  - 支持 **粗体**、*斜体*、`代码片段`、链接等标准语法。
  - **代码高亮**: 支持多种编程语言的语法高亮显示。
  - **三种渲染模式** *(v1.5)*: 实时/完成后/手动，性能与效果自由平衡。
- **📊 表格 (Tables)**
  - 专为手表优化的 "Vertical Bar" 排版风格。
  - 使用短分隔符 (`────`)，确保在小屏幕上也能清晰查看复杂数据表。
- **➗ 专业数学公式 (LaTeX)** *(v1.5 增强)*
  - 内置高性能 LaTeX 解析器，无需联网即可渲染。
  - 支持 **矩阵 (Matrix)**、**向量 (Vector)**、**嵌套分数**、**根号**、**积分**、**答案框** (`\boxed`) 等。
  - 增强嵌套支持：`\frac` 支持 30 层，`\sqrt` 支持 20 层。
  - 完美还原物理公式（如 `\hat{i}`, `\vec{F}`）和行内公式。
  - **双模式可选**: 
    - **简单模式** (默认): 使用 Unicode 符号替换，稳定可靠。
    - **高级模式**: 使用 FlowLayout 图文混排，效果更精细但可能有排版问题。
- **🧐 源码/预览切换 (Raw Toggle)**
  - 每条消息右下角提供 `{}` 按钮。
  - 一键切换"渲染视图"和"原始 Markdown 文本"，方便复制 Prompt 或检查公式源码。

### 3. 多模态与环境感知

- **📷 视觉模型 (Vision)**
  - 支持 GPT-4o、Gemini-2.5-Pro 等视觉模型。
  - 直接从手表相册选择图片发送，让 AI 帮你"看图说话"。
- **📍 环境注入 (Environment Injection)**
  - **时间感知**: 自动将当前准确时间注入 System Prompt，AI 再也不会乱说年份日期
  - **位置感知**: (可选) 获取当前地理位置坐标注入 Prompt，提供更精准的本地化服务（如天气查询）。

### 4. WatchOS 原生集成

深度融合 Apple Watch 系统特性，像原生 App 一样自然。

- **🧩 表盘复杂功能 (Complications)**
  - 支持角标、圆形等多种表盘位置。
  - 抬腕即可点击图标，一键唤醒 AI。
- **🥞 智能叠放组件 (Smart Stack Widget)**
  - 在表盘下滚动的智能叠放中查看 **最后一条消息** 和 **对话标题**。
  - 提供"新对话"快捷入口。
  - *特别优化*: 采用轻量级数据读取机制，极低内存占用，永不崩溃。
- **📳 触觉反馈 (Haptics)**
  - 发送成功、收到回复、报错震动、停止生成... 每一个操作都有细腻的震动反馈。
- **🌙 沉浸式 UI**
  - 全黑背景设计，完美契合 OLED 屏幕，省电且护眼。
  - 支持动态字体 (Dynamic Type)。

### 5. 高效的模型管理 (v1.4 新增)

- **🕐 最近使用模型**
  - 模型选择界面首先展示上次使用的模型，无需翻找。
- **🔍 模型搜索**
  - 在模型选择页和供应商配置页快速搜索模型。
  - 支持按模型 ID 或显示名称过滤。
- **💾 模型列表缓存**
  - 验证一次，永久缓存，启动不再重复请求 API。
  - 1 小时智能缓存策略，可手动强制刷新。
- **🔄 批量验证**
  - 设置页一键验证所有供应商，自动缓存全部模型列表。
- **📤 配置导出**
  - 将全部配置导出为 JSON，便于备份和恢复。

### 6. 全面的模型生态

不再受限于单一厂商，把全世界的 AI 模型装进手表。

- **🌍 预设主流厂商**
  - **OpenAI** (GPT-3.5, GPT-4, GPT-4o)
  - **Google Gemini** (Gemini-Pro, Flash, 1.5)
  - **DeepSeek** (深度求索 V3/R1)
  - **Zhipu AI** (智谱 GLM-4)
  - **Aliyun Qwen** (通义千问)
  - **SiliconFlow** (硅基流动 - 聚合 DeepSeek/Qwen 等开源模型)
  - **ModelScope** (魔搭社区)
  - **OpenRouter** (聚合平台)
  - **Nvidia** (NIM 云平台)
  - **OpenCode Zen** (v1.4 新增)
- **🔧 高级自定义**
  - **自定义模型 ID**: 只要服务商支持，任何新出的模型 (如 `gpt-4o-2029-xx`) 都能手动填写 ID 使用。
  - **自建代理 (BYOL)**: 支持任何兼容 OpenAI/chat/completions;/responses、anthropic/v1/messages、gemini/v1beta/models 格式的接口。
  - **本地模型**: 连接你电脑上的 **Ollama** 服务，实现完全离线的本地 AI 对话。

### 7. 辅助模型 (Helper Model) *(v1.7 新增)*

为了降低成本并提高响应速度，引入了 **Helper Model** 概念，专用于后台任务。

- **降本增效**:
  - 自动接管 **会话标题生成** 和 **记忆提取** 等后台任务。
  - 建议配置为轻量级模型（如 `Gemini Flash` 或 `gpt-4o-mini`），不再消耗昂贵的主模型额度。
- **独立配置**:
  - 在 **设置 -> 高级** 中独立选择辅助模型，与主对话模型互不干扰。

### 8. 隐私与安全

- **🔒 数据本地化**
  - 所有聊天记录 (`UserDefaults`) 和 API Key 仅存储在您的 Apple Watch 本地。
  - 绝不上传至任何中间服务器或第三方统计平台。
- **🛡 网络安全**
  - 遵循 Apple ATS (App Transport Security) 标准。
  - 支持 HTTPS 安全连接。

### 9. ☁️ 云端备份与同步 (Cloud Sync) *(v2.0 核心)*

- **R2 对象存储**
  - 利用 Cloudflare R2 低成本存储您的配置、聊天记录和记忆。
  - 支持 **跨设备同步** (未来计划)。
- **版本控制**:
  - 自动保留历史备份版本。
  - 支持 **增量合并** (Merge) 和 **完整覆盖** (Overwrite) 两种恢复模式。
  - 智能去重机制，节省存储空间。

### 10. 🧠 长期记忆与 RAG (v2.0 核心)

> "让 AI 真正记住你。"

- **RAG (检索增强生成)**
  - 将您的记忆和对话历史向量化，存入 Cloudflare Vectorize 或 R2。
  - 在每一次对话中，AI 都会自动"回忆"起相关的过往细节。
- **Workers AI 集成**
  - 利用 Cloudflare Workers AI 运行服务端 Embedding 模型 (如 `qwen-embedding`)。
  - 数据完全私有，不经过任何第三方商业模型接口。
- **自动维度适配**
  - App 自动探测向量维度 (768/1024/1536)，兼容多种 Embedding 模型。

---

## ☁️ Cloudflare Workers 部署指南

本项目依赖 Cloudflare Workers 实现部分高级功能（可选）。

### 1. 配置云端备份 (Cloud Backup)

**代码路径**: `Workers/_worker.js`

1. **创建 R2 存储桶**: 在 Cloudflare Dashboard 创建一个 R2 Bucket (例如 `chatbot-backup`)。
2. **创建 Worker**: 创建一个新的 Worker (例如 `chatbot-sync`).
3. **绑定 R2**:
   - 在 Worker 设置 -> Settings -> Variables -> R2 Bucket Bindings。
   - 变量名填写 `MY_R2_BUCKET`，绑定到你刚才创建的 Bucket。
4. **部署代码**: 将 `Workers/_worker.js` 的内容复制到 Worker 编辑器中。
   - **修改密钥**: 找到代码顶部的 `AUTH_KEY`，修改为你自己的密钥 (例如 "my-secret-key-2026")。
5. **App 配置**:
   - 打开 App 设置 -> 云端数据管理 -> 云备份设置。
   - 填写 Worker URL (如 `https://chatbot-sync.your-domain.workers.dev/config.json`)。
   - 填写你在代码中设置的 Auth Key。

### 2. 配置向量模型 (Workers AI)

**代码路径**: `Workers/VectorWorker.js`

1. **创建 Worker**: 创建一个新的 Worker (例如 `chatbot-vector`).
2. **绑定 Workers AI**:
   - 在 Worker 设置 -> Settings -> Variables -> Workers AI。
   - 变量名填写 `AI`。
3. **部署代码**: 将 `Workers/VectorWorker.js` 的内容复制到 Worker 编辑器中。
   - 默认使用 `@cf/qwen/qwen3-embedding-0.6b` 模型 (维度 1024)。
4. **App 配置**:
   - 打开 App 设置 -> 记忆与向量 (高级)。
   - 开启 "记忆功能"。
   - 填写 Worker URL (如 `https://chatbot-vector.your-domain.workers.dev`)。
   - 点击 "测试连接" 验证。

---

## 📚 API 文档 (API Reference)

如果您是开发者，可以通过以下 API 与部署在 Cloudflare Workers 上的服务进行交互。

### 1. 云端备份服务 (`_worker.js`)

**Base URL**: `https://<your-worker-name>.<your-subdomain>.workers.dev`

**Authentication**:
所有请求必须包含 Header: `X-Auth-Key: <your-configured-auth-key>`

| 方法 | 路径 | 描述 | 参数/Body |
| :--- | :--- | :--- | :--- |
| `GET` | `/list/<filename>` | 获取文件及其历史版本列表 | 无 |
| `GET` | `/<filename>` | 下载最新版本文件内容 | 无 |
| `PUT` | `/<filename>` | 上传/更新文件 (自动创建历史版本) | Body: JSON 文本内容 |
| `DELETE` | `/<filename>` | 删除指定文件 (慎用) | 无 |
| `POST` | `/rename/<filename>` | 重命名指定版本的备份 | Body: `{ "name": "自定义名称" }` |
| `POST` | `/dedup/<filename>` | 触发智能去重，清理重复版本 | 无 |
| `GET` | `/preview/<key>` | 获取指定版本的内容预览与元数据 | <key> 为完整对象 Key |

**调用示例 (cURL)**:

```bash
# 上传配置文件
curl -X PUT "https://api.example.com/config.json" \
     -H "X-Auth-Key: my-secret-2026" \
     -d '{"model": "gpt-4", "theme": "blue"}'

# 获取历史列表
curl "https://api.example.com/list/config.json" \
     -H "X-Auth-Key: my-secret-2026"
```

### 2. 向量模型服务 (`VectorWorker.js`)

**Base URL**: `https://<your-vector-worker>.<your-subdomain>.workers.dev`

**Authentication**: 无 (或在代码中自行添加)

| 方法 | 路径 | 描述 | Body |
| :--- | :--- | :--- | :--- |
| `POST` | `/` | 将文本转换为向量 (Embedding) | `{ "text": "需要转换的文本" }` |

**Response**:
直接返回 Cloudflare Workers AI 的原始响应 (通常包含 `shape`, `data` 等字段)。

**调用示例 (cURL)**:

```bash
curl -X POST "https://vector.example.com/" \
     -H "Content-Type: application/json" \
     -d '{"text": "Hello World"}'
```

---

## 🚀 安装与部署

### 方式一：直接安装 (IPA)

我们提供了预编译的 `.ipa` 文件，这是最简单的安装方式。

1. 前往 **[Releases](https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch/releases)** 下载最新版本。
2. 使用 **TrollStore** (推荐)、**AltStore**、**Sideloadly** 或**爱思助手**进行签名安装。

### 方式二：源码编译 (Xcode)

如果您担心隐私或需要调试，可以从源码自行编译。

1. **环境准备**: macOS + Xcode 15+ + Apple Watch (watchOS 10+)
2. **克隆代码**: `git clone https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch.git`
3. **项目配置**:
   - 打开 Xcode，新建一个 watchOS App 项目。
   - 将 `ChatBot Watch App` 目录下的所有文件拖入新项目。
   - **关键**: 移除新项目自动生成的 `ContentView.swift` 和 `App.swift`，确保使用本项目的 `ChatBotApp.swift` 作为 `App` 入口。
4. **配置 Widget (可选)**:
   - 如果需要 Smart Stack 小组件功能，需要在 Xcode 中新建一个 **Widget Extension** 目标。
   - 将 `ChatBotWidget` 目录拖入新建的 Widget Extension 目标中。
   - 确保 `ChatBotWidgetBundle.swift` 是 Widget Extension 的入口点 (`@main`)。
5. **权限设置**:
   - 在 `Info.plist` 中添加 `Privacy - Photo Library Usage Description` (用于发图片功能)。
   - 若使用非 HTTPS 自建节点，需配置 `App Transport Security Settings` -> `Allow Arbitrary Loads` = YES。
6. **编译**: 选择您的手表作为目标，点击 Run (⌘R)。

---

## ⚙️ 使用指南

### 1. 配置服务

1. 打开 App，在首页左滑进入 **Settings** (设置)。
2. 点击 **Model Provider**，选择您的服务商 (如 OpenAI 或 DeepSeek)。
3. 输入您的 `API Key` (从各官网获取)。
4. *(可选)* 点击 **Verify** 验证连通性。

### 2. 选择模型

1. 在设置页点击 **Model**。
2. 您可以从 **Saved Models** (已保存) 列表中选择。
3. 也可以点击 **Add Custom Model** 手动输入模型 ID (如 `deepseek-chat`)。

### 3. 开始对话

1. 回到首页，点击 **New Chat**。
2. 支持语音转文字、手写或键盘输入。
3. 点击右下角相册图标可发送图片。

### 4. 管理对话

- 在首页历史列表中，**左滑**某个对话可进行删除 (含二次确认)。
- 点击历史对话可无缝恢复上下文。

### 5. 使用 Smart Stack Widget 小组件

1. **添加组件**: 在手表表盘上，长按进入编辑模式 -> 向下滚动到智能叠放 -> 点击"+"添加 "ChatBot Quick Access" 组件。
2. **查看最新消息**: 组件会自动显示您最近一次对话的标题和最后一条消息摘要。
3. **快速新建对话**: 点击组件底部的 "New Chat" 按钮，可直接跳转到 App 并开始新对话。

> **注意**: 组件数据会在您每次发送或接收消息后自动刷新。

### 6. 使用表盘快捷方式 (Complication)

1. **添加快捷方式**: 在手表表盘上，长按进入编辑模式 -> 选择表盘上的一个空位 -> 滚动找到 "ChatBot" 图标并选择。
2. **一键唤醒**: 之后只需点击表盘上的图标，即可直接打开 OpenChat App。

### 7. 配置渲染模式 *(v1.5)*

1. 进入 **Settings** -> **文本渲染** 区域。
2. **Markdown 渲染模式**: 选择流式输出的渲染策略：
   - **实时渲染**: 流式时实时显示格式，适合短文本
   - **完成后渲染**: 流式时纯文本，完成后自动渲染（推荐）
   - **手动渲染**: 流式时纯文本，点击 `{}` 按钮手动渲染（最佳性能）
3. **启用 LaTeX 渲染**: 开启后，数学公式 (如 `\frac{a}{b}`, `\sqrt{2}`, `\boxed{answer}`) 会被转换为可读格式。
4. **高级渲染模式** (可选): 开启后使用更精细的图文混排渲染。
   - ⚠️ 高级模式可能导致复杂公式排版异常，如遇问题请关闭此选项。

---

## ❓ 常见问题 (FAQ)

**Q: 为什么生成的公式显示乱码？**

A: 请点击气泡右下角的 `{}` 按钮查看原始文本。如果原始文本是标准的 LaTeX，通常是渲染器的限制。我们已针对绝大多数常用数学符号进行了适配。

**Q: Widget 显示空白或崩溃？**

A: 请确保您已更新到最新版本。我们已在 v1.2 中重构了 Widget 的数据读取逻辑，彻底修复了内存溢出问题。

**Q: 如何连接本地 Ollama？**

A: 确保您的电脑和手表在同一局域网。将 API Base URL 设置为 `http://YOUR_PC_IP:11434/v1`，并在 Info.plist 中允许 HTTP 请求。

---

## ⚠️ 免责声明 (Disclaimer)

- 本项目仅为客户端工具，不提供任何 AI 模型服务。
- 请遵守您所在地区关于 AI 使用的相关法律法规。
- API Key 存储在本地，请勿在公共设备上通过截图等方式泄露 Key。

## 📄 License

MIT License
