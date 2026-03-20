console.log('[Tano Demo] Starting server...');

var server = Bun.serve({
    port: 18899,
    hostname: '127.0.0.1',
    fetch: function(req) {
        var url = new URL(req.url);

        if (url.pathname === '/') {
            return new Response('<html><body><h1>Tano Demo</h1><p>Runtime: ' + Bun.version + '</p></body></html>', {
                headers: { 'content-type': 'text/html' }
            });
        }

        if (url.pathname === '/api/info') {
            return Response.json({
                runtime: Bun.version,
                platform: 'ios',
                env: Bun.env.TANO_VERSION || 'unknown'
            });
        }

        return new Response('Not Found', { status: 404 });
    }
});

console.log('[Tano Demo] Server running on port ' + server.port);
