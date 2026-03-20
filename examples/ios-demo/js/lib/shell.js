/**
 * iOS Shell — Termux-like command interpreter for EdgeJS
 *
 * Since iOS forbids fork()/exec(), all commands are implemented
 * in pure JavaScript using Node.js fs/path/os APIs.
 *
 * Supported commands:
 *   ls [-la] [path]        — list directory
 *   cd [path]              — change directory
 *   pwd                    — print working directory
 *   cat <file>             — read file
 *   head [-n N] <file>     — first N lines
 *   tail [-n N] <file>     — last N lines
 *   mkdir [-p] <path>      — create directory
 *   rm [-rf] <path>        — remove file/directory
 *   cp <src> <dst>         — copy file
 *   mv <src> <dst>         — move/rename
 *   touch <file>           — create empty file
 *   echo <text>            — print text
 *   env                    — show environment variables
 *   export KEY=VALUE       — set environment variable
 *   which <cmd>            — check if command exists
 *   whoami                 — current user
 *   uname [-a]             — system info
 *   date                   — current date/time
 *   du [-sh] [path]        — disk usage
 *   find <path> -name <pattern> — find files
 *   grep <pattern> <file>  — search in file
 *   wc [-l] <file>         — word/line count
 *   chmod <mode> <file>    — change permissions
 *   stat <file>            — file info
 *   curl <url>             — HTTP GET
 *   node -e <code>         — evaluate JavaScript
 *   clear                  — clear screen
 *   help                   — show available commands
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');

let cwd = process.env.HOME || os.tmpdir();

function parseArgs(input) {
    // Simple argument parser that handles quotes
    const args = [];
    let current = '';
    let inQuote = false;
    let quoteChar = '';
    for (const ch of input) {
        if (inQuote) {
            if (ch === quoteChar) { inQuote = false; }
            else { current += ch; }
        } else if (ch === '"' || ch === "'") {
            inQuote = true;
            quoteChar = ch;
        } else if (ch === ' ' || ch === '\t') {
            if (current) { args.push(current); current = ''; }
        } else {
            current += ch;
        }
    }
    if (current) args.push(current);
    return args;
}

function resolvePath(p) {
    if (!p) return cwd;
    if (p.startsWith('~')) p = path.join(os.homedir(), p.slice(1));
    if (!path.isAbsolute(p)) p = path.join(cwd, p);
    return path.resolve(p);
}

function formatSize(bytes) {
    if (bytes < 1024) return bytes + 'B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + 'K';
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + 'M';
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + 'G';
}

function formatMode(mode) {
    const types = { 0o140000: 's', 0o120000: 'l', 0o100000: '-', 0o040000: 'd', 0o060000: 'b', 0o020000: 'c', 0o010000: 'p' };
    let type = '-';
    for (const [mask, ch] of Object.entries(types)) {
        if ((mode & 0o170000) === Number(mask)) { type = ch; break; }
    }
    const perms = ['---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx'];
    return type + perms[(mode >> 6) & 7] + perms[(mode >> 3) & 7] + perms[mode & 7];
}

const commands = {
    ls(args) {
        const longFormat = args.includes('-l') || args.includes('-la') || args.includes('-al');
        const showHidden = args.includes('-a') || args.includes('-la') || args.includes('-al');
        const target = resolvePath(args.filter(a => !a.startsWith('-'))[0]);

        try {
            let entries = fs.readdirSync(target);
            if (!showHidden) entries = entries.filter(e => !e.startsWith('.'));
            entries.sort();

            if (!longFormat) return entries.join('  ');

            const lines = entries.map(name => {
                try {
                    const stat = fs.statSync(path.join(target, name));
                    const mode = formatMode(stat.mode);
                    const size = formatSize(stat.size).padStart(8);
                    const date = stat.mtime.toISOString().substring(0, 16).replace('T', ' ');
                    return `${mode} ${size} ${date} ${name}`;
                } catch (e) {
                    return `?????????? ${name}`;
                }
            });
            return lines.join('\n');
        } catch (e) {
            return `ls: ${e.message}`;
        }
    },

    cd(args) {
        const target = resolvePath(args[0] || os.homedir());
        try {
            const stat = fs.statSync(target);
            if (!stat.isDirectory()) return `cd: not a directory: ${target}`;
            cwd = target;
            return '';
        } catch (e) {
            return `cd: ${e.message}`;
        }
    },

    pwd() { return cwd; },

    cat(args) {
        const file = resolvePath(args[0]);
        try { return fs.readFileSync(file, 'utf8'); }
        catch (e) { return `cat: ${e.message}`; }
    },

    head(args) {
        let n = 10;
        const filtered = [];
        for (let i = 0; i < args.length; i++) {
            if (args[i] === '-n' && args[i + 1]) { n = parseInt(args[++i]); }
            else if (!args[i].startsWith('-')) { filtered.push(args[i]); }
        }
        const file = resolvePath(filtered[0]);
        try {
            const lines = fs.readFileSync(file, 'utf8').split('\n');
            return lines.slice(0, n).join('\n');
        } catch (e) { return `head: ${e.message}`; }
    },

    tail(args) {
        let n = 10;
        const filtered = [];
        for (let i = 0; i < args.length; i++) {
            if (args[i] === '-n' && args[i + 1]) { n = parseInt(args[++i]); }
            else if (!args[i].startsWith('-')) { filtered.push(args[i]); }
        }
        const file = resolvePath(filtered[0]);
        try {
            const lines = fs.readFileSync(file, 'utf8').split('\n');
            return lines.slice(-n).join('\n');
        } catch (e) { return `tail: ${e.message}`; }
    },

    mkdir(args) {
        const recursive = args.includes('-p');
        const target = resolvePath(args.filter(a => !a.startsWith('-'))[0]);
        try {
            if (recursive) {
                // Manual recursive mkdir for JSC
                const parts = target.split(path.sep);
                let cur = '';
                for (const p of parts) {
                    cur = cur ? path.join(cur, p) : (p || path.sep);
                    if (!fs.existsSync(cur)) fs.mkdirSync(cur);
                }
            } else {
                fs.mkdirSync(target);
            }
            return '';
        } catch (e) { return `mkdir: ${e.message}`; }
    },

    rm(args) {
        const recursive = args.includes('-r') || args.includes('-rf') || args.includes('-fr');
        const force = args.includes('-f') || args.includes('-rf') || args.includes('-fr');
        const target = resolvePath(args.filter(a => !a.startsWith('-'))[0]);
        try {
            const stat = fs.statSync(target);
            if (stat.isDirectory()) {
                if (!recursive) return `rm: ${target}: is a directory`;
                fs.rmSync(target, { recursive: true, force: true });
            } else {
                fs.unlinkSync(target);
            }
            return '';
        } catch (e) {
            if (force) return '';
            return `rm: ${e.message}`;
        }
    },

    cp(args) {
        const src = resolvePath(args[0]);
        const dst = resolvePath(args[1]);
        try { fs.copyFileSync(src, dst); return ''; }
        catch (e) { return `cp: ${e.message}`; }
    },

    mv(args) {
        const src = resolvePath(args[0]);
        const dst = resolvePath(args[1]);
        try { fs.renameSync(src, dst); return ''; }
        catch (e) { return `mv: ${e.message}`; }
    },

    touch(args) {
        const file = resolvePath(args[0]);
        try {
            if (fs.existsSync(file)) {
                const now = new Date();
                fs.utimesSync(file, now, now);
            } else {
                fs.writeFileSync(file, '');
            }
            return '';
        } catch (e) { return `touch: ${e.message}`; }
    },

    echo(args) { return args.join(' '); },

    env() {
        return Object.entries(process.env)
            .map(([k, v]) => `${k}=${v}`)
            .sort()
            .join('\n');
    },

    export(args) {
        const match = args.join(' ').match(/^(\w+)=(.*)$/);
        if (match) {
            process.env[match[1]] = match[2];
            return '';
        }
        return 'export: usage: export KEY=VALUE';
    },

    which(args) {
        const cmd = args[0];
        if (commands[cmd]) return `${cmd}: built-in shell command`;
        return `${cmd}: not found`;
    },

    whoami() {
        return os.userInfo().username || process.env.USER || 'mobile';
    },

    uname(args) {
        if (args.includes('-a')) {
            return `${os.type()} ${os.hostname()} ${os.release()} ${os.arch()} ${os.platform()}`;
        }
        return os.type();
    },

    date() { return new Date().toString(); },

    du(args) {
        const target = resolvePath(args.filter(a => !a.startsWith('-'))[0] || '.');
        function dirSize(p) {
            let total = 0;
            try {
                const stat = fs.statSync(p);
                if (stat.isFile()) return stat.size;
                if (stat.isDirectory()) {
                    for (const f of fs.readdirSync(p)) {
                        total += dirSize(path.join(p, f));
                    }
                }
            } catch (e) {}
            return total;
        }
        return formatSize(dirSize(target)) + '\t' + target;
    },

    find(args) {
        let searchPath = '.';
        let namePattern = '*';
        for (let i = 0; i < args.length; i++) {
            if (args[i] === '-name' && args[i + 1]) { namePattern = args[++i]; }
            else if (!args[i].startsWith('-')) { searchPath = args[i]; }
        }
        const root = resolvePath(searchPath);
        const regex = new RegExp('^' + namePattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
        const results = [];
        function walk(dir) {
            try {
                for (const f of fs.readdirSync(dir)) {
                    const full = path.join(dir, f);
                    if (regex.test(f)) results.push(full);
                    try { if (fs.statSync(full).isDirectory()) walk(full); } catch (e) {}
                }
            } catch (e) {}
        }
        walk(root);
        return results.join('\n') || 'No matches found';
    },

    grep(args) {
        const pattern = args[0];
        const file = resolvePath(args[1]);
        if (!pattern || !args[1]) return 'grep: usage: grep <pattern> <file>';
        try {
            const regex = new RegExp(pattern, 'gi');
            const lines = fs.readFileSync(file, 'utf8').split('\n');
            const matches = lines.filter(l => regex.test(l));
            return matches.join('\n') || 'No matches';
        } catch (e) { return `grep: ${e.message}`; }
    },

    wc(args) {
        const file = resolvePath(args.filter(a => !a.startsWith('-'))[0]);
        try {
            const content = fs.readFileSync(file, 'utf8');
            const lines = content.split('\n').length;
            const words = content.split(/\s+/).filter(Boolean).length;
            const chars = content.length;
            if (args.includes('-l')) return `${lines}`;
            return `  ${lines}  ${words}  ${chars} ${path.basename(file)}`;
        } catch (e) { return `wc: ${e.message}`; }
    },

    chmod(args) {
        const mode = parseInt(args[0], 8);
        const file = resolvePath(args[1]);
        try { fs.chmodSync(file, mode); return ''; }
        catch (e) { return `chmod: ${e.message}`; }
    },

    stat(args) {
        const file = resolvePath(args[0]);
        try {
            const s = fs.statSync(file);
            return [
                `  File: ${file}`,
                `  Size: ${s.size}\tType: ${s.isDirectory() ? 'directory' : 'file'}`,
                `  Mode: ${formatMode(s.mode)} (${(s.mode & 0o777).toString(8)})`,
                `  Uid: ${s.uid}\tGid: ${s.gid}`,
                `Access: ${s.atime.toISOString()}`,
                `Modify: ${s.mtime.toISOString()}`,
                `Change: ${s.ctime.toISOString()}`,
            ].join('\n');
        } catch (e) { return `stat: ${e.message}`; }
    },

    async curl(args) {
        const url = args[0];
        if (!url) return 'curl: usage: curl <url>';
        return new Promise((resolve) => {
            const mod = url.startsWith('https') ? https : http;
            mod.get(url, { headers: { 'User-Agent': 'EdgeJS-iOS/1.0' } }, (res) => {
                let data = '';
                res.on('data', c => data += c);
                res.on('end', () => resolve(data.substring(0, 2000)));
            }).on('error', e => resolve(`curl: ${e.message}`));
        });
    },

    node(args) {
        if (args[0] === '-e' && args.length > 1) {
            const code = args.slice(1).join(' ');
            try {
                const result = eval(code);
                return result !== undefined ? String(result) : '';
            } catch (e) { return `Error: ${e.message}`; }
        }
        return 'node: usage: node -e "<code>"';
    },

    async python(args) {
        const pythonRunner = require('./python-runner');
        if (args[0] === '-c' && args.length > 1) {
            const code = args.slice(1).join(' ');
            const result = await pythonRunner.run(code);
            if (result.error) return `Python Error: ${result.error}`;
            return result.output || result.result || '';
        }
        if (args[0] && !args[0].startsWith('-')) {
            // Run a .py file
            const file = resolvePath(args[0]);
            try {
                const code = fs.readFileSync(file, 'utf8');
                const result = await pythonRunner.run(code);
                if (result.error) return `Python Error: ${result.error}`;
                return result.output || result.result || '';
            } catch (e) { return `python: ${e.message}`; }
        }
        return 'python: usage: python -c "code" | python <file.py>';
    },

    async pip(args) {
        const pythonRunner = require('./python-runner');
        if (args[0] === 'install' && args[1]) {
            try {
                const result = await pythonRunner.installPackage(args[1]);
                return `Successfully installed ${result.package}`;
            } catch (e) { return `pip: ${e.message}`; }
        }
        return 'pip: usage: pip install <package>';
    },

    clear() { return '\x1B[clear]'; },

    help() {
        return [
            'iOS Shell — Built-in commands:',
            '',
            'File System:  ls cd pwd cat head tail mkdir rm cp mv touch chmod stat',
            'Search:       find grep wc',
            'System:       env export whoami uname date du which',
            'Network:      curl',
            'Python:       python -c "code" | python <file.py> | pip install <pkg>',
            'JavaScript:   node -e "<code>"',
            'Other:        echo clear help',
            '',
            'Note: iOS does not allow spawning child processes.',
            'All commands are implemented in pure JavaScript.',
        ].join('\n');
    },
};

/**
 * Execute a shell command string.
 * @param {string} input — the command line
 * @returns {Promise<string>} — output text
 */
