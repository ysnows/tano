/**
 * Tano 记账 (Accounting) App — Bun server with SQLite persistence
 *
 * Features:
 * - Income & expense tracking with categories
 * - Monthly/yearly statistics
 * - Budget management
 * - Category CRUD
 */

import { Database } from "bun:sqlite";

const db = new Database("accounting.db");

// Enable WAL mode for better concurrent read performance
db.run("PRAGMA journal_mode = WAL");

// ── Schema ──────────────────────────────────────────────

db.run(`
    CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        icon TEXT NOT NULL DEFAULT '📦',
        type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
        color TEXT NOT NULL DEFAULT '#6366f1',
        sort_order INTEGER NOT NULL DEFAULT 0
    )
`);

db.run(`
    CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
        category_id INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL DEFAULT (date('now')),
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (category_id) REFERENCES categories(id)
    )
`);

db.run(`
    CREATE TABLE IF NOT EXISTS budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER,
        amount REAL NOT NULL,
        month TEXT NOT NULL,
        UNIQUE(category_id, month),
        FOREIGN KEY (category_id) REFERENCES categories(id)
    )
`);

// ── Seed default categories ─────────────────────────────

const categoryCount = db.prepare("SELECT COUNT(*) as cnt FROM categories").get() as any;
if (categoryCount.cnt === 0) {
    const insert = db.prepare("INSERT INTO categories (name, icon, type, color, sort_order) VALUES (?, ?, ?, ?, ?)");
    const defaults = [
        ["餐饮", "🍜", "expense", "#ef4444", 1],
        ["交通", "🚇", "expense", "#f97316", 2],
        ["购物", "🛒", "expense", "#eab308", 3],
        ["住房", "🏠", "expense", "#22c55e", 4],
        ["娱乐", "🎮", "expense", "#3b82f6", 5],
        ["医疗", "💊", "expense", "#8b5cf6", 6],
        ["教育", "📚", "expense", "#ec4899", 7],
        ["通讯", "📱", "expense", "#14b8a6", 8],
        ["工资", "💰", "income", "#22c55e", 1],
        ["奖金", "🎁", "income", "#f97316", 2],
        ["投资", "📈", "income", "#3b82f6", 3],
        ["兼职", "💼", "income", "#8b5cf6", 4],
        ["其他收入", "💵", "income", "#6b7280", 5],
        ["其他支出", "📋", "expense", "#6b7280", 9],
    ];
    const insertMany = db.transaction(() => {
        for (const [name, icon, type, color, order] of defaults) {
            insert.run(name, icon, type, color, order);
        }
    });
    insertMany();
    console.log("[Accounting] Seeded default categories");
}

// ── Prepared Statements ─────────────────────────────────

