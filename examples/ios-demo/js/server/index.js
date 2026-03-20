/**
 * iOS Node.js Server — Unified UDS Socket + HTTP Server
 *
 * This replaces the previous js/server.js. Key changes:
 * 1. Connects to Swift UDS server via FrameCodec (length-prefixed frames)
 * 2. CommandDispatcher replaces Worker threads (async queue, shared runtime)
 * 3. HTTP server retained for WebView data access
 * 4. Commander API for extensions to call Swift native operations
 */

const net = require('net');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { encode, FrameDecoder } = require('../lib/framing');
const Commander = require('../lib/commander-ios');
const ExtensionLoader = require('../lib/extension-loader');
const PreferenceResolver = require('../lib/preference-resolver');
const WorkerShim = require('../lib/worker-threads-shim');

// Shim worker_threads module so @enconvo/api's Commander works on iOS.
// Must be registered BEFORE any extension requiring @enconvo/api is loaded.
const Module = require('module');
const originalResolveFilename = Module._resolveFilename;
Module._resolveFilename = function(request, parent, isMain, options) {
    if (request === 'worker_threads') {
        return '__worker_threads_shim__';
    }
    if (request === 'better-sqlite3') {
        return '__better_sqlite3_shim__';
    }
    if (request === 'node:url') {
        return '__node_url_shim__';
    }
    if (request === undefined || request === null || request === 'undefined') {
        console.log(`[ModuleShim] Caught require(${request}) from ${parent?.filename || 'unknown'}`);
        // Return empty module instead of crashing
        return '__empty_module__';
    }
    return originalResolveFilename.call(this, request, parent, isMain, options);
};
// Cache the shim module so require('worker_threads') returns it
require.cache['__worker_threads_shim__'] = {
    id: '__worker_threads_shim__',
    filename: '__worker_threads_shim__',
    loaded: true,
    exports: WorkerShim.shimModule,
};
// node:url shim — add pathToFileURL if missing
const urlMod = (() => {
    try {
        const u = require('url');
        if (!u.pathToFileURL) {
            u.pathToFileURL = (p) => new URL('file://' + require('path').resolve(p));
            u.fileURLToPath = (u) => {
                const url = typeof u === 'string' ? new URL(u) : u;
                return decodeURIComponent(url.pathname);
            };
        }
        if (!u.default) u.default = u;
        return u;
    } catch (e) {
        return {
            default: {},
            URL: globalThis.URL,
            pathToFileURL: (p) => new URL('file://' + p),
            fileURLToPath: (u) => decodeURIComponent(new URL(u).pathname),
        };
    }
})();
require.cache['__node_url_shim__'] = {
    id: '__node_url_shim__',
    filename: '__node_url_shim__',
    loaded: true,
    exports: urlMod,
};
require.cache['__better_sqlite3_shim__'] = {
    id: '__better_sqlite3_shim__',
    filename: '__better_sqlite3_shim__',
    loaded: true,
    exports: require('../lib/sqlite-shim'),
};
require.cache['__empty_module__'] = {
    id: '__empty_module__',
    filename: '__empty_module__',
    loaded: true,
    exports: {},
};

// Redirect console to file (JSC stdout issue)
const _log = (m) => {
    try {
        const ts = new Date().toISOString().substring(11, 23);
        fs.appendFileSync('/tmp/ejs_server_log.txt', `[${ts}] ${m}\n`);
    } catch (e) {}
};
console.log = _log;
console.error = _log;
console.warn = _log;

// === Configuration ===
const SOCKET_PATH = process.env.ENCONVO_SOCKET_PATH || '';
const EXTENSION_PATH = process.env.ENCONVO_EXTENSION_PATH || '';
const HTTP_PORT = 18899;
const LLM_API_URL = 'https://api.groq.com/openai/v1/chat/completions';
const LLM_API_KEY = process.env.GROQ_API_KEY || '';
const LLM_MODEL = 'openai/gpt-oss-120b';

console.log(`[Server] Starting iOS server...`);
console.log(`[Server] Socket path: ${SOCKET_PATH}`);
console.log(`[Server] Extension path: ${EXTENSION_PATH}`);
console.log(`[Server] PID: ${process.pid}`);

// === Command Dispatcher (replaces Worker thread pool) ===
const commandModules = new Map(); // Cached loaded modules

class CommandDispatcher {
    constructor(socket) {
        this.socket = socket;
        this.running = new Map(); // callId -> AbortController
    }

