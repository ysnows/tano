# Wasmer Edge Examples

This repository contains runnable examples for deploying applications to **Wasmer Edge**. Each example mirrors the structure used in [`python-fastapi`](python-fastapi/README.md), with a concise walkthrough of how it works, instructions for running locally, and a short deployment guide.

## Getting Started

1. Install the [Wasmer CLI](https://docs.wasmer.io/install) and log in with `wasmer login`.
2. Clone this repository:
   ```bash
   git clone https://github.com/wasmerio/examples.git
   cd examples
   ```
3. Pick an example, read its `README.md`, and follow the “Running Locally” steps.
4. When you are ready to publish, use `wasmer deploy` from that example directory.

> Every example is self-contained. Dependencies, entry points, and Wasmer-specific configuration are documented in the example’s own README.

## Repository Overview

Examples are grouped by runtime. “Skip” directories hold work-in-progress templates; “fail” directories capture known issues or failing scenarios for regression testing.

### Python

- [`python-http`](python-http/README.md) – stdlib `http.server` JSON responder.
- [`python-django`](python-django/README.md) – Django 5 project using WSGI.
- [`python-fastapi`](python-fastapi/README.md) – minimal FastAPI hello world.
- [`python-fastapi-pandoc-converter`](python-fastapi-pandoc-converter/README.md) – FastAPI + pypandoc conversion service.
- [`python-fastapi-pystone`](python-fastapi-pystone/README.md) – Pystone benchmark exposed via FastAPI.
- [`python-ffmpeg`](python-ffmpeg/README.md) – Frame extraction with `ffmpeg-python`.
- [`python-flask`](python-flask/README.md) – Flask hello world.
- [`python-langchain-starter`](python-langchain-starter/README.md) – Streamlit chat UI backed by LangChain.
- [`python-mcp`](python-mcp/README.md) – FastMCP server exposing basic tools/resources.
- [`python-mcp-chatgpt`](python-mcp-chatgpt/README.md) – Cupcake search MCP server for ChatGPT.
- [`python-mkdocs`](python-mkdocs/README.md) – MkDocs static documentation site.
- [`python-pillow`](python-pillow/README.md) – Image transforms with Pillow.

### JavaScript & TypeScript

- [`js-astro-staticsite`](js-astro-staticsite/README.md) – Astro static export.
- [`js-docusaurus-staticsite`](js-docusaurus-staticsite/README.md) – Docusaurus docs site.
- [`js-gatsby-staticsite`](js-gatsby-staticsite/README.md) – Gatsby static site.
- [`js-next-staticsite`](js-next-staticsite/README.md) – Next.js `output: "export"` sample.
- [`js-svelte`](js-svelte/README.md) – Vite-powered Svelte app.
- [`skip-js-hono-wintercg`](skip-js-hono-wintercg/README.md) – Hono app targeting WinterCG workers.
- [`skip-js-worker-wintercg`](skip-js-worker-wintercg/README.md) – Plain WinterCG-compatible worker template.
- [`fail-js-nuxt-staticsite`](fail-js-nuxt-staticsite/README.md) – Nuxt static export (tracking open issues).
- [`fail-js-remix-staticsite`](fail-js-remix-staticsite/README.md) – Remix static export (tracking open issues).

### PHP

- [`php-basic`](php-basic/README.md) – Minimal PHP script starter.
- [`php-laravel`](php-laravel/README.md) – Laravel application.
- [`php-reactphp`](php-reactphp/README.md) – ReactPHP HTTP server.
- [`php-symfony`](php-symfony/README.md) – Symfony Demo application.
- [`fail-php-amphp`](fail-php-amphp/README.md) – AMPHP event-loop demo (known limitations).
- [`fail-php-madeline`](fail-php-madeline/README.md) – MadelineProto client sample (requires Telegram credentials).

### Go & Rust

- [`go-hugo-staticsite`](go-hugo-staticsite/README.md) – Hugo-generated static site.
- [`skip-rust-axum`](skip-rust-axum/README.md) – Axum server compiled to WASIX.

### Static Sites & Misc

- [`staticsite`](staticsite) – Shared static assets and helper scripts.
- [`Shipit`](Shipit) – Build and deployment recipes used by Wasmer’s internal tooling.

## Working With the Examples

- **Local development** – Most projects rely on the platform tooling for their language (e.g., `uvicorn`, `npm run dev`, `composer install`). Follow the steps in each example README to run locally.
- **Deploying** – `wasmer deploy` reads the `wasmer.toml` (or Shipit configuration) in the example directory to bundle code, configure routes, and upload to your Edge namespace.
- **Environment variables and secrets** – Use `wasmer secret add` or set values in your deployment pipeline. Examples that require API keys (e.g., `python-langchain-starter`) note them explicitly.

## Contributing

Contributions are welcome! If you have an example that showcases a new framework or highlights a best practice:

1. Follow the template established in existing READMEs (overview → demo → how it works → local run → Wasmer deployment).
2. Add your directory under the appropriate language prefix (`python-`, `js-`, `php-`, etc.).
3. Update this root README with a short description and link.
4. Open a pull request describing the scenario and any prerequisites.

## Additional Resources

- [Wasmer Edge documentation](https://docs.wasmer.io/edge)
- [Wasmer CLI reference](https://docs.wasmer.io/cli)
- [Support & community forums](https://discord.gg/wasmer)

Happy deploying!
