# Cupcake MCP Server + Wasmer

This example shows how to run a **Model Context Protocol (MCP)** server for ChatGPT on **Wasmer Edge**.

> ℹ️ ChatGPT expects MCP servers to expose at least two tools (`search` and `fetch`) so it can discover and retrieve content.

## Demo

https://mcp-chatgpt-starter.wasmer.app/sse

Add it inside ChatGPT’s “Model Context Protocol” settings (no auth required) and ask questions like “How many cupcakes did Alice order?”

## How it Works

Everything lives in `main.py`:

* `RECORDS = ...` loads `records.json` and builds a `LOOKUP` dictionary keyed by cupcake order IDs.
* Pydantic models (`SearchResult`, `SearchResultPage`, `FetchResult`) shape the tool responses so clients get structured JSON.
* `FastMCP(name="Cupcake MCP")` registers two tools:
  * `search(query)` tokenises the query and performs keyword matching across order titles, text, and metadata.
  * `fetch(id)` returns the full order record or raises `ValueError` if the ID is unknown.
* `app = create_server()` exposes the MCP instance for Wasmer (`main:app`), and the `__main__` block runs it with the SSE transport.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

Your server listens for SSE connections. Point an MCP client (ChatGPT, Claude Desktop, etc.) at `http://127.0.0.1:8000/sse`.

## Deploying to Wasmer (Overview)

1. Ship `main.py` and `records.json` together; expose the MCP instance as `main:app`.
2. Deploy to Wasmer Edge.
3. Connect your MCP client to `https://<your-subdomain>.wasmer.app/sse`.