    /**
     * Dispatch a command for execution.
     */
    async dispatch(msg) {
        const callId = msg.callId || '';
        const requestId = msg.requestId || '';
        const stateId = msg.stateId || '';
        const payloads = msg.payloads || {};

        console.log(`[Dispatch] start: ${callId} (reqId: ${requestId})`);

        // Per-dispatch context — avoids global state corruption with concurrent commands
        const context = { callId, requestId, stateId };

        // Create abort controller for cancellation
        const abortController = new AbortController();
        this.running.set(callId, abortController);

        try {
            // Parse callId = "extensionName|commandName"
            const [extensionName, commandName] = callId.split('|');
            if (!extensionName || !commandName) {
                this.sendResult(callId, requestId, stateId, { error: 'Invalid callId format' }, 400);
                return;
            }

            // Load command module (synchronous require — no await yield here)
            const handler = await this.loadCommand(extensionName, commandName);
            if (!handler) {
                this.sendResult(callId, requestId, stateId, { error: `Command not found: ${callId}` }, 404);
                return;
            }

            // Resolve preferences for this command
            let resolvedOptions = payloads.options || {};
            try {
                const prefConfig = await PreferenceResolver.loadCommandConfig(
                    callId,
                    { input_text: payloads.input_text || '', workspace: payloads.working_directory || '' },
                    resolvedOptions
                );
                resolvedOptions = { ...prefConfig, ...resolvedOptions };
            } catch (err) {
                console.log(`[Dispatch] Preference resolution failed for ${callId}: ${err.message}`);
            }

            // Build request object matching Enconvo's Request interface
            const request = {
                callId,
                requestId,
                stateId,
                context,
                options: resolvedOptions,
                env: payloads.env || {},
                input: payloads.input || payloads,
                signal: abortController.signal,
            };

            // Set global context RIGHT BEFORE handler execution
            Commander.setContext(callId, requestId, stateId);

            // Execute the command handler
            const result = await handler(request);

            // Send result back
            if (result !== undefined) {
                this.sendResult(callId, requestId, stateId, result, 0);
            }
        } catch (err) {
            if (err.name === 'AbortError') {
                console.log(`[Dispatch] Cancelled: ${callId}`);
            } else {
                console.log(`[Dispatch] Error: ${callId}: ${err.message}`);
                this.sendResult(callId, requestId, stateId, { error: err.message }, 500);
            }
        } finally {
            this.running.delete(callId);
        }
    }

    /**
     * Load a command module. Uses ExtensionLoader for package.json parsing,
     * targetCommand resolution, and multi-path search.
     */
    async loadCommand(extensionName, commandName) {
        const cacheKey = `${extensionName}|${commandName}`;

        // Check cache
        if (commandModules.has(cacheKey)) {
            return commandModules.get(cacheKey);
        }

        // Use ExtensionLoader which handles:
        // - package.json parsing
        // - targetCommand chain resolution
        // - Multi-path search (EXTENSION_PATH, BUNDLE_EXTENSIONS_PATH)
        const loaded = ExtensionLoader.loadCommand(extensionName, commandName);
        if (loaded && typeof loaded.handler === 'function') {
            commandModules.set(cacheKey, loaded.handler);
            return loaded.handler;
        }

        return null;
    }

    /**
     * Send a result back to Swift via UDS.
     */
    sendResult(callId, requestId, stateId, payloads, status = 0) {
        const msg = {
            type: 'response',
            method: 'start',
            callId,
            requestId,
            stateId,
            payloads: { ...payloads, status },
        };
        const frame = encode(JSON.stringify(msg));
        this.socket.write(frame);
    }

    /**
     * Cancel a running command.
     */
    cancel(callId) {
        const controller = this.running.get(callId);
        if (controller) {
            controller.abort();
            this.running.delete(callId);
            console.log(`[Dispatch] Cancelled: ${callId}`);
        }
    }

    /**
     * Cancel all running commands.
     */
    cancelAll() {
        for (const [callId, controller] of this.running) {
            controller.abort();
        }
        this.running.clear();
    }

    /**
     * Clear all caches (for memory pressure).
     */
    clearCache() {
        commandModules.clear();
        ExtensionLoader.clearCaches();
        console.log('[Dispatch] All caches cleared');
    }

    /**
     * List discovered extensions.
     */
    listExtensions() {
        return ExtensionLoader.discoverExtensions();
    }
}

