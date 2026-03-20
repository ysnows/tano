import { log } from "../utils/logger";
import { execSync } from "child_process";

interface CheckResult {
    label: string;
    ok: boolean;
    detail?: string;
}

function runCheck(label: string, fn: () => string | null): CheckResult {
    try {
        const detail = fn();
        return { label, ok: true, detail: detail ?? undefined };
    } catch {
        return { label, ok: false };
    }
}

function getCommandOutput(cmd: string): string {
    return execSync(cmd, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim();
}

export default async function doctor(_args: string[]): Promise<void> {
    log.heading("Tano Doctor");
    log.info("Checking your development environment...\n");

    const checks: CheckResult[] = [];

    // 1. Bun
    checks.push(
        runCheck("Bun installed", () => {
            const version = getCommandOutput("bun --version");
            return `v${version}`;
        })
    );

    // 2. Node.js (optional but good to have)
    checks.push(
        runCheck("Node.js installed", () => {
            const version = getCommandOutput("node --version");
            return version;
        })
    );

    // 3. Xcode
    checks.push(
        runCheck("Xcode Command Line Tools", () => {
            const path = getCommandOutput("xcode-select -p");
            return path;
        })
    );

    // 4. Xcode version
    checks.push(
        runCheck("Xcode version", () => {
            const version = getCommandOutput("xcodebuild -version | head -1");
            return version;
        })
    );

    // 5. iOS Simulator
    checks.push(
        runCheck("iOS Simulator available", () => {
            const output = getCommandOutput("xcrun simctl list devices available");
            const iosDevices = output
                .split("\n")
                .filter((line) => line.includes("iPhone") || line.includes("iPad"));
            if (iosDevices.length === 0) {
                throw new Error("No iOS simulators found");
            }
            return `${iosDevices.length} device(s)`;
        })
    );

    // 6. CocoaPods (optional)
    checks.push(
        runCheck("CocoaPods installed", () => {
            const version = getCommandOutput("pod --version");
            return `v${version}`;
        })
    );

    // 7. Android SDK
    checks.push(
        runCheck("Android SDK (ANDROID_HOME)", () => {
            const androidHome = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
            if (!androidHome) {
                throw new Error("ANDROID_HOME not set");
            }
            return androidHome;
        })
    );

    // 8. Git
    checks.push(
        runCheck("Git installed", () => {
            const version = getCommandOutput("git --version");
            return version.replace("git version ", "v");
        })
    );

    // Print results
    let passCount = 0;
    let failCount = 0;

    for (const check of checks) {
        log.check(check.label, check.ok, check.detail);
        if (check.ok) passCount++;
        else failCount++;
    }

    log.info("");

    if (failCount === 0) {
        log.success("All checks passed! Your environment is ready.");
    } else {
        log.warn(`${passCount} passed, ${failCount} failed.`);
        if (
            !checks.find((c) => c.label === "Android SDK (ANDROID_HOME)")?.ok
        ) {
            log.dim(
                "  Android SDK is optional — only needed for Android builds."
            );
        }
        if (
            !checks.find((c) => c.label === "CocoaPods installed")?.ok
        ) {
            log.dim(
                "  CocoaPods is optional — Tano uses Swift Package Manager by default."
            );
        }
    }

    log.info("");
}
