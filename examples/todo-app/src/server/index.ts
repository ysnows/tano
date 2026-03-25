/**
 * TodoApp — Bun server with SQLite persistence
 *
 * This server runs natively on the device via the Tano runtime.
 * It uses the @tano/plugin-sqlite plugin to persist todos in a
 * local SQLite database on the device.
 */

import { Database } from "bun:sqlite";

const db = new Database("todos.db");
db.run("PRAGMA journal_mode = WAL");

db.run(`
    CREATE TABLE IF NOT EXISTS todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        priority TEXT NOT NULL DEFAULT 'medium',
        due_date TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
`);

// Migrate: add priority/due_date if missing
try { db.run("ALTER TABLE todos ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'"); } catch {}
try { db.run("ALTER TABLE todos ADD COLUMN due_date TEXT"); } catch {}

const stmts = {
    getAll: db.prepare("SELECT * FROM todos ORDER BY done ASC, CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END, created_at DESC"),
    insert: db.prepare("INSERT INTO todos (text, priority, due_date) VALUES (?, ?, ?) RETURNING *"),
    update: db.prepare("UPDATE todos SET text = ?, done = ?, priority = ?, due_date = ? WHERE id = ? RETURNING *"),
    delete: db.prepare("DELETE FROM todos WHERE id = ?"),
    clearDone: db.prepare("DELETE FROM todos WHERE done = 1"),
    stats: db.prepare("SELECT COUNT(*) as total, SUM(done) as done FROM todos"),
};

function fmt(row: any) {
    return {
        id: row.id,
        text: row.text,
        done: Boolean(row.done),
        priority: row.priority,
        dueDate: row.due_date,
        createdAt: row.created_at,
    };
}

const webDir = new URL("../web", import.meta.url).pathname;

const server = Bun.serve({
    port: 18899,
    hostname: "127.0.0.1",

    async fetch(req) {
        const url = new URL(req.url);
        const m = req.method;

        // GET /api/todos
        if (url.pathname === "/api/todos" && m === "GET") {
            return Response.json(stmts.getAll.all().map(fmt));
        }

        // POST /api/todos
        if (url.pathname === "/api/todos" && m === "POST") {
            const body = await req.json();
            const text = (body.text || "").trim();
            if (!text) return Response.json({ error: "Text is required" }, { status: 400 });
            const row = stmts.insert.get(text, body.priority || "medium", body.dueDate || null);
            return Response.json(fmt(row), { status: 201 });
        }

        // PATCH /api/todos/:id
        if (url.pathname.startsWith("/api/todos/") && m === "PATCH") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });

            // Get existing
            const existing = db.prepare("SELECT * FROM todos WHERE id = ?").get(id) as any;
            if (!existing) return Response.json({ error: "Not found" }, { status: 404 });

            const body = await req.json();
            const row = stmts.update.get(
                "text" in body ? body.text : existing.text,
                "done" in body ? (body.done ? 1 : 0) : existing.done,
                "priority" in body ? body.priority : existing.priority,
                "dueDate" in body ? body.dueDate : existing.due_date,
                id,
            );
            return Response.json(fmt(row));
        }

        // DELETE /api/todos/:id
        if (url.pathname.startsWith("/api/todos/") && url.pathname !== "/api/todos/clear-done" && m === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            stmts.delete.run(id);
            return Response.json({ ok: true });
        }

        // POST /api/todos/clear-done
        if (url.pathname === "/api/todos/clear-done" && m === "POST") {
            stmts.clearDone.run();
            return Response.json(stmts.getAll.all().map(fmt));
        }

        // GET /api/stats
        if (url.pathname === "/api/stats") {
            const s = stmts.stats.get() as any;
            return Response.json({ total: s.total, done: s.done || 0 });
        }

        // GET /api/info
        if (url.pathname === "/api/info") {
            return Response.json({ app: "TodoApp", runtime: `Bun ${Bun.version}`, database: "SQLite (WAL)" });
        }

        // Static files
        if (url.pathname === "/" || url.pathname === "/index.html") {
            const file = Bun.file(`${webDir}/index.html`);
            if (await file.exists()) return new Response(file, { headers: { "Content-Type": "text/html" } });
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`[TodoApp] Server running at http://localhost:${server.port}`);
console.log(`[TodoApp] SQLite database initialized (WAL mode)`);
