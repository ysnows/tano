<?php

require __DIR__ . '/../vendor/autoload.php';

use Revolt\EventLoop;

$suspension = EventLoop::getSuspension();

EventLoop::delay(2, function () use ($suspension): void {
    print '++ Executing callback created by EventLoop::delay()' . PHP_EOL;

    $suspension->resume(null);
});

print '++ Suspending to event loop...' . PHP_EOL;

$suspension->suspend();

print '++ Script end' . PHP_EOL;