// === UDS Socket Connection ===
let udsSocket = null;
let dispatcher = null;
const frameDecoder = new FrameDecoder();

function connectUDS() {
    if (!SOCKET_PATH) {
        console.log('[UDS] No socket path configured, skipping UDS connection');
        return;
    }

    console.log(`[UDS] Connecting to ${SOCKET_PATH}...`);

    udsSocket = net.createConnection({ path: SOCKET_PATH }, () => {
        console.log('[UDS] Connected to Swift UDS server');

        Commander.init(udsSocket);
        WorkerShim.fakeParentPort.setSocket(udsSocket);  // Wire parentPort to UDS
        dispatcher = new CommandDispatcher(udsSocket);

        // Send "connected" message
        const msg = {
            type: 'request',
            method: 'connected',
            callId: '',
            requestId: crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(),
            stateId: '',
            payloads: {
                platform: process.platform,
                arch: process.arch,
                version: process.version,
                pid: process.pid,
            },
        };
        const frame = encode(JSON.stringify(msg));
        udsSocket.write(frame);
    });

    udsSocket.on('data', (data) => {
        const messages = frameDecoder.feed(data);
        for (const msgStr of messages) {
            try {
                const msg = JSON.parse(msgStr);
                handleUDSMessage(msg);
            } catch (err) {
                console.log(`[UDS] Parse error: ${err.message}`);
            }
        }
    });

    udsSocket.on('error', (err) => {
        console.log(`[UDS] Error: ${err.message}`);
    });

    udsSocket.on('close', () => {
        console.log('[UDS] Disconnected');
        udsSocket = null;
        frameDecoder.reset();

        // Reconnect after delay
        setTimeout(connectUDS, 2000);
    });
}

function handleUDSMessage(msg) {
    const method = msg.method;
    const type = msg.type;

    // Handle responses to our requests (Commander.sendRequest + SDK Commander)
    if (type === 'response') {
        Commander.resolveRequest(msg);
        // Also deliver to fake parentPort so @enconvo/api Commander can match responses
        WorkerShim.deliverMessage(msg);
        return;
    }

    // Handle requests from Swift
    switch (method) {
        case 'start':
            if (dispatcher) {
                dispatcher.dispatch(msg);
            }
            break;

        case 'cancel': {
            const callId = msg.callId;
            if (callId && dispatcher) {
                dispatcher.cancel(callId);
            }
            break;
        }

        case 'cancelAllTask':
            if (dispatcher) {
                dispatcher.cancelAll();
            }
            break;

        case 'terminate': {
            const callIds = msg.payloads?.callIds || [];
            const all = msg.payloads?.all || false;
            if (all && dispatcher) {
                dispatcher.cancelAll();
            } else if (dispatcher) {
                callIds.forEach(id => dispatcher.cancel(id));
            }
            break;
        }

        case 'clearCache':
            if (dispatcher) {
                dispatcher.clearCache();
            }
            break;

        case 'listExtensions': {
            if (dispatcher) {
                const extensions = dispatcher.listExtensions();
                const response = {
                    type: 'response',
                    method: 'listExtensions',
                    callId: msg.callId || '',
                    requestId: msg.requestId || '',
                    stateId: msg.stateId || '',
                    payloads: { extensions },
                };
                const frame = encode(JSON.stringify(response));
                udsSocket.write(frame);
            }
            break;
        }

        default:
            console.log(`[UDS] Unhandled method: ${method}`);
            break;
    }
}

