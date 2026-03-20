import { log } from "../utils/logger";
import { existsSync } from "fs";
import { resolve, join } from "path";

interface TanoConfig {
    app?: { name?: string };
    server?: { entry?: string; port?: number };
    web?: { entry?: string; framework?: string };
}

async function loadConfig(cwd: string): Promise<TanoConfig> {
    const configPath = join(cwd, "tano.config.ts");
    if (!existsSync(configPath)) {
        throw new Error("tano.config.ts not found in current directory. Are you in a Tano project?");
    }
    // Dynamic import of the config
    try {
        const mod = await import(configPath);
        return mod.default || mod;
    } catch {
        // Fallback: read as text and extract basic values
        const text = await Bun.file(configPath).text();
        const config: TanoConfig = {};
        const portMatch = text.match(/port:\s*(\d+)/);
        if (portMatch) {
            config.server = { port: parseInt(portMatch[1]) };
        }
        return config;
    }
}

export default async function dev(args: string[]): Promise<void> {
    const cwd = process.cwd();
    const isAndroid = args.includes("--android");

    log.heading("tano dev");
    log.info("");

    // 1. Load config
    let config: TanoConfig;
    try {
        config = await loadConfig(cwd);
    } catch (e: any) {
        log.error(e.message);
        process.exit(1);
    }

    const serverEntry = config.server?.entry || "./src/server/index.ts";
    const serverPort = config.server?.port || 18899;
    const webEntry = config.web?.entry || "./src/web/index.html";
    const framework = config.web?.framework;

    // 2. Check server entry exists
    const serverPath = resolve(cwd, serverEntry);
    if (!existsSync(serverPath)) {
        log.error(`Server entry not found: ${serverEntry}`);
        process.exit(1);
    }

    log.step(`Server: ${serverEntry} (port ${serverPort})`);
    log.step(`Web: ${webEntry}${framework ? ` (${framework})` : ""}`);
    log.info("");

    // 3. Start the Bun dev server
    log.step("Starting Bun dev server...");

    const serverProc = Bun.spawn(["bun", "run", serverPath], {
        cwd,
        env: {
            ...process.env,
            PORT: String(serverPort),
            NODE_ENV: "development",
            TANO_DEV: "true",
        },
        stdout: "pipe",
        stderr: "pipe",
    });

    // Pipe server output
    const serverStdout = serverProc.stdout;
    const serverStderr = serverProc.stderr;

    if (serverStdout) {
        (async () => {
            const reader = serverStdout.getReader();
            const decoder = new TextDecoder();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                process.stdout.write(`\x1b[36m[server]\x1b[0m ${decoder.decode(value)}`);
            }
        })();
    }

    if (serverStderr) {
        (async () => {
            const reader = serverStderr.getReader();
            const decoder = new TextDecoder();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                process.stderr.write(`\x1b[33m[server]\x1b[0m ${decoder.decode(value)}`);
            }
        })();
    }

    // 4. Wait for server to be ready
    log.step("Waiting for server to be ready...");
    const maxRetries = 30;
    let ready = false;
    for (let i = 0; i < maxRetries; i++) {
        try {
            const res = await fetch(`http://127.0.0.1:${serverPort}/`);
            if (res.ok || res.status === 404) {
                ready = true;
                break;
            }
        } catch {
            // Not ready yet
        }
        await Bun.sleep(500);
    }

    if (!ready) {
        log.warn("Server may not be ready yet, continuing anyway...");
    } else {
        log.success(`Server running on http://127.0.0.1:${serverPort}`);
    }

    // 5. Start web dev server if framework specified
    let webProc: ReturnType<typeof Bun.spawn> | null = null;
    if (framework) {
        log.step(`Starting ${framework} dev server...`);
        const webCmd = framework === "next"
            ? ["npx", "next", "dev"]
            : framework === "vite"
            ? ["npx", "vite", "dev"]
            : ["bun", "run", "dev"];

        webProc = Bun.spawn(webCmd, {
            cwd: resolve(cwd, "src/web"),
            stdout: "pipe",
            stderr: "pipe",
        });
    }

    // 6. Open iOS Simulator (or Android emulator)
    if (!isAndroid) {
        log.step("Opening iOS Simulator...");
        try {
            // Boot first available simulator
            const simListProc = Bun.spawnSync(["xcrun", "simctl", "list", "devices", "available", "-j"]);
            const simData = JSON.parse(simListProc.stdout.toString());
            let bootedDevice: string | null = null;

            for (const [runtime, devices] of Object.entries(simData.devices || {})) {
                if (!String(runtime).includes("iOS")) continue;
                for (const device of devices as any[]) {
                    if (device.state === "Booted") {
                        bootedDevice = device.udid;
                        break;
                    }
                }
                if (bootedDevice) break;
            }

            if (!bootedDevice) {
                // Find an iPhone to boot
                for (const [runtime, devices] of Object.entries(simData.devices || {})) {
                    if (!String(runtime).includes("iOS")) continue;
                    for (const device of devices as any[]) {
                        if (device.isAvailable && device.name.includes("iPhone")) {
                            Bun.spawnSync(["xcrun", "simctl", "boot", device.udid]);
                            bootedDevice = device.udid;
                            log.success(`Booted ${device.name}`);
                            break;
                        }
                    }
                    if (bootedDevice) break;
                }
            }

            // Open Simulator app
            Bun.spawn(["open", "-a", "Simulator"]);

            if (bootedDevice) {
                // Open the dev URL in the simulator's Safari
                await Bun.sleep(2000);
                Bun.spawnSync([
                    "xcrun", "simctl", "openurl", bootedDevice,
                    `http://127.0.0.1:${serverPort}`
                ]);
                log.success("Opened dev server in iOS Simulator");
            }
        } catch (e: any) {
            log.warn(`Could not open simulator: ${e.message}`);
            log.info(`  Open http://127.0.0.1:${serverPort} in the simulator manually`);
        }
    } else {
        log.step("Android emulator support coming soon");
        log.info(`  Open http://10.0.2.2:${serverPort} in the emulator browser`);
    }

    log.info("");
    log.success("Dev server running. Press Ctrl+C to stop.");
    log.dim(`  Server: http://127.0.0.1:${serverPort}`);
    log.info("");

    // 7. Watch for file changes
    log.step("Watching for changes...");

    // Handle graceful shutdown
    process.on("SIGINT", () => {
        log.info("\n");
        log.step("Shutting down...");
        serverProc.kill();
        webProc?.kill();
        process.exit(0);
    });

    process.on("SIGTERM", () => {
        serverProc.kill();
        webProc?.kill();
        process.exit(0);
    });

    // Keep the process alive
    await serverProc.exited;
}
