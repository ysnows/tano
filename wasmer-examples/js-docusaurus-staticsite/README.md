# Docusaurus Documentation Site + Wasmer

This example shows how to publish a **Docusaurus 2** documentation site on **Wasmer Edge**.

## Demo

https://wasmer-edge-docusaurus-sample.wasmer.app/

## How it Works

* `docusaurus.config.js` configures site metadata, navbar/footer, and themes.
* Markdown docs live in the `docs/` directory and are organised via `sidebars.js`.
* `yarn build` (or `npm run build`) generates static assets in `build/`, ready for Wasmer Edge.

## Running Locally

```bash
yarn install
yarn start
```

The dev server runs at `http://127.0.0.1:3000/` with live reload. To test the production bundle, run:

```bash
yarn build
yarn serve   # serves ./build locally
```

## Deploying to Wasmer (Overview)

1. Build the site: `yarn build` (outputs to `build/`).
2. Configure Wasmer Edge to publish the `build/` directory.
3. Deploy and browse `https://<your-subdomain>.wasmer.app/`.