// === HTTP API Server (for WebView) ===
const httpServer = http.createServer(async (req, res) => {
    // CORS for WebView
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    // Read body
    let body = '';
    for await (const chunk of req) body += chunk;

    const url = req.url;
    console.log(`${req.method} ${url}`);

    try {
        if (url === '/terminal' || url.startsWith('/terminal?')) {
            const termPath = path.join(__dirname, '..', '..', 'web', 'terminal.html');
            try {
                res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
                res.end(fs.readFileSync(termPath, 'utf8'));
            } catch (e) {
                respond(res, { error: 'Terminal page not found' }, 404);
            }

        } else if (url === '/settings' || url.startsWith('/settings?')) {
            // Serve settings HTML page
            const settingsPath = path.join(__dirname, '..', '..', 'web', 'settings.html');
            try {
                const html = fs.readFileSync(settingsPath, 'utf8');
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(html);
            } catch (e) {
                respond(res, { error: 'Settings page not found' }, 404);
            }

        } else if (url.startsWith('/webapp') || url.startsWith('/_next/') || url === '/favicon.ico') {
            // Serve enconvo_webapp static files
            // /_next/ paths are the Next.js static asset convention
            serveWebapp(req, res, url);

        } else if (url === '/api/info') {
            respond(res, {
                platform: process.platform,
                arch: process.arch,
                version: process.version,
                pid: process.pid,
                engine: 'JavaScriptCore',
                uptime: process.uptime(),
                uds: !!udsSocket,
            });

        } else if (url === '/api/test') {
            const { name } = JSON.parse(body || '{}');
            respond(res, await runTest(name));

        } else if (url === '/api/chat') {
            const { prompt, messages: chatMessages, apiKey, model, stream, provider, baseUrl } = JSON.parse(body);

            // Fall back to saved preferences if no key in request
            let key = apiKey || LLM_API_KEY;
            let chatModel = model;
            let chatProvider = provider;
            let chatBaseUrl = baseUrl;
            if (!key) {
                try {
                    const prefs = await PreferenceResolver.loadCommandConfig('llm_ios|chat');
                    key = prefs.api_key || '';
                    chatModel = chatModel || prefs.model;
                    chatProvider = chatProvider || prefs.provider || 'groq';
                    chatBaseUrl = chatBaseUrl || prefs.base_url;
                } catch (e) {}
            }
            if (!key) { respond(res, { error: 'No API key. Set one in Extensions > llm_ios > chat.' }, 400); return; }

            if (stream) {
                await streamChatIOS(res, prompt, key, chatModel, chatProvider, chatBaseUrl, chatMessages);
            } else {
                const { chatCompletion } = require('../extensions/llm_ios/llm-core');
                const result = await chatCompletion({
                    apiKey: key, provider: chatProvider || 'groq',
                    baseUrl: chatBaseUrl || undefined,
                    model: chatModel || 'llama-3.3-70b-versatile',
                    messages: chatMessages || [{ role: 'user', content: prompt }],
                    stream: false, maxTokens: 4096,
                });
                respond(res, result);
            }

        } else if (url === '/api/command') {
            // Execute a command via UDS
            const { callId, stateId, input } = JSON.parse(body);
            if (!callId) { respond(res, { error: 'Missing callId' }, 400); return; }
            if (dispatcher) {
                await dispatcher.dispatch({
                    method: 'start',
                    callId,
                    requestId: crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(),
                    stateId: stateId || '',
                    payloads: input || {},
                });
                respond(res, { success: true });
            } else {
                respond(res, { error: 'UDS not connected' }, 503);
            }

        } else if (url === '/api/preferences') {
            // Get/set preferences for a command
            const { commandKey, name, value, action } = JSON.parse(body || '{}');
            if (action === 'set' && commandKey && name !== undefined) {
                PreferenceResolver.savePreference(commandKey, name, value);
                respond(res, { success: true });
            } else if (commandKey) {
                const config = await PreferenceResolver.loadCommandConfig(commandKey);
                respond(res, config);
            } else {
                respond(res, { error: 'Missing commandKey' }, 400);
            }

        } else if (url === '/api/extensions') {
            // List discovered extensions
            if (dispatcher) {
                respond(res, { extensions: dispatcher.listExtensions() });
            } else {
                respond(res, { extensions: [] });
            }

        } else if (url === '/api/webapp') {
            // Handle webapp parentPort messages (extension settings, preferences, etc.)
            const msg = JSON.parse(body || '{}');
            const method = msg.method || '';
            const callId = msg.callId || '';
            const payloads = msg.payloads || {};

            // Route based on method — these are the commands the webapp sends
            if (method.includes('|') || method.startsWith('enconvo://')) {
                // Command execution: method is a commandKey like "enconvo|extension_management"
                const cmdKey = method.replace('enconvo://', '').replace(/\//g, '|');
                try {
                    const result = await PreferenceResolver.loadCommandConfig(cmdKey);
                    respond(res, { ...result, success: true });
                } catch (e) {
                    respond(res, { error: e.message }, 500);
                }
            } else if (method === 'getExtensionOptions' || method === 'getCommandOptions') {
                const key = payloads.commandKey || payloads.extensionName || '';
                const config = await PreferenceResolver.loadCommandConfig(key);
                respond(res, config);
            } else if (method === 'setExtensionCommandPreferenceValue') {
                const key = payloads.commandKey || '';
                const name = payloads.name || '';
                const value = payloads.value;
                if (key && name !== undefined) {
                    PreferenceResolver.savePreference(key, name, value);
                }
                respond(res, { success: true });
            } else {
                // Forward to native via UDS
                try {
                    const result = await Commander.sendRequest({ method, payloads });
                    respond(res, result);
                } catch (e) {
                    respond(res, { error: e.message }, 500);
                }
            }

        } else if (url === '/api/python') {
            // Execute Python code via Pyodide (loaded at runtime)
            const { code, install } = JSON.parse(body || '{}');
            const pythonRunner = require('../lib/python-runner');
            if (install) {
                try {
                    const result = await pythonRunner.installPackage(install);
                    respond(res, result);
                } catch (e) { respond(res, { error: e.message }, 500); }
            } else if (code) {
                const result = await pythonRunner.run(code);
                respond(res, result);
            } else {
                respond(res, { error: 'Missing code or install parameter' }, 400);
            }

        } else if (url === '/api/shell') {
            // Execute a shell command
            const { command } = JSON.parse(body || '{}');
            if (!command) { respond(res, { error: 'Missing command' }, 400); return; }
            const shell = require('../lib/shell');
            const output = await shell.execute(command);
            respond(res, { output, cwd: shell.getCwd() });

        } else if (url === '/api/native') {
            // Call a native Swift function via UDS
            const { method: nativeMethod, payloads } = JSON.parse(body);
            if (!nativeMethod) { respond(res, { error: 'Missing method' }, 400); return; }
            try {
                const result = await Commander.sendRequest({ method: nativeMethod, payloads: payloads || {} });
                respond(res, result);
            } catch (err) {
                respond(res, { error: err.message }, 500);
            }

        } else {
            respond(res, { error: 'Not found' }, 404);
        }
    } catch (e) {
        console.log('Error: ' + e.message);
        respond(res, { error: e.message }, 500);
    }
});

function respond(res, data, status = 200) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
}

