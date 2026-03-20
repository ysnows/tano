import { log } from "../utils/logger";

export default async function plugin(args: string[]): Promise<void> {
    const action = args[0];

    log.heading("tano plugin");
    log.info("");

    if (!action) {
        log.error("Please specify an action:");
        log.info("  tano plugin add <name>      Install a Tano plugin");
        log.info("  tano plugin create <name>    Scaffold a new plugin");
        log.info("");
        process.exit(1);
    }

    if (action !== "add" && action !== "create") {
        log.error(`Unknown plugin action: ${action}`);
        log.info("  Supported actions: add, create");
        log.info("");
        process.exit(1);
    }

    const pluginName = args[1];

    if (action === "add") {
        log.warn("Coming soon!");
        log.info("");
        log.info("  'tano plugin add' will:");
        log.info("  1. Download the plugin Swift package");
        log.info("  2. Add it to your project's Package.swift dependencies");
        log.info("  3. Register it with the Tano plugin router");
        log.info("  4. Add the JS bridge bindings to your project");
        if (pluginName) {
            log.info("");
            log.dim(`  Requested plugin: ${pluginName}`);
        }
        log.info("");
    }

    if (action === "create") {
        log.warn("Coming soon!");
        log.info("");
        log.info("  'tano plugin create' will:");
        log.info("  1. Scaffold a new plugin with Swift + JS boilerplate");
        log.info("  2. Include Package.swift, source, and test directories");
        log.info("  3. Register it with the project for development");
        if (pluginName) {
            log.info("");
            log.dim(`  Plugin name: ${pluginName}`);
        }
        log.info("");
    }
}
