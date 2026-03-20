/**
 * TodoApp — Bun server with SQLite persistence
 *
 * This server runs natively on the device via the Tano runtime.
 * It uses the @tano/plugin-sqlite plugin to persist todos in a
 * local SQLite database on the device.
 */

import { Database } from "bun:sqlite";

// Initialize SQLite database
const db = new Database("todos.db");
db.run(`
    CREATE TABLE IF NOT EXISTS todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
`);

// Prepared statements for performance
const getAllTodos = db.prepare("SELECT id, text, done, created_at FROM todos ORDER BY created_at DESC");
const insertTodo = db.prepare("INSERT INTO todos (text) VALUES (?) RETURNING id, text, done, created_at");
const updateTodoDone = db.prepare("UPDATE todos SET done = ? WHERE id = ? RETURNING id, text, done, created_at");
const updateTodoText = db.prepare("UPDATE todos SET text = ? WHERE id = ? RETURNING id, text, done, created_at");
const updateTodo = db.prepare("UPDATE todos SET text = ?, done = ? WHERE id = ? RETURNING id, text, done, created_at");
const deleteTodoById = db.prepare("DELETE FROM todos WHERE id = ?");
const clearDoneTodos = db.prepare("DELETE FROM todos WHERE done = 1");

function formatTodo(row: any) {
    return {
        id: row.id,
        text: row.text,
        done: Boolean(row.done),
        createdAt: row.created_at,
    };
}

// Serve the web UI files
const webDir = new URL("../web", import.meta.url).pathname;

const server = Bun.serve({
    port: 18899,
    hostname: "127.0.0.1",

    async fetch(req) {
        const url = new URL(req.url);

        // ---------- API Routes ----------

        // GET /api/todos — list all todos
        if (url.pathname === "/api/todos" && req.method === "GET") {
            const rows = getAllTodos.all();
            return Response.json(rows.map(formatTodo));
        }

        // POST /api/todos — create a new todo
        if (url.pathname === "/api/todos" && req.method === "POST") {
            const body = await req.json();
            const text = (body.text || "").trim();
            if (!text) {
                return Response.json({ error: "Text is required" }, { status: 400 });
            }
            const row = insertTodo.get(text);
            return Response.json(formatTodo(row), { status: 201 });
        }

        // PATCH /api/todos/:id — update a todo
        if (url.pathname.startsWith("/api/todos/") && req.method === "PATCH") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });

            const body = await req.json();
            let row: any;

            if ("text" in body && "done" in body) {
                row = updateTodo.get(body.text, body.done ? 1 : 0, id);
            } else if ("done" in body) {
                row = updateTodoDone.get(body.done ? 1 : 0, id);
            } else if ("text" in body) {
                row = updateTodoText.get(body.text, id);
            }

            if (!row) return Response.json({ error: "Not found" }, { status: 404 });
            return Response.json(formatTodo(row));
        }

        // DELETE /api/todos/:id — delete a todo
        if (url.pathname.startsWith("/api/todos/") && req.method === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            deleteTodoById.run(id);
            return Response.json({ ok: true });
        }

        // POST /api/todos/clear-done — remove all completed todos
        if (url.pathname === "/api/todos/clear-done" && req.method === "POST") {
            clearDoneTodos.run();
            const rows = getAllTodos.all();
            return Response.json(rows.map(formatTodo));
        }

        // GET /api/info — app info
        if (url.pathname === "/api/info") {
            return Response.json({
                app: "TodoApp",
                runtime: `Bun ${Bun.version}`,
                database: "SQLite",
            });
        }

        // ---------- Static File Serving ----------

        // Serve index.html for root
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

console.log(`[TodoApp] Server running at http://localhost:${server.port}`);
console.log(`[TodoApp] SQLite database initialized`);
