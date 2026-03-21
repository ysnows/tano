/**
 * ChatApp — Bun server with SSE streaming
 *
 * This server runs natively on the device via the Tano runtime.
 * It demonstrates Server-Sent Events (SSE) for streaming responses,
 * simulating the token-by-token output of an LLM.
 */

const webDir = new URL("../web", import.meta.url).pathname;

export default Bun.serve({
    port: 18899,
    hostname: "127.0.0.1",

    async fetch(req) {
        const url = new URL(req.url);

        // POST /api/chat — streaming chat response via SSE
        if (url.pathname === "/api/chat" && req.method === "POST") {
            const body = await req.json().catch(() => ({}));
            const message = (body as any).message || "Hello";

            const words = `I received your message: "${message}". This is a simulated streaming response from the on-device Bun server, demonstrating Server-Sent Events (SSE) with Tano. Each word is sent as a separate event to simulate LLM token streaming.`.split(" ");

            const stream = new ReadableStream({
                async start(controller) {
                    const encoder = new TextEncoder();
                    for (const word of words) {
                        controller.enqueue(
                            encoder.encode(`data: ${JSON.stringify({ token: word + " " })}\n\n`)
                        );
                        await Bun.sleep(50);
                    }
                    controller.enqueue(encoder.encode("data: [DONE]\n\n"));
                    controller.close();
                },
            });

            return new Response(stream, {
                headers: {
                    "Content-Type": "text/event-stream",
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                },
            });
        }

        // GET /api/info — app info
        if (url.pathname === "/api/info") {
            return Response.json({ app: "Tano Chat", runtime: Bun.version });
        }

        // ---------- Static File Serving ----------

        if (url.pathname === "/" || url.pathname === "/index.html") {
            const file = Bun.file(`${webDir}/index.html`);
            if (await file.exists()) {
                return new Response(file, {
                    headers: { "Content-Type": "text/html" },
                });
            }
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`[ChatApp] Server running at http://localhost:18899`);
console.log(`[ChatApp] SSE streaming endpoint: POST /api/chat`);
