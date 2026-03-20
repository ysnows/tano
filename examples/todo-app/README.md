# TodoApp Example

A complete todo application built with Tano, demonstrating:

- **On-device Bun server** handling REST API requests
- **SQLite persistence** via `bun:sqlite` for durable local storage
- **Plain HTML/JS frontend** served in the native WebView (no build step)
- **Native plugin integration** using `@tano/plugin-clipboard` for copy-to-clipboard

## Project Structure

```
todo-app/
├── tano.config.ts         # Tano project configuration
├── package.json           # Dependencies and scripts
├── src/
│   ├── server/
│   │   └── index.ts       # Bun server with SQLite-backed todo API
│   └── web/
│       └── index.html     # Single-file HTML/JS frontend
└── README.md
```

## Getting Started

```bash
# Install dependencies
bun install

# Start the development server
tano dev

# Or run the server directly
bun run dev:server
```

## API Endpoints

| Method   | Endpoint               | Description              |
|----------|------------------------|--------------------------|
| `GET`    | `/api/todos`           | List all todos           |
| `POST`   | `/api/todos`           | Create a new todo        |
| `PATCH`  | `/api/todos/:id`       | Update a todo            |
| `DELETE` | `/api/todos/:id`       | Delete a todo            |
| `POST`   | `/api/todos/clear-done`| Remove completed todos   |
| `GET`    | `/api/info`            | App and runtime info     |

## Plugins Used

- **@tano/plugin-sqlite** — Provides SQLite database access on-device
- **@tano/plugin-clipboard** — Native clipboard read/write via `window.Tano.invoke('clipboard', ...)`
