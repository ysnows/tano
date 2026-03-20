# MkDocs Static Site + Wasmer

This example shows how to build and serve a **MkDocs** documentation site on **Wasmer Edge**.

## Demo

https://wasmer-edge-mkdocs-sample.wasmer.app/

## How it Works

MkDocs turns Markdown files into a static site:

* `mkdocs.yml` configures the project title, navigation, and theme.
* The `docs/` directory contains your Markdown content (`index.md`, etc.).
* `mkdocs build` renders everything into the `site/` folder, which Wasmer Edge serves like any static site.

Because the output is plain HTML/CSS/JS, deployments are fast and serverless.

## Running Locally

```bash
pip install mkdocs
mkdocs serve
```

Visit `http://127.0.0.1:8000/` to preview changes with live reload. To inspect the static output manually, run `mkdocs build` and browse the `site/` directory.

## Deploying to Wasmer (Overview)

1. Run `mkdocs build` to generate the `site/` folder.
2. Point your deployment (e.g., `wasmer.toml`) at the `site/` directory as the publish root.
3. Deploy to Wasmer Edge and browse `https://<your-subdomain>.wasmer.app/`.
