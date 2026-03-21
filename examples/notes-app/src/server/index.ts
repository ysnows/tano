/**
 * NotesApp — Bun server with Notes CRUD API
 *
 * This server runs natively on the device via the Tano runtime.
 * It provides a REST API for managing notes, using an in-memory
 * store. In production, swap with @tano/plugin-sqlite for persistence.
 */

interface Note {
    id: number;
    title: string;
    content: string;
    createdAt: string;
    updatedAt: string;
}

const notes: Note[] = [];
let nextId = 1;

function now() {
    return new Date().toISOString();
}

const webDir = new URL("../web", import.meta.url).pathname;

const server = Bun.serve({
    port: 18899,
    hostname: "127.0.0.1",

    async fetch(req) {
        const url = new URL(req.url);

        // ---------- API Routes ----------

        // GET /api/notes — list all notes
        if (url.pathname === "/api/notes" && req.method === "GET") {
            return Response.json(notes);
        }

        // GET /api/notes/:id — get a single note
        if (url.pathname.startsWith("/api/notes/") && req.method === "GET") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            const note = notes.find((n) => n.id === id);
            if (!note) return Response.json({ error: "Not found" }, { status: 404 });
            return Response.json(note);
        }

        // POST /api/notes — create a note
        if (url.pathname === "/api/notes" && req.method === "POST") {
            const body = await req.json();
            const title = ((body as any).title || "").trim();
            const content = ((body as any).content || "").trim();
            if (!title) {
                return Response.json({ error: "Title is required" }, { status: 400 });
            }
            const note: Note = {
                id: nextId++,
                title,
                content,
                createdAt: now(),
                updatedAt: now(),
            };
            notes.push(note);
            return Response.json(note, { status: 201 });
        }

        // PATCH /api/notes/:id — update a note
        if (url.pathname.startsWith("/api/notes/") && req.method === "PATCH") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            const note = notes.find((n) => n.id === id);
            if (!note) return Response.json({ error: "Not found" }, { status: 404 });

            const body = await req.json();
            if ("title" in (body as any)) note.title = (body as any).title;
            if ("content" in (body as any)) note.content = (body as any).content;
            note.updatedAt = now();
            return Response.json(note);
        }

        // DELETE /api/notes/:id — delete a note
        if (url.pathname.startsWith("/api/notes/") && req.method === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            const idx = notes.findIndex((n) => n.id === id);
            if (idx === -1) return Response.json({ error: "Not found" }, { status: 404 });
            notes.splice(idx, 1);
            return Response.json({ ok: true });
        }

        // GET /api/info — app info
        if (url.pathname === "/api/info") {
            return Response.json({
                app: "NotesApp",
                runtime: `Bun ${Bun.version}`,
                noteCount: notes.length,
            });
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

console.log(`[NotesApp] Server running at http://localhost:${server.port}`);