// === Webapp Static File Server ===
// Serves the enconvo_webapp Next.js static export from the extensions directory.
const MIME_TYPES = {
    '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css',
    '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff': 'font/woff',
    '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.map': 'application/json',
};

function findWebappRoot() {
    // Search for the webapp static export in extension paths
    const candidates = [
        process.env.ENCONVO_BUNDLE_EXTENSIONS_PATH && path.join(process.env.ENCONVO_BUNDLE_EXTENSIONS_PATH, 'enconvo_webapp', 'assets', 'enconvo_webapp'),
        process.env.ENCONVO_EXTENSION_PATH && path.join(process.env.ENCONVO_EXTENSION_PATH, 'enconvo_webapp', 'assets', 'enconvo_webapp'),
        // macOS user home fallback (for simulator where HOME is the sandbox)
        process.env.ENCONVO_MACOS_HOME && path.join(process.env.ENCONVO_MACOS_HOME, '.config', 'enconvo', 'extension', 'enconvo_webapp', 'assets', 'enconvo_webapp'),
        // Direct macOS path detection (simulator fallback)
        (() => { try { const h = process.env.HOME || ''; const m = h.match(/^(\/Users\/[^/]+)/); return m ? path.join(m[1], '.config', 'enconvo', 'extension', 'enconvo_webapp', 'assets', 'enconvo_webapp') : null; } catch(e) { return null; } })(),
        // iOS sandbox fallback
        path.join(process.env.HOME || '/tmp', '.config', 'enconvo', 'extension', 'enconvo_webapp', 'assets', 'enconvo_webapp'),
    ].filter(Boolean);

    for (const candidate of candidates) {
        if (fs.existsSync(path.join(candidate, 'index.html'))) {
            return candidate;
        }
    }
    return null;
}

let _webappRoot = null;
function getWebappRoot() {
    if (!_webappRoot) _webappRoot = findWebappRoot();
    return _webappRoot;
}

