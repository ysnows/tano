import { log } from "../utils/logger";

export default async function build(args: string[]): Promise<void> {
    const platform = args[0];

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

    log.warn("Coming soon!");
    log.info("");
    log.info(`  This command will build your Tano app for ${platform}:`);
    log.info("  1. Bundle the Bun server code");
    log.info("  2. Bundle the web assets");
    log.info("  3. Copy bundles into the native shell project");

    if (platform === "ios") {
        log.info("  4. Run xcodebuild to produce an .app / .ipa");
    } else {
        log.info("  4. Run gradle to produce an .apk / .aab");
    }

    log.info("");
    log.dim("  Track progress: https://github.com/nicktano/tano");
    log.info("");
}
