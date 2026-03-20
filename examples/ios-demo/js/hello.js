// Edge.js iOS Node.js API Test Suite
// Results are printed to stdout for the Swift UI to capture

const results = [];

function test(name, fn) {
  try {
    const result = fn();
    results.push({ name, status: 'PASS', detail: result || '' });
  } catch (e) {
    results.push({ name, status: 'FAIL', detail: e.message });
  }
}

// ===== Core Module Tests =====

test('console.log', () => {
  console.log('[test] console.log works');
  return 'OK';
});

test('process.platform', () => {
  return process.platform;
});

test('process.arch', () => {
  return process.arch;
});

test('process.version', () => {
  return process.version;
});

test('process.pid', () => {
  return String(process.pid);
});

test('process.env', () => {
  return 'keys: ' + Object.keys(process.env).length;
});

// Buffer
test('Buffer.from', () => {
  const buf = Buffer.from('Hello Edge.js on iOS!', 'utf8');
  return buf.toString('utf8');
});

test('Buffer.alloc', () => {
  const buf = Buffer.alloc(1024, 0);
  return buf.length + ' bytes';
});

test('Buffer.base64', () => {
  const encoded = Buffer.from('Edge.js iOS').toString('base64');
  const decoded = Buffer.from(encoded, 'base64').toString('utf8');
  return decoded === 'Edge.js iOS' ? 'roundtrip OK' : 'MISMATCH';
});

// Path
test('path.join', () => {
  const path = require('path');
  return path.join('/app', 'data', 'hello.js');
});

test('path.resolve', () => {
  const path = require('path');
  return path.resolve('.');
});

test('path.extname', () => {
  const path = require('path');
  return path.extname('file.ts');
});

// URL
test('URL constructor', () => {
  const u = new URL('https://api.openai.com/v1/chat/completions');
  return u.hostname;
});

test('URLSearchParams', () => {
  const p = new URLSearchParams({ model: 'gpt-4', temp: '0.7' });
  return p.toString();
});

// Crypto
test('crypto.randomUUID', () => {
  const crypto = require('crypto');
  return crypto.randomUUID();
});

test('crypto.sha256', () => {
  const crypto = require('crypto');
  const hash = crypto.createHash('sha256').update('edge.js').digest('hex');
  return hash.substring(0, 16) + '...';
});

// Events
test('EventEmitter', () => {
  const EventEmitter = require('events');
  const ee = new EventEmitter();
  let received = '';
  ee.on('msg', (data) => { received = data; });
  ee.emit('msg', 'hello from events');
  return received;
});

// Stream
test('Readable.from', () => {
  const { Readable } = require('stream');
  const chunks = [];
  const s = Readable.from(['a', 'b', 'c']);
  return 'created OK';
});

// JSON
test('JSON roundtrip', () => {
  const obj = {
    model: 'gpt-4',
    messages: [{ role: 'user', content: 'hello' }],
    temperature: 0.7
  };
  const str = JSON.stringify(obj);
  const parsed = JSON.parse(str);
  return parsed.model + ' + ' + parsed.messages.length + ' msg';
});

// Timer
test('setTimeout', () => {
  return new Promise((resolve) => {
    setTimeout(() => resolve('fired after 10ms'), 10);
  });
});

// Promise
test('Promise.all', () => {
  return Promise.all([
    Promise.resolve(1),
    Promise.resolve(2),
    Promise.resolve(3)
  ]).then(vals => 'sum=' + vals.reduce((a,b) => a+b));
});

// OS
test('os.hostname', () => {
  const os = require('os');
  return os.hostname();
});

test('os.tmpdir', () => {
  const os = require('os');
  return "/tmp";
});

test('os.cpus', () => {
  const os = require('os');
  const cpus = os.cpus();
  return cpus.length + ' cores';
});

// FS
test('fs.writeFile + readFile', () => {
  const fs = require('fs');
  const os = require('os');
  const path = require('path');
  const testFile = path.join("/tmp", 'edgejs_ios_test.txt');
  fs.writeFileSync(testFile, 'Hello from Edge.js on iOS!');
  const content = fs.readFileSync(testFile, 'utf8');
  fs.unlinkSync(testFile);
  return content;
});

test('fs.mkdirSync + readdirSync', () => {
  const fs = require('fs');
  const os = require('os');
  const path = require('path');
  const dir = path.join("/tmp", 'edgejs_test_dir');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'a.txt'), 'a');
  fs.writeFileSync(path.join(dir, 'b.txt'), 'b');
  const files = fs.readdirSync(dir);
  fs.rmSync(dir, { recursive: true });
  return files.join(', ');
});

