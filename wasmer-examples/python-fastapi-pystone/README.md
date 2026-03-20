# FastAPI Pystone Benchmark + Wasmer

This example runs the classic **Pystone** CPU benchmark behind a **FastAPI** endpoint on **Wasmer Edge**.

## Demo

`https://<your-subdomain>.wasmer.app/` (call `/?loops=50000` to adjust the workload)

## How it Works

`src/main.py` contains both the FastAPI app and the benchmark:

* The module defines `app = FastAPI()` so Wasmer can load `main:app`.
* Pystone logic (records, procedures, and helper functions) is imported from the historical benchmark implementation.
* `LOOPS = 50000` sets the default number of iterations; the `/` route accepts an optional `loops` query parameter (capped to twice the default).
* The handler calls `pystones(loops)` and returns JSON containing the runtime, loop count, and benchmark version.
* Running the module directly starts `uvicorn` on `0.0.0.0:8000`.

This exposes an easy way to gather performance data from Wasmer Edge.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn
uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
```

Then visit `http://127.0.0.1:8000/` or `http://127.0.0.1:8000/?loops=100000` to trigger the benchmark.

## Deploying to Wasmer (Overview)

1. Ensure the deployment points to `src.main:app`.
2. Deploy to Wasmer Edge.
3. Call `https://<your-subdomain>.wasmer.app/?loops=50000` and inspect the JSON benchmark results.
