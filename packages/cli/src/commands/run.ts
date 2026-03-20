import { log } from "../utils/logger";
import { existsSync } from "fs";
import { resolve, join } from "path";

export default async function run(args: string[]): Promise<void> {
    const platform = args[0];
    const cwd = process.cwd();

    log.heading("tano run");
    log.info("");

    if (!platform) {
        log.error("Please specify a platform:");
        log.info("  tano run ios");
        log.info("  tano run android");
        log.info("");
        process.exit(1);
    }

    if (platform !== "ios" && platform !== "android") {
        log.error(`Unknown platform: ${platform}`);
        log.info("  Supported platforms: ios, android");
        log.info("");
        process.exit(1);
    }

    // Check we're in a tano project
    if (!existsSync(join(cwd, "tano.config.ts"))) {
        log.error("tano.config.ts not found. Are you in a Tano project?");
        process.exit(1);
    }

    if (platform === "ios") {
        await runIOS(cwd);
    } else {
        await runAndroid(cwd);
    }
}

async function runIOS(cwd: string): Promise<void> {
    // 1. Build first
    log.step("Building for iOS...");
    const buildMod = await import("./build");
    await buildMod.default(["ios"]);

    // 2. Find built .app
    const derivedData = resolve(cwd, "dist/ios-build");
    let appPath: string | null = null;

    if (existsSync(derivedData)) {
        // Search for .app in derived data
        const findProc = Bun.spawnSync([
            "find", derivedData, "-name", "*.app", "-type", "d"
        ]);
        const apps = findProc.stdout.toString().trim().split("\n").filter(Boolean);
        if (apps.length > 0) {
            appPath = apps[0];
        }
    }

    if (!appPath) {
        // No built app — fall back to dev mode
        log.info("");
        log.info("  No .app found in dist/ios-build/");
        log.info("  Falling back to dev mode (tano dev)...");
        log.info("");
        const devMod = await import("./dev");
        await devMod.default([]);
        return;
    }

    // 3. Boot simulator
    log.step("Preparing iOS Simulator...");
    const simListProc = Bun.spawnSync(["xcrun", "simctl", "list", "devices", "available", "-j"]);
    const simData = JSON.parse(simListProc.stdout.toString());
    let targetDevice: string | null = null;
    let targetName: string = "";

    // Find booted device or first available iPhone
    for (const [runtime, devices] of Object.entries(simData.devices || {})) {
        if (!String(runtime).includes("iOS")) continue;
        for (const device of devices as any[]) {
            if (device.state === "Booted") {
                targetDevice = device.udid;
                targetName = device.name;
                break;
            }
        }
        if (targetDevice) break;
    }

    if (!targetDevice) {
        for (const [runtime, devices] of Object.entries(simData.devices || {})) {
            if (!String(runtime).includes("iOS")) continue;
            for (const device of devices as any[]) {
                if (device.isAvailable && device.name.includes("iPhone")) {
                    log.step(`Booting ${device.name}...`);
                    Bun.spawnSync(["xcrun", "simctl", "boot", device.udid]);
                    targetDevice = device.udid;
                    targetName = device.name;
                    break;
                }
            }
            if (targetDevice) break;
        }
    }

    if (!targetDevice) {
        log.error("No iOS Simulator found. Install one via Xcode.");
        process.exit(1);
    }

    // Open Simulator UI
    Bun.spawn(["open", "-a", "Simulator"]);
    await Bun.sleep(1000);

    // 4. Install and launch
    log.step(`Installing on ${targetName}...`);
    const installProc = Bun.spawnSync(["xcrun", "simctl", "install", targetDevice, appPath]);
    if (installProc.exitCode !== 0) {
        log.error("Failed to install app on simulator");
        log.dim("  " + installProc.stderr.toString());
        process.exit(1);
    }

    // Extract bundle identifier from Info.plist
    const plistProc = Bun.spawnSync([
        "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier",
        join(appPath, "Info.plist")
    ]);
    const bundleId = plistProc.stdout.toString().trim();

    if (bundleId) {
        log.step(`Launching ${bundleId}...`);
        Bun.spawnSync(["xcrun", "simctl", "launch", targetDevice, bundleId]);
        log.success(`App running on ${targetName}`);
    } else {
        log.warn("Could not determine bundle identifier");
    }

    log.info("");
}

async function runAndroid(_cwd: string): Promise<void> {
    log.step("Android run support coming soon.");
    log.info("  Use 'tano build android' to build, then install manually.");
    log.info("");
}
