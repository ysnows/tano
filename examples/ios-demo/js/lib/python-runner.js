/**
 * Python Runner for iOS/EdgeJS — loads Pyodide at runtime
 *
 * Pyodide (CPython compiled to WebAssembly) is loaded on first use.
 * The WASM binary + stdlib are fetched from CDN on first call (~10MB).
 * Subsequent calls use the cached runtime.
 *
 * Usage:
 *   const python = require('./python-runner');
 *   const result = await python.run('print(2 + 2)');
 *   // { output: "4\n", error: null }
 */

'use strict';

let pyodide = null;
let loading = null; // Promise if loading in progress
let outputBuffer = '';

/**
 * Load Pyodide runtime. Downloads WASM from CDN on first call.
 * Returns the pyodide instance.
 */
async function ensureLoaded() {
    if (pyodide) return pyodide;
    if (loading) return loading;

    loading = (async () => {
        console.log('[Python] Loading Pyodide runtime...');
        try {
            // Polyfill node:url.pathToFileURL if missing (JSC doesn't have it)
            try {
                const url = require('url');
                if (!url.pathToFileURL) {
                    url.pathToFileURL = (p) => new URL('file://' + require('path').resolve(p));
                    url.fileURLToPath = (u) => decodeURIComponent(new URL(String(u)).pathname);
                }
            } catch (e) {}

            // Polyfill node:vm if missing
            try {
                const vm = require('vm');
                if (!vm.runInThisContext) {
                    vm.runInThisContext = (code) => eval(code);
                }
            } catch (e) {}

            const { loadPyodide } = require('./pyodide-loader');
            pyodide = await loadPyodide({
                // Packages fetched from CDN at runtime (not bundled)
                indexURL: 'https://cdn.jsdelivr.net/pyodide/v0.27.4/full/',
                stdout: (text) => { outputBuffer += text + '\n'; },
                stderr: (text) => { outputBuffer += '[stderr] ' + text + '\n'; },
            });
            console.log('[Python] Pyodide ready — Python ' + pyodide.version);
            return pyodide;
        } catch (e) {
            console.log('[Python] Failed to load Pyodide: ' + e.message);
            loading = null;
            throw e;
        }
    })();

    return loading;
}

/**
 * Run Python code.
 * @param {string} code
 * @returns {Promise<{output: string, error: string|null, result: string|null}>}
 */
async function run(code) {
    try {
        const py = await ensureLoaded();
        outputBuffer = '';
        const result = py.runPython(code);
        return {
            output: outputBuffer.trimEnd(),
            error: null,
            result: result !== undefined && result !== null ? String(result) : null,
        };
    } catch (e) {
        return {
            output: outputBuffer.trimEnd(),
            error: e.message,
            result: null,
        };
    }
}

/**
 * Install a Python package from PyPI (via micropip).
 * @param {string} pkg — package name
 */
async function installPackage(pkg) {
    const py = await ensureLoaded();
    await py.loadPackage('micropip');
    const micropip = py.pyimport('micropip');
    await micropip.install(pkg);
    return { success: true, package: pkg };
}

/**
 * Check if Pyodide is loaded.
 */
function isLoaded() { return !!pyodide; }

module.exports = { run, ensureLoaded, installPackage, isLoaded };
