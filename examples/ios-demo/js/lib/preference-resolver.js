/**
 * Preference Resolver for iOS
 *
 * Resolves command preferences from multiple storage backends,
 * matching the macOS CommandManageUtils.loadCommandConfig() behavior.
 *
 * Storage backends (storeType):
 *   - "native-kv" (default) → UserDefaults via UDS (Commander.sendRequest)
 *   - "file://{path}" → read file from disk
 *   - "preference-key:{key}" → delegate to another preference
 *   - Direct key lookup from installed_preferences JSON files
 *
 * Special preference types:
 *   - "extension" / "provider" → recursively load another command's config
 *   - "password" → decrypt via native bridge
 *   - "dropdown" with dataProxy → load options from another command
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const Commander = require('./commander-ios');

/**
 * Create directories recursively (polyfill for JSC where recursive option may fail).
 */
function mkdirRecursive(dirPath) {
    if (fs.existsSync(dirPath)) return;
    const parent = path.dirname(dirPath);
    if (parent !== dirPath && !fs.existsSync(parent)) {
        mkdirRecursive(parent);
    }
    try { fs.mkdirSync(dirPath); } catch (e) {
        if (e.code !== 'EEXIST') throw e;
    }
}

// Cache for loaded preference files
const preferenceCache = new Map();
const commandInfoCache = new Map();

/**
 * Get the preferences storage directory.
 * On iOS, uses ENCONVO_DATA_PATH (set by Swift) which points to App Support.
 * Falls back to $HOME/Library/Application Support/enconvo/ for iOS compatibility.
 * On macOS, uses ~/.config/enconvo/ (standard Enconvo path).
 */
let _dataDir = null;
function getDataDir() {
    if (_dataDir) return _dataDir;

    // Try multiple writable paths — avoid 'Application Support' (space causes issues in JSC mkdir)
    const home = process.env.HOME || os.tmpdir();
    const candidates = [
        path.join(home, 'Library', 'enconvo'),
        path.join(home, 'Documents', 'enconvo'),
        path.join(os.tmpdir(), 'enconvo_data'),
    ];

    for (const candidate of candidates) {
        try {
            if (!fs.existsSync(candidate)) fs.mkdirSync(candidate);
            // Test writability by creating subdirs
            const prefsDir = path.join(candidate, 'installed_preferences');
            const cmdsDir = path.join(candidate, 'installed_commands');
            if (!fs.existsSync(prefsDir)) fs.mkdirSync(prefsDir);
            if (!fs.existsSync(cmdsDir)) fs.mkdirSync(cmdsDir);
            _dataDir = candidate;
            console.log(`[PrefResolver] Data dir: ${_dataDir}`);
            return _dataDir;
        } catch (e) {
            // Try next candidate
        }
    }

    // Last resort: /tmp
    _dataDir = path.join(os.tmpdir(), 'enconvo_data');
    try { fs.mkdirSync(_dataDir); } catch (e) {}
    try { fs.mkdirSync(path.join(_dataDir, 'installed_preferences')); } catch (e) {}
    try { fs.mkdirSync(path.join(_dataDir, 'installed_commands')); } catch (e) {}
    console.log(`[PrefResolver] Data dir (fallback): ${_dataDir}`);
    return _dataDir;
}

function getPreferencesDir() {
    return path.join(getDataDir(), 'installed_preferences');
}

function getCommandsDir() {
    return path.join(getDataDir(), 'installed_commands');
}

/**
 * Read a preference file from disk.
 * Returns the parsed JSON or empty object.
 */
function getPreferenceInfo(preferenceKey) {
    if (preferenceCache.has(preferenceKey)) {
        return preferenceCache.get(preferenceKey);
    }

    const filePath = path.join(getPreferencesDir(), `${preferenceKey}.json`);
    try {
        if (fs.existsSync(filePath)) {
            const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            preferenceCache.set(preferenceKey, data);
            return data;
        }
    } catch (err) {
        console.log(`[PrefResolver] Failed to read ${filePath}: ${err.message}`);
    }
    return {};
}

/**
 * Read command info from installed_commands.
 */
function getCommandInfo(commandKey) {
    if (commandInfoCache.has(commandKey)) {
        return commandInfoCache.get(commandKey);
    }

    const filePath = path.join(getCommandsDir(), `${commandKey}.json`);
    try {
        if (fs.existsSync(filePath)) {
            const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            commandInfoCache.set(commandKey, data);
            return data;
        }
    } catch (err) {
        console.log(`[PrefResolver] Failed to read command ${filePath}: ${err.message}`);
    }
    return null;
}

/**
 * Evaluate showOnlyWhen conditions.
 * Returns true if the preference should be visible.
 */