async function execute(input) {
    const trimmed = input.trim();
    if (!trimmed) return '';

    // Handle pipes (simple single pipe)
    if (trimmed.includes(' | ')) {
        const parts = trimmed.split(' | ');
        let output = '';
        for (const part of parts) {
            // Feed previous output as stdin to grep/wc/head/tail
            const args = parseArgs(part.trim());
            const cmd = args.shift();
            if (commands[cmd]) {
                if (output && (cmd === 'grep' || cmd === 'wc' || cmd === 'head' || cmd === 'tail')) {
                    // Write output to temp file and pass it
                    const tmp = path.join(os.tmpdir(), '.pipe_tmp');
                    fs.writeFileSync(tmp, output);
                    args.push(tmp);
                }
                const result = commands[cmd](args);
                output = result instanceof Promise ? await result : result;
            } else {
                return `${cmd}: command not found`;
            }
        }
        return output;
    }

    const args = parseArgs(trimmed);
    const cmd = args.shift();

    if (!commands[cmd]) {
        return `${cmd}: command not found. Type 'help' for available commands.`;
    }

    const result = commands[cmd](args);
    return result instanceof Promise ? await result : result;
}

/**
 * Get the current working directory.
 */
function getCwd() { return cwd; }

module.exports = { execute, getCwd, commands };
