import { log } from "../utils/logger";
import { startWatcher } from "../utils/watcher";
import { startHMRServer } from "../utils/hmr-server";
import { getHMRClientScript } from "../utils/hmr-client";
import { existsSync } from "fs";
import { resolve, join, extname } from "path";

interface TanoConfig {
    app?: { name?: string };
    server?: { entry?: string; port?: number };
    web?: { entry?: string; framework?: string };
}

const HMR_PORT = 18900;

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

function startServerProcess(
    serverPath: string,
    cwd: string,
    serverPort: number,
): ReturnType<typeof Bun.spawn> {
    const proc = Bun.spawn(["bun", "run", serverPath], {
        cwd,
        env: {
            ...process.env,
            PORT: String(serverPort),
            NODE_ENV: "development",
            TANO_DEV: "true",
            TANO_HMR_PORT: String(HMR_PORT),
        },
        stdout: "pipe",
        stderr: "pipe",
    });

    const stdout = proc.stdout;
    const stderr = proc.stderr;

    if (stdout) {
        (async () => {
            const reader = stdout.getReader();
            const decoder = new TextDecoder();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                process.stdout.write(`\x1b[36m[server]\x1b[0m ${decoder.decode(value)}`);
            }
        })();
    }

    if (stderr) {
        (async () => {
            const reader = stderr.getReader();
            const decoder = new TextDecoder();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                process.stderr.write(`\x1b[33m[server]\x1b[0m ${decoder.decode(value)}`);
            }
        })();
    }

    return proc;
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

    // 3. Start HMR WebSocket server
    const hmr = startHMRServer(HMR_PORT);
    log.step(`HMR server started on ws://127.0.0.1:${HMR_PORT}`);

    // 4. Start the Bun dev server
    log.step("Starting Bun dev server...");
    let serverProc = startServerProcess(serverPath, cwd, serverPort);

    // 5. Wait for server to be ready
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

    // 6. Start web dev server if framework specified
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

    // 7. Start file watcher for HMR
    const serverDir = resolve(cwd, "src/server");
    const webDir = resolve(cwd, "src/web");
    const watchDirs: string[] = [];

    if (existsSync(serverDir)) watchDirs.push(serverDir);
    if (existsSync(webDir)) watchDirs.push(webDir);

    let isRestarting = false;

    const stopWatcher = startWatcher({
        dirs: watchDirs,
        extensions: [".ts", ".tsx", ".js", ".jsx", ".css", ".html", ".json"],
        ignore: ["node_modules", "dist", ".git", ".tano"],
        debounceMs: 150,
        onChange: async (path, _event) => {
            const isServerFile = path.startsWith("src/server");
            const isCSSFile = extname(path) === ".css";

            if (isServerFile) {
                if (isRestarting) return;
                isRestarting = true;

                log.info("");
                log.step(`\x1b[35m[HMR]\x1b[0m ${path} changed, restarting server...`);

                // Kill existing server process
                serverProc.kill();
                await serverProc.exited;

                // Restart server
                serverProc = startServerProcess(serverPath, cwd, serverPort);

                // Wait for new server to be ready
                let serverReady = false;
                for (let i = 0; i < 20; i++) {
                    try {
                        const res = await fetch(`http://127.0.0.1:${serverPort}/`);
                        if (res.ok || res.status === 404) {
                            serverReady = true;
                            break;
                        }
                    } catch {
                        // Not ready yet
                    }
                    await Bun.sleep(300);
                }

                if (serverReady) {
                    log.success("Server restarted");
                } else {
                    log.warn("Server may not have restarted correctly");
                }

                // Notify clients to reload
                hmr.notify("server", path);
                isRestarting = false;
            } else if (isCSSFile) {
                log.step(`\x1b[35m[HMR]\x1b[0m ${path} changed, updating styles...`);
                hmr.notify("css", path);
            } else {
                log.step(`\x1b[35m[HMR]\x1b[0m ${path} changed, reloading...`);
                hmr.notify("reload", path);
            }
        },
    });

    // 8. Open iOS Simulator (or Android emulator)
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
    log.dim(`  HMR:    ws://127.0.0.1:${HMR_PORT}`);
    log.info("");

    // 9. Log HMR client injection hint
    log.dim(`  Inject HMR client in your HTML before </body>:`);
    log.dim(`  <script src="http://127.0.0.1:${HMR_PORT}"></script>`);
    log.dim(`  Or use TANO_HMR_PORT env var in your server to inject automatically.`);
    log.info("");

    log.step("Watching for changes...");

    // Handle graceful shutdown
    process.on("SIGINT", () => {
        log.info("\n");
        log.step("Shutting down...");
        stopWatcher();
        hmr.stop();
        serverProc.kill();
        webProc?.kill();
        process.exit(0);
    });

    process.on("SIGTERM", () => {
        stopWatcher();
        hmr.stop();
        serverProc.kill();
        webProc?.kill();
        process.exit(0);
    });

    // Keep the process alive
    await serverProc.exited;
}