function evaluateShowOnlyWhen(showOnlyWhen, config) {
    if (!showOnlyWhen) return true;

    for (const [key, rule] of Object.entries(showOnlyWhen)) {
        const currentValue = config[key];
        const operator = rule.operator || 'or';
        const conditions = rule.conditions || [];

        const results = conditions.map(cond => {
            switch (cond.condition) {
                case 'eq': return currentValue === cond.value;
                case 'ne': return currentValue !== cond.value;
                case 'gt': return Number(currentValue) > Number(cond.value);
                case 'lt': return Number(currentValue) < Number(cond.value);
                case 'gte': return Number(currentValue) >= Number(cond.value);
                case 'lte': return Number(currentValue) <= Number(cond.value);
                case 'in': return Array.isArray(cond.value) && cond.value.includes(currentValue);
                case 'nin': return Array.isArray(cond.value) && !cond.value.includes(currentValue);
                default: return true;
            }
        });

        const visible = operator === 'and'
            ? results.every(r => r)
            : results.some(r => r);

        if (!visible) return false;
    }
    return true;
}

/**
 * Resolve template variables in a string.
 * Supports: {{workspace}}, {{assets.extensionName}}, {{now}}, {{input_text}}
 */
function resolveTemplateVars(str, context) {
    if (typeof str !== 'string') return str;

    return str.replace(/\{\{(\w+(?:\.\w+)?)\}\}/g, (match, key) => {
        if (key === 'now') return new Date().toISOString();
        if (key === 'input_text') return context.input_text || '';
        if (key === 'working_directory') return context.working_directory || process.cwd();
        if (key === 'responseLanguage') return context.responseLanguage || 'en';
        if (key.startsWith('assets.')) {
            const extName = key.substring(7);
            const extPath = process.env.ENCONVO_EXTENSION_PATH || '';
            return path.join(extPath, extName, 'assets');
        }
        if (key === 'workspace') return context.workspace || process.cwd();
        return match; // Leave unresolved
    });
}

/**
 * Resolve a single preference value from its storage backend.
 */
async function resolvePreferenceValue(pref, savedPrefs, context) {
    const storeType = pref.storeType || 'native-kv';
    const name = pref.name;

    // Check saved preferences first
    if (savedPrefs[name] !== undefined && savedPrefs[name] !== null) {
        return savedPrefs[name];
    }

    // Check storeType
    if (storeType.startsWith('file://')) {
        const filePath = resolveTemplateVars(storeType.replace('file://', ''), context);
        try {
            if (fs.existsSync(filePath)) {
                return fs.readFileSync(filePath, 'utf8');
            }
        } catch (err) {
            console.log(`[PrefResolver] File read error: ${err.message}`);
        }
    } else if (storeType.startsWith('preference-key:')) {
        const otherKey = storeType.replace('preference-key:', '');
        const otherPrefs = getPreferenceInfo(otherKey);
        return otherPrefs[name];
    } else if (storeType === 'native-kv') {
        // Try to get from native KV store
        try {
            const result = await Commander.sendRequest({
                method: 'getKV',
                payloads: { key: name },
            });
            if (result && result.value !== undefined) {
                return result.value;
            }
        } catch (err) {
            // KV not available, fall through to default
        }
    }

    // Use default
    return pref.default !== undefined ? pref.default : '';
}

/**
 * Load and resolve all preferences for a command.
 *
 * @param {string} commandKey - "extensionName|commandName"
 * @param {object} context - Runtime context (input_text, workspace, etc.)
 * @param {object} overrides - Runtime overrides from the request
 * @param {number} depth - Recursion depth (prevent infinite loops)
 * @returns {object} Resolved config with all preference values
 */
