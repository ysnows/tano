# ChatApp Example

A chat application built with Tano, demonstrating Server-Sent Events (SSE) streaming from an on-device Bun server.

## What This Demonstrates

- **SSE streaming** — The server sends tokens one at a time via `text/event-stream`, simulating LLM-style output
- **ReadableStream on Bun** — Uses `ReadableStream` with `Bun.sleep()` to produce a delayed stream of tokens
- **Fetch stream reader** — The web client reads the SSE stream using `res.body.getReader()` for real-time display
- **On-device Bun server** — The entire backend runs natively on the mobile device via Tano

## Project Structure

```
chat-app/
├── tano.config.ts         # Tano project configuration
├── package.json           # Dependencies and scripts
├── src/
│   ├── server/
│   │   └── index.ts       # Bun server with SSE streaming endpoint
│   └── web/
│       └── index.html     # Chat UI with streaming token display
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

| Method | Endpoint     | Description                              |
|--------|-------------|------------------------------------------|
| `POST` | `/api/chat` | Send a message, receive SSE stream back  |
| `GET`  | `/api/info` | App and runtime info                     |

## Swapping in a Real LLM

To connect to a real LLM API (e.g., OpenAI, Anthropic, Ollama), replace the simulated response in `src/server/index.ts`:

```typescript
// Instead of splitting a static string, forward to an LLM API:
if (url.pathname === '/api/chat' && req.method === 'POST') {
    const body = await req.json();

    const llmRes = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            model: 'gpt-4',
            messages: [{ role: 'user', content: body.message }],
            stream: true,
        }),
    });

    // Forward the SSE stream directly
    return new Response(llmRes.body, {
        headers: { 'Content-Type': 'text/event-stream' },
    });
}
```

Since the Bun server runs on-device, you can also integrate with local/on-device LLM runtimes for fully offline inference.
