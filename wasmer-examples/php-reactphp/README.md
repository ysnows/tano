# ReactPHP HTTP Server + Wasmer

This example shows how to run a minimalist **ReactPHP** HTTP server on **Wasmer Edge**.

## Demo

https://wordpress-php-starter.wasmer.app/

## How it Works

`app/index.php` wires together ReactPHP’s event loop and HTTP server:

* `require __DIR__ . '/../vendor/autoload.php';` loads dependencies installed via Composer.
* `new React\Http\HttpServer(...)` defines a callback that returns `"Hello World!\n"` for every request.
* `React\Socket\SocketServer('127.0.0.1:8080')` opens a TCP socket, and `HttpServer->listen($socket)` attaches the HTTP handler.
* When the script runs, it keeps the event loop alive and logs the listening URL.

You can extend the callback to implement more complex routing or JSON APIs.

## Running Locally

```bash
composer install
php app/index.php
```

ReactPHP listens on `http://127.0.0.1:8080/`. Hit the URL in your browser or with `curl` to confirm the “Hello World!” response.

## Deploying to Wasmer (Overview)

1. Install dependencies (`composer install --no-dev --optimize-autoloader`) before deploying.
2. Ensure your start command runs `php app/index.php` (or similar) so Wasmer boots the ReactPHP loop.
3. Visit `https://<your-subdomain>.wasmer.app/` to verify the server responds.
