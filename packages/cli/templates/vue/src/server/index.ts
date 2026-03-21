console.log('[{{APP_NAME}}] Starting server...');

const db = { items: [] as { id: number; text: string; done: boolean }[] };
let nextId = 1;

export default Bun.serve({
    port: 18899,
    hostname: '127.0.0.1',
    fetch(req) {
        const url = new URL(req.url);

        if (url.pathname === '/api/todos') {
            if (req.method === 'GET') {
                return Response.json(db.items);
            }
            if (req.method === 'POST') {
                const body = req.body ? JSON.parse(req.body as any) : {};
                const item = { id: nextId++, text: body.text || '', done: false };
                db.items.push(item);
                return Response.json(item, { status: 201 });
            }
        }

        if (url.pathname.startsWith('/api/todos/') && req.method === 'PATCH') {
            const id = parseInt(url.pathname.split('/').pop() || '0');
            const item = db.items.find(i => i.id === id);
            if (item) {
                const body = req.body ? JSON.parse(req.body as any) : {};
                if ('done' in body) item.done = body.done;
                if ('text' in body) item.text = body.text;
                return Response.json(item);
            }
            return Response.json({ error: 'Not found' }, { status: 404 });
        }

        if (url.pathname.startsWith('/api/todos/') && req.method === 'DELETE') {
            const id = parseInt(url.pathname.split('/').pop() || '0');
            db.items = db.items.filter(i => i.id !== id);
            return Response.json({ ok: true });
        }

        if (url.pathname === '/api/info') {
            return Response.json({ runtime: Bun.version, app: '{{APP_NAME}}' });
        }

        return new Response('Not Found', { status: 404 });
    }
});

console.log('[{{APP_NAME}}] Server running on port 18899');