function serveWebapp(req, res, url) {
    const root = getWebappRoot();
    if (!root) {
        res.writeHead(404, { 'Content-Type': 'text/html' });
        res.end('<h2>Webapp not found</h2><p>The enconvo_webapp extension is not installed.</p><p>Install it or copy the static export to the extensions directory.</p>');
        return;
    }

    // Strip /webapp prefix (but keep /_next/ paths as-is since they're absolute)
    let filePath = url.startsWith('/webapp') ? (url.replace(/^\/webapp/, '') || '/') : url;
    // Strip query string
    filePath = filePath.split('?')[0];
    if (filePath === '/' || filePath === '') filePath = '/index.html';

    // Try the exact path, then try with .html extension (Next.js static export convention)
    let fullPath = path.join(root, filePath);
    if (!fs.existsSync(fullPath) && !path.extname(fullPath)) {
        // Try index.html in subdirectory (Next.js route convention)
        const indexPath = path.join(fullPath, 'index.html');
        if (fs.existsSync(indexPath)) {
            fullPath = indexPath;
        } else {
            // Try .html extension
            fullPath = fullPath + '.html';
        }
    }

    if (!fs.existsSync(fullPath) || !fullPath.startsWith(root)) {
        // Fall back to root index.html for client-side routing
        fullPath = path.join(root, 'index.html');
    }

    try {
        const ext = path.extname(fullPath).toLowerCase();
        const contentType = MIME_TYPES[ext] || 'application/octet-stream';
        // Read text files as UTF-8 string, binary files as Buffer
        const isText = ['.html', '.js', '.css', '.json', '.svg', '.map'].includes(ext);
        const content = isText ? fs.readFileSync(fullPath, 'utf8') : fs.readFileSync(fullPath);
        res.writeHead(200, {
            'Content-Type': contentType + (isText ? '; charset=utf-8' : ''),
            'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600',
        });
        res.end(content);
    } catch (e) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Internal server error: ' + e.message);
    }
}

// === LLM Chat (non-streaming) ===
function chat(prompt, apiKey, model) {
    return new Promise((resolve, reject) => {
        const reqBody = JSON.stringify({
            model: model || LLM_MODEL,
            messages: [{ role: 'user', content: prompt }],
            max_completion_tokens: 2048,
            stream: false,
        });
        const req = https.request({
            hostname: 'api.groq.com', port: 443,
            path: '/openai/v1/chat/completions',
            method: 'POST',
            headers: {
                'Authorization': 'Bearer ' + apiKey,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(reqBody),
                'Connection': 'close',
            },
            agent: false,
        }, (apiRes) => {
            let data = '';
            apiRes.on('data', c => data += c);
            apiRes.on('end', () => {
                try {
                    const d = JSON.parse(data);
                    if (d.error) reject(new Error(d.error.message));
                    else resolve({ content: d.choices[0].message.content, model: d.model, usage: d.usage });
                } catch(e) { reject(e); }
            });
        });
        req.on('error', reject);
        req.write(reqBody);
        req.end();
    });
}

// === LLM Chat (SSE streaming) ===
function streamChat(res, prompt, apiKey, model) {
    return new Promise((resolve, reject) => {
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*',
        });

        const reqBody = JSON.stringify({
            model: model || LLM_MODEL,
            messages: [{ role: 'user', content: prompt }],
            max_completion_tokens: 2048,
            stream: true,
        });

        const apiReq = https.request({
            hostname: 'api.groq.com', port: 443,
            path: '/openai/v1/chat/completions',
            method: 'POST',
            headers: {
                'Authorization': 'Bearer ' + apiKey,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(reqBody),
                'Connection': 'close',
            },
            agent: false,
        }, (apiRes) => {
            apiRes.on('data', (chunk) => { res.write(chunk); });
            apiRes.on('end', () => { res.end(); resolve(); });
        });
        apiReq.on('error', (e) => {
            res.write('data: ' + JSON.stringify({ error: e.message }) + '\n\n');
            res.end();
            reject(e);
        });
        apiReq.write(reqBody);
        apiReq.end();
    });
}

// === Streaming Chat via iOS LLM Provider ===
async function streamChatIOS(res, prompt, apiKey, model, provider, baseUrl, messages) {
    const { chatCompletion, parseSSEStream } = require('../extensions/llm_ios/llm-core');

    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
    });

    try {
        const response = await chatCompletion({
            apiKey,
            provider: provider || 'groq',
            baseUrl: baseUrl || undefined,
            model: model || 'llama-3.3-70b-versatile',
            messages: messages || [{ role: 'user', content: prompt }],
            stream: true,
            temperature: 0.7,
            maxTokens: 4096,
        });

        if (response.statusCode !== 200) {
            let errBody = '';
            for await (const chunk of response.stream) errBody += chunk.toString();
            res.write(`data: ${JSON.stringify({ error: errBody })}\n\n`);
            res.end();
            return;
        }

        // Pipe SSE directly from provider to WebView
        response.stream.on('data', (chunk) => res.write(chunk));
        response.stream.on('end', () => res.end());
    } catch (err) {
        res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
        res.end();
    }
}

