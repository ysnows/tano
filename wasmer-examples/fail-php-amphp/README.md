# AMPHP Event Loop Demo + Wasmer

This example shows how to run a tiny **AMPHP** script on **Wasmer Edge**. It highlights how `Revolt\EventLoop` suspends and resumes execution around asynchronous callbacks.

## Demo

`https://<your-subdomain>.wasmer.app/` (logs are printed to stdout when the script runs)

## How it Works

`app/index.php` performs the entire demo:

* `composer install` brings in `amphp/amp` and friends via `vendor/autoload.php`.
* `EventLoop::getSuspension()` captures the current fiber suspension so the script can yield control.
* `EventLoop::delay(2, ...)` schedules a callback that prints a message and resumes the suspension after two seconds.
* `suspend()` yields to the event loop; once the delay fires, execution resumes and the script prints `"++ Script end"`.

This pattern demonstrates AMPHP’s cooperative multitasking model in a minimal script.

## Running Locally

```bash
composer install
php app/index.php
```

Watch the terminal output: the script immediately suspends, resumes two seconds later when the delayed callback fires, and then exits.

## Deploying to Wasmer (Overview)

1. Install dependencies (`composer install --no-dev`) before deploying.
2. Set your start command to run the script once (e.g., `php app/index.php`) or wrap it behind a minimal HTTP runner if desired.
3. Visit `https://<your-subdomain>.wasmer.app/` and inspect the logs to confirm the delay/resume cycle.
