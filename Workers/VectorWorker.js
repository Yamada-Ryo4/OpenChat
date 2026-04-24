export default {
    async fetch(request, env, ctx) {
        // 1. 只处理 POST 请求
        if (request.method !== 'POST') {
            return new Response('请发送 POST 请求', { status: 405 });
        }

        try {
            // 2. 获取输入的文本
            const body = await request.json();
            const text = body.text;

            if (!text) {
                return new Response('缺少 "text" 参数', { status: 400 });
            }

            // 3. 调用 Qwen3 Embedding 模型
            // 确保你在后台设置的变量名是 "AI"
            const response = await env.AI.run('@cf/qwen/qwen3-embedding-0.6b', {
                text: text
            });

            // 4. 返回 JSON 结果
            return Response.json(response);

        } catch (e) {
            // 错误处理
            return new Response(`运行出错: ${e.message}`, { status: 500 });
        }
    },
};
