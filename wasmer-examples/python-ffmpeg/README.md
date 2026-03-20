# FastAPI + ffmpeg-python Frame Grabber

This example shows how to extract a single video frame with **ffmpeg-python** behind a **FastAPI** endpoint on **Wasmer Edge**.

## Demo

https://python-ffmpeg-example.wasmer.app

## How it Works

`main.py` performs three steps for each request to `/process`:

1. **Download** – Streams the source video URL into a temporary file using `requests`.
2. **Extract** – Runs `ffmpeg.input(..., ss=time).output(..., vframes=1, vcodec="mjpeg")` to grab a JPEG at the requested timestamp (defaults to 1 s).
3. **Respond** – Reads the generated image, encodes it as base64, and injects it into a simple HTML template.

Temporary files are cleaned up after each request, and errors are surfaced as `HTTPException` responses.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# ensure ffmpeg CLI is installed (brew install ffmpeg, apt install ffmpeg, etc.)
uvicorn main:app --host 0.0.0.0 --port 8000
```

Visit `http://127.0.0.1:8000/` for the UI or call `/process?url=...&time=2` to test.

## Deploying to Wasmer (Overview)

1. Bundle `main.py`, `requirements.txt`, and any static assets.
2. Provide an ffmpeg binary in your Wasmer build (e.g., via `wasmer.toml` packages).
3. Deploy and open `https://<your-subdomain>.wasmer.app/process?url=...` to generate screenshots.
