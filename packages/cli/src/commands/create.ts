import { log } from "../utils/logger";
import { existsSync, mkdirSync, readdirSync, statSync, readFileSync, writeFileSync } from "fs";
import { join, resolve, dirname } from "path";
import { execSync } from "child_process";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export default async function create(args: string[]): Promise<void> {
    const appName = args[0];

    if (!appName) {
        log.error("Please provide a project name:");
        log.info("  tano create <name>");
        log.info("");
        log.info("Example:");
        log.info("  tano create my-app");
        process.exit(1);
    }

    // Validate name
    if (!/^[a-zA-Z][a-zA-Z0-9_-]*$/.test(appName)) {
        log.error(
            "Invalid project name. Use letters, numbers, hyphens, and underscores. Must start with a letter."
        );
        process.exit(1);
    }

    const targetDir = resolve(process.cwd(), appName);

    if (existsSync(targetDir)) {
        log.error(`Directory "${appName}" already exists.`);
        process.exit(1);
    }

    log.heading(`Creating Tano project: ${appName}`);
    log.info("");

    // Locate templates directory
    const templatesDir = resolve(__dirname, "../../templates/default");

    if (!existsSync(templatesDir)) {
        log.error("Template directory not found. This is a bug in @tano/cli.");
        log.dim(`Expected: ${templatesDir}`);
        process.exit(1);
    }

    // Create project directory
    log.step("Creating project directory...");
    mkdirSync(targetDir, { recursive: true });

    // Copy template files with placeholder replacement
    log.step("Copying template files...");
    copyDir(templatesDir, targetDir, appName);

    // Install dependencies
    log.step("Installing dependencies...");
    try {
        execSync("bun install", {
            cwd: targetDir,
            stdio: "pipe",
        });
        log.success("Dependencies installed.");
    } catch {
        log.warn(
            "Could not install dependencies. Run 'bun install' manually in the project directory."
        );
    }

    // Print success message
    log.info("");
    log.success(`Project "${appName}" created successfully!`);
    log.info("");
    log.info("  Next steps:");
    log.info("");
    log.info(`    cd ${appName}`);
    log.info("    tano dev          # Start development server");
    log.info("    tano doctor       # Check your environment");
    log.info("    tano build ios    # Build for iOS");
    log.info("");
}

function copyDir(src: string, dest: string, appName: string): void {
    const entries = readdirSync(src);

    for (const entry of entries) {
        const srcPath = join(src, entry);
        const destPath = join(dest, entry);
        const stat = statSync(srcPath);

        if (stat.isDirectory()) {
            mkdirSync(destPath, { recursive: true });
            copyDir(srcPath, destPath, appName);
        } else {
            let content = readFileSync(srcPath, "utf-8");
            content = content.replace(/\{\{APP_NAME\}\}/g, appName);
            writeFileSync(destPath, content, "utf-8");
        }
    }
}
