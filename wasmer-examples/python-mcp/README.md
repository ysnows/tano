# FastMCP Demo Server + Wasmer

This example shows how to run a **Model Context Protocol (MCP)** server built with **FastMCP** on **Wasmer Edge**.

## Demo

`https://<your-subdomain>.wasmer.app/` (attach `/sse` when testing from an MCP-compatible client)

## How it Works

`main.py` defines the MCP application:

* `mcp = FastMCP("Demo")` creates a server instance at import time so Wasmer can load `main:mcp`.
* Three capabilities are registered:
  * `add(a, b)` – a simple tool that sums two integers.
  * `greeting://{name}` – a dynamic resource that returns a personalised greeting.
  * `greet_user(name, style)` – a prompt template that chooses wording based on the requested style.
* When run as a script, `mcp.run(transport="streamable-http")` starts the server using the Streamable HTTP transport expected by Wasmer Edge.

Use these patterns to add your own tools, resources, or prompts before deploying.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install mcp
python main.py
```

The server listens for MCP clients on the default port and transport (Streamable HTTP). Point your MCP client (e.g., ChatGPT or Claude Desktop) to the local endpoint.

## Deploying to Wasmer (Overview)

1. Ensure `main.py` exports the `mcp` instance (entrypoint `main:mcp`).
2. Deploy to Wasmer Edge.
3. Connect your MCP-enabled client to `https://<your-subdomain>.wasmer.app/sse`.
