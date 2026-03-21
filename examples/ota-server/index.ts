// Simple OTA update server for Tano apps
// Deploy this alongside your app bundles

const UPDATES_DIR = './updates';

Bun.serve({
    port: 3001,
    async fetch(req) {
        const url = new URL(req.url);

        if (url.pathname === '/manifest') {
            const channel = url.searchParams.get('channel') || 'production';
            const currentHash = url.searchParams.get('current') || '';

            // Read the latest manifest for this channel
            const manifestPath = `${UPDATES_DIR}/${channel}/manifest.json`;
            const file = Bun.file(manifestPath);

            if (!await file.exists()) {
                return Response.json({ error: 'No updates available' }, { status: 404 });
            }

            const manifest = await file.json();

            // If client already has this version, return 204
            if (manifest.hash === currentHash) {
                return new Response(null, { status: 204 });
            }

            return Response.json(manifest);
        }

        // Serve bundle files
        if (url.pathname.startsWith('/bundles/')) {
            const filePath = `${UPDATES_DIR}${url.pathname.replace('/bundles', '')}`;
            const file = Bun.file(filePath);
            if (await file.exists()) {
                return new Response(file);
            }
            return new Response('Not Found', { status: 404 });
        }

        return Response.json({
            name: 'Tano OTA Server',
            endpoints: {
                manifest: '/manifest?channel=production&current=<hash>',
                bundles: '/bundles/<channel>/<filename>'
            }
        });
    }
});

console.log('Tano OTA Server running on port 3001');
