import { log } from "../utils/logger";

export default async function run(args: string[]): Promise<void> {
    const platform = args[0];

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

    log.warn("Coming soon!");
    log.info("");
    log.info(`  This command will build and run your Tano app on ${platform}:`);
    log.info("  1. Build the project (same as 'tano build')");

    if (platform === "ios") {
        log.info("  2. Launch the iOS Simulator");
        log.info("  3. Install and run the app");
    } else {
        log.info("  2. Launch the Android Emulator (or use connected device)");
        log.info("  3. Install and run the APK");
    }

    log.info("");
    log.dim("  Track progress: https://github.com/nicktano/tano");
    log.info("");
}
