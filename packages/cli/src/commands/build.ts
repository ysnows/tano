import { log } from "../utils/logger";
import { existsSync, mkdirSync, cpSync } from "fs";
import { resolve, join } from "path";

export default async function build(args: string[]): Promise<void> {
    const platform = args[0];
    const cwd = process.cwd();

    log.heading("tano build");
    log.info("");

    if (!platform) {
        log.error("Please specify a platform:");
        log.info("  tano build ios");
        log.info("  tano build android");
        log.info("");
        process.exit(1);
    }

    if (platform !== "ios" && platform !== "android") {
        log.error(`Unknown platform: ${platform}`);
        log.info("  Supported platforms: ios, android");
        log.info("");
        process.exit(1);
    }

    // 1. Check we're in a tano project
    const configPath = join(cwd, "tano.config.ts");
    if (!existsSync(configPath)) {
        log.error("tano.config.ts not found. Are you in a Tano project?");
        process.exit(1);
    }

    const distDir = resolve(cwd, "dist");
    mkdirSync(distDir, { recursive: true });

    // 2. Bundle server code
    log.step("Bundling server code...");
    const serverEntry = resolve(cwd, "src/server/index.ts");
    if (!existsSync(serverEntry)) {
        log.error("Server entry not found: src/server/index.ts");
        process.exit(1);
    }

    const serverBuild = await Bun.build({
        entrypoints: [serverEntry],
        outdir: join(distDir, "server"),
        target: "bun",
        minify: true,
    });

    if (!serverBuild.success) {
        log.error("Server build failed:");
        for (const msg of serverBuild.logs) {
            log.error(`  ${msg}`);
        }
        process.exit(1);
    }
    log.success(`Server bundled → dist/server/index.js (${formatSize(serverBuild.outputs[0]?.size || 0)})`);

    // 3. Bundle web assets
    log.step("Bundling web assets...");
    const webDir = resolve(cwd, "src/web");
    const webDistDir = join(distDir, "web");
    mkdirSync(webDistDir, { recursive: true });

    if (existsSync(webDir)) {
        // Copy all web files to dist
        cpSync(webDir, webDistDir, { recursive: true });

        // If there are .ts/.tsx files, bundle them
        const webEntry = join(webDir, "index.html");
        if (existsSync(webEntry)) {
            log.success("Web assets copied → dist/web/");
        } else {
            log.warn("No index.html found in src/web/");
        }
    } else {
        log.warn("No src/web/ directory found, skipping web bundle");
    }

    // 4. Platform-specific build
    if (platform === "ios") {
        await buildIOS(cwd, distDir);
    } else {
        await buildAndroid(cwd, distDir);
    }

    log.info("");
    log.success(`Build complete for ${platform}!`);
    log.dim(`  Output: ${distDir}`);
    log.info("");
}

async function buildIOS(cwd: string, distDir: string): Promise<void> {
    log.step("Building for iOS...");

    // Check Xcode is available
    const xcodeCheck = Bun.spawnSync(["xcode-select", "-p"]);
    if (xcodeCheck.exitCode !== 0) {
        log.error("Xcode Command Line Tools not found. Run: xcode-select --install");
        process.exit(1);
    }

    // Check for ios/ directory (generated Xcode project)
    const iosDir = resolve(cwd, "ios");
    if (!existsSync(iosDir)) {
        log.info("  No ios/ directory found.");
        log.info("  The bundled server.js and web/ assets are ready in dist/");
        log.info("  To create a full iOS build, add an Xcode project in ios/");
        log.info("  or use the Tano iOS shell app.");
        log.info("");
        log.dim("  For now, you can test with: tano dev");
        return;
    }

    // If ios/ exists, try xcodebuild
    log.step("Running xcodebuild...");
    const buildProc = Bun.spawnSync([
        "xcodebuild", "build",
        "-project", join(iosDir, "App.xcodeproj"),
        "-scheme", "App",
        "-sdk", "iphonesimulator",
        "-configuration", "Debug",
        "-derivedDataPath", join(distDir, "ios-build"),
        "CODE_SIGN_IDENTITY=",
        "CODE_SIGNING_REQUIRED=NO",
        "ARCHS=arm64",
    ]);

    if (buildProc.exitCode === 0) {
        log.success("iOS build succeeded");
    } else {
        log.warn("xcodebuild failed — check your ios/ project configuration");
        log.dim("  " + buildProc.stderr.toString().split("\n")[0]);
    }
}

async function buildAndroid(_cwd: string, _distDir: string): Promise<void> {
    log.step("Building for Android...");
    log.info("  Android build support coming soon.");
    log.info("  The bundled server.js and web/ assets are ready in dist/");
    log.dim("  You can integrate them into an existing Android project.");
}

function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes}B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}