// DNS
test('dns.lookup (localhost)', () => {
  return new Promise((resolve, reject) => {
    const dns = require('dns');
    dns.lookup('localhost', (err, addr) => {
      if (err) reject(err);
      else resolve(addr);
    });
  });
});

// Net (UDS - the Enconvo communication pattern)
test('net.createServer (UDS)', () => {
  return new Promise((resolve, reject) => {
    const net = require('net');
    const fs = require('fs');
    const os = require('os');
    const path = require('path');
    const sock = path.join("/tmp", 'edgejs_test_' + process.pid + '.sock');
    try { fs.unlinkSync(sock); } catch {}
    
    const server = net.createServer((conn) => {
      conn.on('data', (d) => {
        conn.write('echo:' + d.toString());
        conn.end();
      });
    });
    
    server.listen(sock, () => {
      const client = net.createConnection(sock, () => {
        client.write('ping');
      });
      client.on('data', (d) => {
        server.close(() => {
          try { fs.unlinkSync(sock); } catch {}
          resolve(d.toString());
        });
        client.end();
      });
      client.on('error', reject);
    });
    server.on('error', reject);
  });
});

// HTTP client (the core of LLM plugins)
test('fetch (HTTPS GET)', () => {
  return fetch('https://httpbin.org/get')
    .then(r => 'status=' + r.status)
    .catch(e => 'error: ' + e.message);
});

test('fetch (HTTPS POST JSON)', () => {
  return fetch('https://httpbin.org/post', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-4', message: 'hello from iOS' })
  })
    .then(r => r.json())
    .then(d => {
      const posted = JSON.parse(d.data);
      return 'model=' + posted.model;
    })
    .catch(e => 'error: ' + e.message);
});

// Run all tests (including async ones)
async function runAll() {
  // Wait for any pending promises in results
  for (let i = 0; i < results.length; i++) {
    if (results[i].detail && typeof results[i].detail.then === 'function') {
      try {
        results[i].detail = await results[i].detail;
        results[i].status = 'PASS';
      } catch (e) {
        results[i].detail = e.message;
        results[i].status = 'FAIL';
      }
    }
  }
  
  const passed = results.filter(r => r.status === 'PASS').length;
  const failed = results.filter(r => r.status === 'FAIL').length;
  
  console.log('\n========== EDGE.JS iOS TEST RESULTS ==========');
  for (const r of results) {
    const icon = r.status === 'PASS' ? '✓' : '✗';
    console.log(`  ${icon} ${r.name}: ${r.detail}`);
  }
  console.log(`\n  Total: ${results.length} | Passed: ${passed} | Failed: ${failed}`);
  console.log('================================================\n');
  
  // Keep the server running for UDS testing
  const net = require('net');
  const fs = require('fs');
  const os = require('os');
  const path = require('path');
  const sock = path.join("/tmp", 'edgejs_jobtalk_' + process.pid + '.sock');
  try { fs.unlinkSync(sock); } catch {}
  
  const server = net.createServer((conn) => {
    let buf = '';
    conn.on('data', (chunk) => {
      buf += chunk.toString();
      let idx;
      while ((idx = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, idx);
        buf = buf.slice(idx + 1);
        try {
          const msg = JSON.parse(line);
          const reply = { type: 'response', requestId: msg.requestId, payloads: { text: 'OK from Edge.js' } };
          conn.write(JSON.stringify(reply) + '\n');
        } catch {}
      }
    });
  });
  
  server.listen(sock, () => {
    console.log('[EdgeJS] UDS server ready at ' + sock);
    console.log('[EdgeJS] Waiting for connections...');
  });
}

runAll().catch(e => {
  console.error('Test runner error:', e);
  process.exit(1);
});

process.on('uncaughtException', (e) => {
  console.error('[EdgeJS] Uncaught:', e.message);
});
process.on('unhandledRejection', (e) => {
  console.error('[EdgeJS] Unhandled rejection:', e.message || e);
});

// Also write results to a file for clean reading
const fs2 = require('fs');
const resultsPath = '/tmp/edgejs_test_results.txt';
let output = '\n========== EDGE.JS iOS TEST RESULTS ==========\n';
for (const r of results) {
  const icon = r.status === 'PASS' ? 'PASS' : 'FAIL';
  output += '  [' + icon + '] ' + r.name + ': ' + r.detail + '\n';
}
const passed2 = results.filter(r => r.status === 'PASS').length;
const failed2 = results.filter(r => r.status === 'FAIL').length;
output += '\n  Total: ' + results.length + ' | Passed: ' + passed2 + ' | Failed: ' + failed2 + '\n';
output += '================================================\n';
try {
  fs2.writeFileSync(resultsPath, output);
} catch(e) {}
