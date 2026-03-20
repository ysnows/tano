/**
 * {{APP_NAME}} — Bun server
 *
 * This server runs natively on the device via the Tano runtime.
 * It handles API requests from the WebView frontend and has full
 * access to native plugins through the Tano bridge.
 */

const server = Bun.serve({
    port: 3000,

    async fetch(req: Request): Promise<Response> {
        const url = new URL(req.url);

        // API routes
        if (url.pathname === "/api/hello") {
            return Response.json({
                message: "Hello from {{APP_NAME}}!",
                timestamp: new Date().toISOString(),
                runtime: "Bun " + Bun.version,
            });
        }

        if (url.pathname === "/api/health") {
            return Response.json({ status: "ok" });
        }

        // Serve the web UI for all other routes
        const indexPath = new URL("../web/index.html", import.meta.url).pathname;
        const file = Bun.file(indexPath);

        if (await file.exists()) {
            return new Response(file, {
                headers: { "Content-Type": "text/html" },
            });
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`{{APP_NAME}} server running at http://localhost:${server.port}`);
