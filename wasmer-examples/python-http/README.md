# Python http.server + Wasmer

This example shows how to run a minimal **Python standard-library HTTP server** on **Wasmer Edge**.

## Demo

`https://<your-subdomain>.wasmer.app/` (deploy your own copy to get a live demo)

## How it Works

The server logic lives in `src/main.py`:

* `CustomHandler` subclasses `http.server.SimpleHTTPRequestHandler` and overrides `do_GET()` to return JSON: `{"message": "Python app is running with Wasmer!"}`.
* `HTTPServer((host, port), CustomHandler)` starts the server; by default it binds to `HOST=127.0.0.1` and `PORT=8080`, but both can be overridden via environment variables.
* When run directly, the script prints the serving URL and blocks forever handling requests.

Because everything uses the Python standard library, no extra dependencies are required for Wasmer.

## Running Locally

```bash
python src/main.py
```

Your server is available at `http://127.0.0.1:8080/` (or whatever `HOST`/`PORT` you configure).

## Deploying to Wasmer (Overview)

1. Keep `src/main.py` as the entrypoint referenced in `wasmer.toml` or your deploy command.
2. Deploy to Wasmer Edge.
3. Visit `https://<your-subdomain>.wasmer.app/` to confirm the JSON response.