const stmts = {
    // Transactions
    listTransactions: db.prepare(`
        SELECT t.id, t.amount, t.type, t.category_id, t.note, t.date, t.created_at,
               c.name as category_name, c.icon as category_icon, c.color as category_color
        FROM transactions t
        JOIN categories c ON c.id = t.category_id
        WHERE t.date BETWEEN ? AND ?
        ORDER BY t.date DESC, t.created_at DESC
    `),
    insertTransaction: db.prepare(`
        INSERT INTO transactions (amount, type, category_id, note, date)
        VALUES (?, ?, ?, ?, ?)
        RETURNING id, amount, type, category_id, note, date, created_at
    `),
    updateTransaction: db.prepare(`
        UPDATE transactions SET amount = ?, type = ?, category_id = ?, note = ?, date = ?
        WHERE id = ?
        RETURNING id, amount, type, category_id, note, date, created_at
    `),
    deleteTransaction: db.prepare("DELETE FROM transactions WHERE id = ?"),

    // Categories
    listCategories: db.prepare("SELECT * FROM categories ORDER BY type, sort_order"),
    insertCategory: db.prepare(
        "INSERT INTO categories (name, icon, type, color, sort_order) VALUES (?, ?, ?, ?, ?) RETURNING *"
    ),
    updateCategory: db.prepare(
        "UPDATE categories SET name = ?, icon = ?, color = ? WHERE id = ? RETURNING *"
    ),
    deleteCategory: db.prepare("DELETE FROM categories WHERE id = ?"),

    // Stats
    monthlyStats: db.prepare(`
        SELECT type, SUM(amount) as total
        FROM transactions
        WHERE date BETWEEN ? AND ?
        GROUP BY type
    `),
    categoryStats: db.prepare(`
        SELECT c.id, c.name, c.icon, c.color, t.type, SUM(t.amount) as total, COUNT(*) as count
        FROM transactions t
        JOIN categories c ON c.id = t.category_id
        WHERE t.date BETWEEN ? AND ?
        GROUP BY c.id, t.type
        ORDER BY total DESC
    `),
    dailyStats: db.prepare(`
        SELECT date, type, SUM(amount) as total
        FROM transactions
        WHERE date BETWEEN ? AND ?
        GROUP BY date, type
        ORDER BY date
    `),

    // Budgets
    listBudgets: db.prepare(`
        SELECT b.*, c.name as category_name, c.icon as category_icon, c.color as category_color
        FROM budgets b
        LEFT JOIN categories c ON c.id = b.category_id
        WHERE b.month = ?
    `),
    upsertBudget: db.prepare(`
        INSERT INTO budgets (category_id, amount, month)
        VALUES (?, ?, ?)
        ON CONFLICT(category_id, month) DO UPDATE SET amount = excluded.amount
        RETURNING *
    `),
    deleteBudget: db.prepare("DELETE FROM budgets WHERE id = ?"),

    budgetSpent: db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as spent
        FROM transactions
        WHERE category_id = ? AND type = 'expense' AND date BETWEEN ? AND ?
    `),
};

// ── Helpers ─────────────────────────────────────────────

function monthRange(month: string): [string, string] {
    // month = "2026-03"
    const [y, m] = month.split("-").map(Number);
    const start = `${y}-${String(m).padStart(2, "0")}-01`;
    const lastDay = new Date(y, m, 0).getDate();
    const end = `${y}-${String(m).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
    return [start, end];
}

function formatTx(row: any) {
    return {
        id: row.id,
        amount: row.amount,
        type: row.type,
        categoryId: row.category_id,
        categoryName: row.category_name,
        categoryIcon: row.category_icon,
        categoryColor: row.category_color,
        note: row.note,
        date: row.date,
        createdAt: row.created_at,
    };
}

// ── HTTP Server ─────────────────────────────────────────

const webDir = new URL("../web", import.meta.url).pathname;

const server = Bun.serve({
    port: 18899,
    hostname: "127.0.0.1",

    async fetch(req) {
        const url = new URL(req.url);
        const method = req.method;

        // ── Transactions ──

        if (url.pathname === "/api/transactions" && method === "GET") {
            const month = url.searchParams.get("month") || new Date().toISOString().slice(0, 7);
            const [start, end] = monthRange(month);
            const rows = stmts.listTransactions.all(start, end);
            return Response.json(rows.map(formatTx));
        }

        if (url.pathname === "/api/transactions" && method === "POST") {
            const body = await req.json();
            const { amount, type, categoryId, note, date } = body as any;
            if (!amount || !type || !categoryId) {
                return Response.json({ error: "amount, type, categoryId required" }, { status: 400 });
            }
            const row = stmts.insertTransaction.get(
                Number(amount), type, categoryId, note || "", date || new Date().toISOString().slice(0, 10)
            );
            return Response.json(row, { status: 201 });
        }

        if (url.pathname.startsWith("/api/transactions/") && method === "PUT") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            const body = await req.json();
            const { amount, type, categoryId, note, date } = body as any;
            const row = stmts.updateTransaction.get(Number(amount), type, categoryId, note || "", date, id);
            if (!row) return Response.json({ error: "Not found" }, { status: 404 });
            return Response.json(row);
        }

        if (url.pathname.startsWith("/api/transactions/") && method === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            stmts.deleteTransaction.run(id);
            return Response.json({ ok: true });
        }

        // ── Categories ──

        if (url.pathname === "/api/categories" && method === "GET") {
            const rows = stmts.listCategories.all();
            return Response.json(rows);
        }

        if (url.pathname === "/api/categories" && method === "POST") {
            const body = await req.json();
            const { name, icon, type, color } = body as any;
            if (!name || !type) {
                return Response.json({ error: "name, type required" }, { status: 400 });
            }
            try {
                const row = stmts.insertCategory.get(name, icon || "📦", type, color || "#6366f1", 99);
                return Response.json(row, { status: 201 });
            } catch (e: any) {
                return Response.json({ error: e.message }, { status: 409 });
            }
        }

        if (url.pathname.startsWith("/api/categories/") && method === "PUT") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            const body = await req.json();
            const { name, icon, color } = body as any;
            const row = stmts.updateCategory.get(name, icon, color, id);
            if (!row) return Response.json({ error: "Not found" }, { status: 404 });
            return Response.json(row);
        }

        if (url.pathname.startsWith("/api/categories/") && method === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            stmts.deleteCategory.run(id);
            return Response.json({ ok: true });
        }

        // ── Stats ──

        if (url.pathname === "/api/stats" && method === "GET") {
            const month = url.searchParams.get("month") || new Date().toISOString().slice(0, 7);
            const [start, end] = monthRange(month);

            const monthlyTotals = stmts.monthlyStats.all(start, end) as any[];
            const income = monthlyTotals.find((r: any) => r.type === "income")?.total || 0;
            const expense = monthlyTotals.find((r: any) => r.type === "expense")?.total || 0;

            const categoryBreakdown = stmts.categoryStats.all(start, end);
            const dailyBreakdown = stmts.dailyStats.all(start, end);

            return Response.json({
                month,
                income,
                expense,
                balance: income - expense,
                categories: categoryBreakdown,
                daily: dailyBreakdown,
            });
        }

        // ── Budgets ──

        if (url.pathname === "/api/budgets" && method === "GET") {
            const month = url.searchParams.get("month") || new Date().toISOString().slice(0, 7);
            const [start, end] = monthRange(month);
            const budgets = stmts.listBudgets.all(month) as any[];

            // Attach spent amount to each budget
            const result = budgets.map((b: any) => {
                const spent = (stmts.budgetSpent.get(b.category_id, start, end) as any).spent;
                return { ...b, spent, remaining: b.amount - spent };
            });

            return Response.json(result);
        }

        if (url.pathname === "/api/budgets" && method === "POST") {
            const body = await req.json();
            const { categoryId, amount, month } = body as any;
            if (!categoryId || !amount || !month) {
                return Response.json({ error: "categoryId, amount, month required" }, { status: 400 });
            }
            const row = stmts.upsertBudget.get(categoryId, Number(amount), month);
            return Response.json(row, { status: 201 });
        }

        if (url.pathname.startsWith("/api/budgets/") && method === "DELETE") {
            const id = parseInt(url.pathname.split("/").pop() || "0");
            if (!id) return Response.json({ error: "Invalid ID" }, { status: 400 });
            stmts.deleteBudget.run(id);
            return Response.json({ ok: true });
        }

        // ── App Info ──

        if (url.pathname === "/api/info") {
            return Response.json({
                app: "Tano 记账",
                runtime: `Bun ${Bun.version}`,
                database: "SQLite (WAL)",
            });
        }

        // ── Static Files ──

        if (url.pathname === "/" || url.pathname === "/index.html") {
            const file = Bun.file(`${webDir}/index.html`);
            if (await file.exists()) {
                return new Response(file, { headers: { "Content-Type": "text/html" } });
            }
        }

        // Serve CSS/JS/assets
        const filePath = `${webDir}${url.pathname}`;
        const file = Bun.file(filePath);
        if (await file.exists()) {
            return new Response(file);
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`[记账] Server running at http://localhost:${server.port}`);
console.log(`[记账] SQLite database initialized`);