async function loadCommandConfig(commandKey, context = {}, overrides = {}, depth = 0) {
    if (depth > 10) {
        console.log(`[PrefResolver] Max recursion depth reached for ${commandKey}`);
        return {};
    }

    // Load command info — try installed_commands first, then fall back to package.json
    let commandInfo = getCommandInfo(commandKey);
    let preferences = (commandInfo && commandInfo.preferences) || [];

    // If no preferences from installed_commands, try the extension's package.json
    if (preferences.length === 0) {
        const ExtensionLoader = require('./extension-loader');
        const [extName, cmdName] = commandKey.split('|');
        if (extName) {
            const extInfo = ExtensionLoader.getExtensionInfo(extName);
            if (extInfo) {
                const cmd = (extInfo.commands || []).find(c => c.name === cmdName);
                if (cmd && cmd.preferences) {
                    preferences = cmd.preferences;
                    commandInfo = cmd;
                }
                // Also check extension-level preferences
                if (extInfo.preferences && extInfo.preferences.length > 0) {
                    preferences = [...preferences, ...(extInfo.preferences || [])];
                }
            }
        }
    }

    // Load saved preference values
    const savedPrefs = getPreferenceInfo(commandKey);

    // Build config object
    const config = {
        commandKey,
        title: commandInfo?.title || '',
        icon: commandInfo?.icon || '',
        description: commandInfo?.description || '',
    };

    // Apply overrides first
    Object.assign(config, overrides);

    // Resolve each preference
    for (const pref of preferences) {
        // Skip hidden/non-visible preferences
        if (pref.showOnlyWhen && !evaluateShowOnlyWhen(pref.showOnlyWhen, config)) {
            continue;
        }

        // Handle special types
        if (pref.type === 'extension' || pref.type === 'provider') {
            config[pref.name] = await resolveProviderPreference(pref, savedPrefs, context, depth);
            continue;
        }

        if (pref.type === 'group' && pref.preferences) {
            // Resolve nested group preferences
            for (const subPref of pref.preferences) {
                const value = overrides[subPref.name] !== undefined
                    ? overrides[subPref.name]
                    : await resolvePreferenceValue(subPref, savedPrefs, context);
                config[subPref.name] = value;
            }
            continue;
        }

        // Standard preference
        const value = overrides[pref.name] !== undefined
            ? overrides[pref.name]
            : await resolvePreferenceValue(pref, savedPrefs, context);
        config[pref.name] = value;
    }

    return config;
}

/**
 * Resolve a provider/extension type preference.
 * This recursively loads the selected provider's config.
 */
async function resolveProviderPreference(pref, savedPrefs, context, depth) {
    const proxyName = pref.proxyName || pref.providerCategory || pref.name;

    // Get the global default for this provider category
    const globalPrefs = getPreferenceInfo(proxyName);
    let selectedCommand = globalPrefs.defaultCommand || '';

    // Check if saved prefs override the selection
    if (savedPrefs[pref.name] && typeof savedPrefs[pref.name] === 'object') {
        selectedCommand = savedPrefs[pref.name].commandKey || selectedCommand;
    }

    if (!selectedCommand) {
        // Use defaultOptions if available
        if (pref.defaultOptions && pref.defaultOptions.length > 0) {
            const defaultOpt = pref.defaultOptions[0];
            const extName = pref.proxyName || proxyName;
            selectedCommand = `${extName}|${defaultOpt.commandName || 'default'}`;
        }
    }

    if (!selectedCommand) {
        return { commandKey: '', error: 'No provider selected' };
    }

    // Recursively load the selected provider's config
    try {
        const providerConfig = await loadCommandConfig(selectedCommand, context, {}, depth + 1);
        providerConfig.commandKey = selectedCommand;

        // Apply defaultOptions overrides
        if (pref.defaultOptions && pref.defaultOptions.length > 0) {
            for (const opt of pref.defaultOptions) {
                if (opt.modelName) providerConfig.modelName = opt.modelName;
                if (opt.temperature !== undefined) providerConfig.temperature = opt.temperature;
                if (opt.maxTokens !== undefined) providerConfig.maxTokens = opt.maxTokens;
            }
        }

        return providerConfig;
    } catch (err) {
        console.log(`[PrefResolver] Provider resolution error: ${err.message}`);
        return { commandKey: selectedCommand, error: err.message };
    }
}

/**
 * Save a preference value.
 */
function savePreference(preferenceKey, name, value) {
    const dir = getPreferencesDir();
    const filePath = path.join(dir, `${preferenceKey}.json`);

    let data = {};
    try {
        if (fs.existsSync(filePath)) {
            data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        }
    } catch (err) {}

    data[name] = value;
    data.preferenceKey = preferenceKey;

    try {
        // Create directory hierarchy — use try/catch for each level
        try { fs.mkdirSync(dir); } catch (e) { /* may already exist */ }
        if (!fs.existsSync(dir)) {
            // Fallback: create parent then child
            const parent = path.dirname(dir);
            try { fs.mkdirSync(parent); } catch (e) {}
            try { fs.mkdirSync(dir); } catch (e) {}
        }
        if (!fs.existsSync(dir)) {
            console.log(`[PrefResolver] Cannot create dir: ${dir}`);
            return;
        }
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
        // Invalidate cache
        preferenceCache.delete(preferenceKey);
    } catch (err) {
        console.log(`[PrefResolver] Failed to save preference: ${err.message}`);
    }
}

/**
 * Clear all caches.
 */
function clearCaches() {
    preferenceCache.clear();
    commandInfoCache.clear();
}

module.exports = {
    loadCommandConfig,
    getPreferenceInfo,
    getCommandInfo,
    savePreference,
    resolveTemplateVars,
    evaluateShowOnlyWhen,
    clearCaches,
};
