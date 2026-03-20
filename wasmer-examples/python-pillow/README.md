# FastAPI Image Processor (Pillow) + Wasmer

This example shows how to perform simple image manipulations with **Pillow (PIL)** behind a **FastAPI** endpoint on **Wasmer Edge**.

## Demo

https://python-pillow-example.wasmer.app

## How it Works

`main.py` implements a `/process` route that accepts three query parameters: `url`, `rotate`, and `crop`.

1. **Download** – `requests.get(url)` fetches the remote image and loads it with `Image.open(BytesIO(...))`.
2. **Transform** – If `rotate` is provided, the image rotates with `expand=True`; if `crop` is provided (`left,top,right,bottom`), the image is cropped accordingly.
3. **Return** – The image is saved to an in-memory buffer as PNG and returned as a streaming response.

Invalid crop strings or download failures are handled with descriptive HTTP errors.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Then try:

```bash
curl "http://127.0.0.1:8000/process?url=https://picsum.photos/320&rotate=45&crop=0,0,200,200" \
  --output rotated.png
```

## Deploying to Wasmer (Overview)

1. Bundle `main.py` and `requirements.txt` in your project.
2. Configure the start command to run Uvicorn: `uvicorn main:app --host 0.0.0.0 --port $PORT`.
3. Deploy to Wasmer Edge and call `https://<your-subdomain>.wasmer.app/process?...`.
