# MadelineProto Telegram Client + Wasmer

This example shows how to run a minimal **MadelineProto** client on **Wasmer Edge**. MadelineProto lets you automate interactions with the Telegram network using PHP.

## Demo

`https://<your-subdomain>.wasmer.app/` (configure your own Telegram credentials to use the demo)

## How it Works

The entrypoint `app/index.php` bootstraps MadelineProto:

* `vendor/autoload.php` loads dependencies installed with Composer.
* `new MadelineProto\API('session.madeline')` initialises the Telegram client and persists the session in `session.madeline`.
* After `start()` authenticates the session, the script fetches the current user, sends a `/start` message to `@stickeroptimizerbot`, joins the official `@MadelineProto` channel, attempts to accept an invite link, and finally echoes `"OK, done!"`.

Make sure you provide any required environment variables (e.g., API ID and hash) so the login flow can complete during deployment.

## Running Locally

```bash
composer install
php -t app -S 127.0.0.1:8080
```

The script runs immediately when requested at `http://127.0.0.1:8080/`. Check your logs or console output to see MadelineProto activity.

## Deploying to Wasmer (Overview)

1. Include the generated `vendor/` directory and persistable `session.madeline` file.
2. Configure your Telegram API credentials as Wasmer secrets/environment variables.
3. Deploy, then visit `https://<your-subdomain>.wasmer.app/` to trigger the MadelineProto automation.
