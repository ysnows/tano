# Django + Wasmer Edge

This example shows how to run a standard **Django 5** project on **Wasmer Edge**.

## Demo

https://django-template.wasmer.app/

## How it Works

Key files to know:

* `api/settings.py`
  * Adds the sample app (`'example'`) to `INSTALLED_APPS`.
  * Sets `ALLOWED_HOSTS = ['127.0.0.1', '.wasmer.app']` so both local development and Wasmer Edge subdomains work.
  * Points `WSGI_APPLICATION` to `api.wsgi.app`, meaning Wasmer will import `api/wsgi.py` and look for `app`.
* `api/wsgi.py`
  * Calls `get_wsgi_application()` and exposes it as a module-level variable named `app` (the entrypoint Wasmer runs).
* `example/views.py`
  * Defines `index(request)` which renders the current time in a simple HTML page.
* `example/urls.py` and `api/urls.py`
  * Wire the `index` view to the root URL (`/`) and include it in the project’s root URL patterns.

Because Django serves via WSGI, Wasmer Edge runs the project without extra adapters.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt  # or pip install django
python manage.py migrate
python manage.py runserver
```

Visit `http://127.0.0.1:8000/` to see the “Hello from Wasmer!” page with the current timestamp.

## Deploying to Wasmer (Overview)

1. Collect static files and apply migrations as part of your build (e.g., `python manage.py collectstatic --no-input`).
2. Ensure `api.wsgi:app` is the entrypoint in your deployment configuration.
3. Deploy to Wasmer Edge and browse to `https://<your-subdomain>.wasmer.app/`.
