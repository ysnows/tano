# Astro Static Site + Wasmer

This example shows how to build an **Astro** project and deploy the generated site to **Wasmer Edge**.

## Demo

`https://<your-subdomain>.wasmer.app/` (deploy to get a live URL)

## How it Works

* `astro.config.mjs` configures Astro (this starter uses the default output and no SSR adapters).
* Pages live in `src/pages/` (`index.astro` renders the landing page and pulls in layout/components).
* `npm run build` outputs static HTML/CSS/JS into `dist/`, which Wasmer Edge serves directly.

## Running Locally

```bash
pnpm install    # or npm install / yarn install
pnpm run dev
```

Open `http://127.0.0.1:4321/` to see the dev server with hot reload. To preview the production build:

```bash
pnpm run build
pnpm run preview
```

## Deploying to Wasmer (Overview)

1. Build the site: `pnpm run build` (creates the `dist/` folder).
2. Configure Wasmer Edge to publish the `dist/` directory.
3. Deploy and visit `https://<your-subdomain>.wasmer.app/`.