// === Node.js API Tests ===
async function runTest(name) {
    switch (name) {
        case 'fs': {
            const f = path.join(os.tmpdir(), 'ejs_test_' + Date.now() + '.txt');
            fs.writeFileSync(f, 'Hello from Edge.js!');
            const c = fs.readFileSync(f, 'utf8');
            fs.unlinkSync(f);
            return { result: '✓ fs: ' + c };
        }
        case 'crypto':
            return {
                result: '✓ crypto: uuid=' +
                    (crypto.randomUUID ? crypto.randomUUID() : 'N/A') +
                    ' sha256=' + crypto.createHash('sha256').update('test').digest('hex').substring(0, 16)
            };
        case 'path':
            return { result: '✓ path.join: ' + path.join('/app', 'data', 'file.js') };
        case 'buffer': {
            const s = 'Edge.js iOS';
            const e = Buffer.from(s).toString('base64');
            return { result: '✓ Buffer.base64: ' + Buffer.from(e, 'base64').toString() };
        }
        case 'events': {
            const EE = require('events');
            const ee = new EE();
            let msg = '';
            ee.on('t', m => msg = m);
            ee.emit('t', 'hello from EventEmitter');
            return { result: '✓ events: ' + msg };
        }
        case 'dns':
            return new Promise((resolve) => {
                require('dns').lookup('localhost', (e, addr) => {
                    resolve({ result: e ? '✗ dns: ' + e.message : '✓ dns: ' + addr });
                });
            });
        case 'http':
            return { result: '✓ http: native https.request works on JSC!' };
        case 'uds':
            return { result: '✓ UDS: ' + (udsSocket ? 'connected' : 'not connected') };
        case 'extensions': {
            const exts = ExtensionLoader.discoverExtensions();
            if (exts.length === 0) {
                return { result: '⚠ extensions: none found (search paths: ' + JSON.stringify(ExtensionLoader.discoverExtensions()) + ')' };
            }
            const names = exts.map(e => `${e.name}@${e.version}(${e.commandCount}cmds)`).join(', ');
            return { result: '✓ extensions: ' + names };
        }
        case 'llm': {
            // Test the iOS LLM provider — reads key from env or saved preferences
            let testKey = process.env.GROQ_API_KEY || '';
            if (!testKey) {
                try { testKey = (await PreferenceResolver.loadCommandConfig('llm_ios|chat')).api_key || ''; } catch(e) {}
            }
            if (!testKey) {
                return { result: '⚠ llm: no API key (set via API Key button or preferences)' };
            }
            try {
                const { chatCompletion } = require('../extensions/llm_ios/llm-core');
                const r = await chatCompletion({
                    apiKey: testKey,
                    provider: 'groq',
                    model: 'llama-3.3-70b-versatile',
                    messages: [{ role: 'user', content: 'Say "iOS LLM works!" in exactly 3 words.' }],
                    stream: false,
                    maxTokens: 20,
                });
                return { result: '✓ llm: ' + (r.content || '').substring(0, 50) + ' (model: ' + r.model + ')' };
            } catch (e) {
                return { result: '✗ llm: ' + e.message };
            }
        }
        case 'command': {
            // Test executing the bundled hello_world|greet command
            const loaded = ExtensionLoader.loadCommand('hello_world', 'greet');
            if (!loaded) {
                return { result: '✗ command: hello_world|greet not found' };
            }
            try {
                const result = await loaded.handler({ options: { name: 'iOS Tester' }, input: {}, context: {} });
                return { result: '✓ command: ' + (result.content || JSON.stringify(result)) };
            } catch (e) {
                return { result: '✗ command error: ' + e.message };
            }
        }
        case 'sqlite': {
            // Test SQLite via Swift bridge (UDS → SQLiteBridge.swift → libsqlite3)
            try {
                const tmpDb = require('os').tmpdir() + '/edgejs_test.db';
                const r1 = await new Promise((resolve) => {
                    const http = require('http');
                    const data = JSON.stringify({ method: 'sqlite', payloads: { action: 'exec', db: tmpDb, sql: 'CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ts INTEGER DEFAULT (strftime(\'%s\',\'now\')))' } });
                    const req = http.request({ hostname: '127.0.0.1', port: 18899, path: '/api/native', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (res) => { let b = ''; res.on('data', c => b += c); res.on('end', () => resolve(JSON.parse(b))); });
                    req.write(data); req.end();
                });
                // Insert
                const r2 = await new Promise((resolve) => {
                    const http = require('http');
                    const data = JSON.stringify({ method: 'sqlite', payloads: { action: 'run', db: tmpDb, sql: 'INSERT INTO test (name) VALUES (?)', params: ['EdgeJS iOS SQLite'] } });
                    const req = http.request({ hostname: '127.0.0.1', port: 18899, path: '/api/native', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (res) => { let b = ''; res.on('data', c => b += c); res.on('end', () => resolve(JSON.parse(b))); });
                    req.write(data); req.end();
                });
                // Query
                const r3 = await new Promise((resolve) => {
                    const http = require('http');
                    const data = JSON.stringify({ method: 'sqlite', payloads: { action: 'query', db: tmpDb, sql: 'SELECT * FROM test ORDER BY id DESC LIMIT 1' } });
                    const req = http.request({ hostname: '127.0.0.1', port: 18899, path: '/api/native', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (res) => { let b = ''; res.on('data', c => b += c); res.on('end', () => resolve(JSON.parse(b))); });
                    req.write(data); req.end();
                });
                const row = r3.rows ? r3.rows[0] : null;
                if (row) {
                    return { result: '✓ sqlite: name=' + row.name + ', id=' + row.id };
                } else {
                    return { result: '✗ sqlite: no rows returned. exec=' + JSON.stringify(r1) + ' run=' + JSON.stringify(r2) };
                }
            } catch (e) {
                return { result: '✗ sqlite: ' + e.message };
            }
        }
        case 'pathtest': {
            try {
                const p = require('path');
                return { result: '✓ path.resolve type: ' + typeof p.resolve + ', sep: ' + p.sep };
            } catch (e) {
                return { result: '✗ path: ' + e.message };
            }
        }
        case 'env':
            return {
                result: '✓ HOME=' + (process.env.HOME || 'unset') +
                    ' | DATA=' + (process.env.ENCONVO_DATA_PATH || 'unset') +
                    ' | EXT=' + (process.env.ENCONVO_EXTENSION_PATH || 'unset').substring(0, 40) +
                    ' | BUNDLE=' + (process.env.ENCONVO_BUNDLE_EXTENSIONS_PATH || 'unset').substring(0, 40)
            };
        case 'info':
            return {
                result: '✓ ' + process.platform + '/' + process.arch + ' ' + process.version +
                    ' | Engine: JSC | UDS: ' + (udsSocket ? 'yes' : 'no')
            };
        default:
            return { result: 'Unknown test: ' + name };
    }
}

// === Event Loop Watchdog ===
// Detects if the single-threaded event loop is blocked for too long.
// Since EdgeJS has no Worker threads, a synchronous command can freeze everything.
let watchdogLastTick = Date.now();
const WATCHDOG_INTERVAL = 2000;  // Check every 2s
const WATCHDOG_THRESHOLD = 500;  // Warn if blocked >500ms

setInterval(() => {
    const now = Date.now();
    const delta = now - watchdogLastTick;
    if (delta > WATCHDOG_INTERVAL + WATCHDOG_THRESHOLD) {
        console.log(`[Watchdog] Event loop blocked for ${delta - WATCHDOG_INTERVAL}ms`);
    }
    watchdogLastTick = now;
}, WATCHDOG_INTERVAL).unref();  // unref so it doesn't keep the process alive

// === Start ===

// 1. Start HTTP server for WebView
httpServer.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        console.log(`[Server] FATAL: Port ${HTTP_PORT} already in use. Another server instance may be running.`);
        // Try next port
        const altPort = HTTP_PORT + 1;
        httpServer.listen(altPort, '127.0.0.1', () => {
            console.log(`[Server] HTTP server on http://127.0.0.1:${altPort} (fallback port)`);
            fs.writeFileSync('/tmp/ejs_server_port.txt', String(altPort));
        });
    } else {
        console.log(`[Server] HTTP server error: ${err.message}`);
    }
});
httpServer.listen(HTTP_PORT, '127.0.0.1', () => {
    console.log(`[Server] HTTP server on http://127.0.0.1:${HTTP_PORT}`);
    fs.writeFileSync('/tmp/ejs_server_port.txt', String(HTTP_PORT));
});

// 2. Connect to Swift UDS server
connectUDS();

process.on('uncaughtException', (e) => console.log('Uncaught: ' + e.message));
process.on('unhandledRejection', (e) => console.log('Unhandled: ' + e));
