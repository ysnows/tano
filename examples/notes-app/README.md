# NotesApp Example

A notes application built with Tano, demonstrating native plugin integration for biometrics, clipboard, and cryptographic hashing.

## What This Demonstrates

- **Notes CRUD API** — Create, read, update, and delete notes via on-device Bun server
- **Biometric authentication** — Lock/unlock the app using `window.Tano.invoke('biometrics', 'authenticate')`
- **Clipboard integration** — Copy note content using `window.Tano.invoke('clipboard', 'copy', ...)`
- **Cryptographic hashing** — Hash note content using `window.Tano.invoke('crypto', 'hash', ...)`
- **Browser fallbacks** — All native features gracefully fall back to Web APIs during development

## Project Structure

```
notes-app/
├── tano.config.ts         # Tano project configuration
├── package.json           # Dependencies and scripts
├── src/
│   ├── server/
│   │   └── index.ts       # Bun server with notes CRUD API
│   └── web/
│       └── index.html     # Notes UI with biometric lock, clipboard, crypto
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

| Method   | Endpoint          | Description          |
|----------|-------------------|----------------------|
| `GET`    | `/api/notes`      | List all notes       |
| `GET`    | `/api/notes/:id`  | Get a single note    |
| `POST`   | `/api/notes`      | Create a new note    |
| `PATCH`  | `/api/notes/:id`  | Update a note        |
| `DELETE` | `/api/notes/:id`  | Delete a note        |
| `GET`    | `/api/info`       | App and runtime info |

## Plugins Used

- **@tano/plugin-biometrics** — Face ID / Touch ID / fingerprint authentication via `window.Tano.invoke('biometrics', 'authenticate')`
- **@tano/plugin-clipboard** — Native clipboard read/write via `window.Tano.invoke('clipboard', 'copy', ...)`
- **@tano/plugin-crypto** — Cryptographic hashing (SHA-256) via `window.Tano.invoke('crypto', 'hash', ...)`
- **@tano/plugin-sqlite** — SQLite database access (swap in-memory store for persistent storage)

## Native Plugin Usage

The web UI uses `window.Tano.invoke()` to call native device features:

```javascript
// Lock — require biometric authentication
const result = await window.Tano.invoke('biometrics', 'authenticate');

// Copy to clipboard
await window.Tano.invoke('clipboard', 'copy', { text: noteContent });

// Hash content
const { hash } = await window.Tano.invoke('crypto', 'hash', {
    algorithm: 'sha256',
    data: noteContent
});
```

When running in a browser (during development), all calls fall back to standard Web APIs (`navigator.clipboard`, `crypto.subtle`).
