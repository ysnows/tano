import { log } from "../utils/logger";

export default async function dev(_args: string[]): Promise<void> {
    log.heading("tano dev");
    log.info("");
    log.warn("Coming soon!");
    log.info("");
    log.info("  This command will:");
    log.info("  1. Start the Bun development server (src/server/index.ts)");
    log.info("  2. Watch for file changes and reload automatically");
    log.info("  3. Open the iOS Simulator with the Tano shell app");
    log.info("  4. Bridge the WebView to the local dev server");
    log.info("");
    log.dim("  Track progress: https://github.com/nicktano/tano");
    log.info("");
}
