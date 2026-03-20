#!/usr/bin/env bun

import { log } from "./utils/logger";

const args = process.argv.slice(2);
const command = args[0];

function printHelp(): void {
    log.info(`
  tano — cross-platform mobile framework

  Usage:
    tano <command> [options]

  Commands:
    create <name>       Create a new Tano project
    dev                 Start development server
    build <platform>    Build for ios or android
    run <platform>      Run on ios or android device/simulator
    doctor              Check development environment
    plugin <action>     Manage plugins (add, create)

  Options:
    --help, -h          Show this help message
    --version, -v       Show version

  Examples:
    tano create my-app
    tano dev
    tano build ios
    tano run ios
    tano doctor
`);
}

function printVersion(): void {
    log.info("@tano/cli v0.1.0");
}

async function main(): Promise<void> {
    if (!command || command === "--help" || command === "-h") {
        printHelp();
        return;
    }

    if (command === "--version" || command === "-v") {
        printVersion();
        return;
    }

    switch (command) {
        case "create":
            await import("./commands/create").then((m) =>
                m.default(args.slice(1))
            );
            break;
        case "dev":
            await import("./commands/dev").then((m) =>
                m.default(args.slice(1))
            );
            break;
        case "build":
            await import("./commands/build").then((m) =>
                m.default(args.slice(1))
            );
            break;
        case "run":
            await import("./commands/run").then((m) =>
                m.default(args.slice(1))
            );
            break;
        case "doctor":
            await import("./commands/doctor").then((m) =>
                m.default(args.slice(1))
            );
            break;
        case "plugin":
            await import("./commands/plugin").then((m) =>
                m.default(args.slice(1))
            );
            break;
        default:
            log.error(`Unknown command: ${command}`);
            printHelp();
            process.exit(1);
    }
}

main().catch((err) => {
    log.error(err.message || String(err));
    process.exit(1);
});
