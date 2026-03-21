/**
 * Tano Chat App — Server with Groq LLM Integration
 *
 * Set GROQ_API_KEY in your environment or tano.config.ts env.
 * Falls back to simulated streaming if no API key is set.
 */

const GROQ_API_KEY = Bun.env?.GROQ_API_KEY || '';
const GROQ_MODEL = 'llama-3.3-70b-versatile';
const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';

const webDir = new URL('../web', import.meta.url).pathname;

console.log('[Chat] Starting server...');
console.log('[Chat] Groq API:', GROQ_API_KEY ? 'configured' : 'not set (using simulated responses)');

interface ChatMessage {
    role: 'user' | 'assistant' | 'system';
    content: string;
}

const conversationHistory: ChatMessage[] = [
    { role: 'system', content: 'You are a helpful assistant running inside a Tano mobile app. Keep responses concise.' }
];

export default Bun.serve({
    port: 18899,
    hostname: '127.0.0.1',

    async fetch(req) {
        const url = new URL(req.url);

        // POST /api/chat — streaming chat via SSE
        if (url.pathname === '/api/chat' && req.method === 'POST') {
            const body = await req.json().catch(() => ({}));
            const userMessage = (body as any).message || '';

            if (!userMessage.trim()) {
                return Response.json({ error: 'Message is required' }, { status: 400 });
            }

            conversationHistory.push({ role: 'user', content: userMessage });

            if (GROQ_API_KEY) {
                return streamFromGroq(conversationHistory);
            } else {
                return simulateStream(userMessage);
            }
        }

        // POST /api/chat/clear — reset conversation
        if (url.pathname === '/api/chat/clear' && req.method === 'POST') {
            conversationHistory.length = 1; // Keep system prompt
            return Response.json({ ok: true });
        }

        // GET /api/info
        if (url.pathname === '/api/info') {
            return Response.json({
                app: 'Tano Chat',
                runtime: Bun.version,
                llm: GROQ_API_KEY ? `groq/${GROQ_MODEL}` : 'simulated',
            });
        }

        // Static file serving
        if (url.pathname === '/' || url.pathname === '/index.html') {
            const file = Bun.file(`${webDir}/index.html`);
            if (await file.exists()) {
                return new Response(file, { headers: { 'Content-Type': 'text/html' } });
            }
        }

        return new Response('Not Found', { status: 404 });
    }
});

async function streamFromGroq(messages: ChatMessage[]): Promise<Response> {
    const groqRes = await fetch(GROQ_URL, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${GROQ_API_KEY}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            model: GROQ_MODEL,
            messages,
            stream: true,
            max_tokens: 1024,
        }),
    });

    if (!groqRes.ok) {
        const errorText = await groqRes.text();
        conversationHistory.pop(); // Remove failed user message
        return Response.json({ error: `Groq API error: ${groqRes.status}` }, { status: 502 });
    }

    let fullResponse = '';

    const stream = new ReadableStream({
        async start(controller) {
            const encoder = new TextEncoder();
            const reader = groqRes.body?.getReader();
            if (!reader) { controller.close(); return; }

            const decoder = new TextDecoder();
            let buffer = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';

                for (const line of lines) {
                    if (!line.startsWith('data: ')) continue;
                    const data = line.slice(6).trim();

                    if (data === '[DONE]') {
                        controller.enqueue(encoder.encode('data: [DONE]\n\n'));
                        conversationHistory.push({ role: 'assistant', content: fullResponse });
                        controller.close();
                        return;
                    }

                    try {
                        const parsed = JSON.parse(data);
                        const token = parsed.choices?.[0]?.delta?.content || '';
                        if (token) {
                            fullResponse += token;
                            controller.enqueue(encoder.encode(`data: ${JSON.stringify({ token })}\n\n`));
                        }
                    } catch { /* skip malformed */ }
                }
            }

            if (fullResponse) {
                conversationHistory.push({ role: 'assistant', content: fullResponse });
            }
            controller.enqueue(encoder.encode('data: [DONE]\n\n'));
            controller.close();
        }
    });

    return new Response(stream, {
        headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
        }
    });
}

async function simulateStream(userMessage: string): Promise<Response> {
    const words = `I received your message: "${userMessage}". This is a simulated response — set GROQ_API_KEY in your environment to use real AI (Llama 3.3 70B via Groq).`.split(' ');

    conversationHistory.push({ role: 'assistant', content: words.join(' ') });

    const stream = new ReadableStream({
        async start(controller) {
            const encoder = new TextEncoder();
            for (const word of words) {
                controller.enqueue(encoder.encode(`data: ${JSON.stringify({ token: word + ' ' })}\n\n`));
                await Bun.sleep(30);
            }
            controller.enqueue(encoder.encode('data: [DONE]\n\n'));
            controller.close();
        }
    });

    return new Response(stream, {
        headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
        }
    });
}

console.log('[Chat] Server running on port 18899');
