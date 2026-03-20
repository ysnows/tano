/**
 * Extension Loader for iOS
 *
 * Discovers and loads extension command modules from disk.
 * Simplified from enconvo.nodejs CommandManageUtils for single-runtime iOS usage.
 *
 * Extension directory structure:
 *   {extensionPath}/{extensionName}/
 *     ├── package.json      # Extension metadata with commands[]
 *     ├── {commandName}.js  # Command handler (compiled)
 *     └── assets/           # Optional assets
 *
 * Command resolution:
 *   callId "chat_with_ai|analyze" → {extensionPath}/chat_with_ai/analyze.js
 *   With targetCommand chaining: follows targetCommand → targetCommand until final handler
 */

const fs = require('fs');
const path = require('path');

// Cache for loaded package.json metadata
const extensionInfoCache = new Map();
// Cache for resolved command info
const commandInfoCache = new Map();

/**
 * Search paths for extensions, in priority order.
 */
function getSearchPaths() {
    const paths = [];
    const extensionPath = process.env.ENCONVO_EXTENSION_PATH;
    const bundlePath = process.env.ENCONVO_BUNDLE_EXTENSIONS_PATH;

    if (extensionPath && fs.existsSync(extensionPath)) {
        paths.push(extensionPath);
    }
    if (bundlePath && fs.existsSync(bundlePath)) {
        paths.push(bundlePath);
    }
    return paths;
}

/**
 * Load and cache a package.json for an extension.
 */
function getExtensionInfo(extensionName) {
    if (extensionInfoCache.has(extensionName)) {
        return extensionInfoCache.get(extensionName);
    }

    for (const searchPath of getSearchPaths()) {
        const pkgPath = path.join(searchPath, extensionName, 'package.json');
        try {
            if (fs.existsSync(pkgPath)) {
                const raw = fs.readFileSync(pkgPath, 'utf8');
                const info = JSON.parse(raw);
                extensionInfoCache.set(extensionName, info);
                return info;
            }
        } catch (err) {
            console.log(`[ExtLoader] Failed to load ${pkgPath}: ${err.message}`);
        }
    }
    return null;
}

/**
 * Get command metadata from extension's package.json commands array.
 */
function getCommandInfo(extensionName, commandName) {
    const cacheKey = `${extensionName}|${commandName}`;
    if (commandInfoCache.has(cacheKey)) {
        return commandInfoCache.get(cacheKey);
    }

    const extInfo = getExtensionInfo(extensionName);
    if (!extInfo || !extInfo.commands) return null;

    const command = extInfo.commands.find(c => c.name === commandName);
    if (command) {
        // Attach extension-level info
        command.extensionName = extensionName;
        command.commandKey = cacheKey;
        commandInfoCache.set(cacheKey, command);
    }
    return command || null;
}

/**
 * Resolve targetCommand chains to find the final command handler.
 * Prevents infinite loops with visited set.
 *
 * Example: custom_bot|my_bot → targetCommand: "chat_with_ai|chat_command"
 *   → returns { extensionName: "chat_with_ai", commandName: "chat_command", ... }
 */
function resolveTargetCommand(extensionName, commandName) {
    const visited = new Set();
    let currentExt = extensionName;
    let currentCmd = commandName;

    while (true) {
        const key = `${currentExt}|${currentCmd}`;
        if (visited.has(key)) break; // Circular reference
        visited.add(key);

        const info = getCommandInfo(currentExt, currentCmd);
        if (!info) break;

        const target = info.targetCommand;
        if (!target || target.trim() === '') break;

        // Parse targetCommand: "extensionName|commandName"
        const parts = target.split('|');
        if (parts.length !== 2) break;

        currentExt = parts[0];
        currentCmd = parts[1];
    }

    return { extensionName: currentExt, commandName: currentCmd };
}

/**
 * Find the JS file path for a command.
 * Resolves targetCommand chains and searches all extension paths.
 *
 * @param {string} extensionName
 * @param {string} commandName
 * @returns {{ filePath: string, commandInfo: object } | null}
 */
function findCommandFile(extensionName, commandName) {
    // Resolve target command chain
    const resolved = resolveTargetCommand(extensionName, commandName);
    const finalExt = resolved.extensionName;
    const finalCmd = resolved.commandName;

    // Search for the JS file
    for (const searchPath of getSearchPaths()) {
        const filePath = path.join(searchPath, finalExt, `${finalCmd}.js`);
        try {
            if (fs.existsSync(filePath)) {
                const commandInfo = getCommandInfo(finalExt, finalCmd) || {
                    name: finalCmd,
                    extensionName: finalExt,
                    commandKey: `${finalExt}|${finalCmd}`,
                };
                return { filePath, commandInfo };
            }
        } catch (err) {
            // Continue searching
        }
    }

    return null;
}

/**
 * Load a command handler from disk.
 * Returns the default export function, or null if not found.
 *
 * @param {string} extensionName
 * @param {string} commandName
 * @returns {{ handler: Function, commandInfo: object } | null}
 */
function loadCommand(extensionName, commandName) {
    const found = findCommandFile(extensionName, commandName);
    if (!found) return null;

    try {
        const mod = require(found.filePath);
        const handler = mod.default || mod;
        if (typeof handler === 'function') {
            console.log(`[ExtLoader] Loaded: ${extensionName}|${commandName} from ${found.filePath}`);
            return { handler, commandInfo: found.commandInfo };
        }
        console.log(`[ExtLoader] No function export in ${found.filePath}`);
    } catch (err) {
        console.log(`[ExtLoader] Error loading ${found.filePath}: ${err.message}`);
    }

    return null;
}

/**
 * Discover all extensions in the search paths.
 * Returns array of { name, version, title, commands[] }.
 */
function discoverExtensions() {
    const extensions = [];

    for (const searchPath of getSearchPaths()) {
        try {
            const dirs = fs.readdirSync(searchPath);
            for (const dir of dirs) {
                const pkgPath = path.join(searchPath, dir, 'package.json');
                try {
                    if (fs.existsSync(pkgPath)) {
                        const raw = fs.readFileSync(pkgPath, 'utf8');
                        const info = JSON.parse(raw);
                        extensions.push({
                            name: info.name || dir,
                            version: info.version || '0.0.0',
                            title: info.title || info.name || dir,
                            commandCount: (info.commands || []).length,
                            path: path.join(searchPath, dir),
                        });
                    }
                } catch (err) {
                    // Skip invalid extensions
                }
            }
        } catch (err) {
            // Skip inaccessible paths
        }
    }

    return extensions;
}

/**
 * Clear all caches (for memory pressure).
 */
function clearCaches() {
    extensionInfoCache.clear();
    commandInfoCache.clear();
    // Also clear require cache for extension modules
    const searchPaths = getSearchPaths();
    for (const key of Object.keys(require.cache)) {
        for (const sp of searchPaths) {
            if (key.startsWith(sp)) {
                delete require.cache[key];
            }
        }
    }
    console.log('[ExtLoader] Caches cleared');
}

module.exports = {
    getExtensionInfo,
    getCommandInfo,
    resolveTargetCommand,
    findCommandFile,
    loadCommand,
    discoverExtensions,
    clearCaches,
};
