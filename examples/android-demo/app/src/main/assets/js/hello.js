/**
 * hello.js - Edge.js iOS/Android demo entry script.
 *
 * Starts a Unix domain socket echo server that speaks the JobTalk protocol
 * (newline-delimited JSON). Useful for verifying that the Edge.js runtime is
 * alive and that IPC works from the host app.
 */

const net = require("net");
const path = require("path");
const os = require("os");

// Socket path: use the first command-line argument, or fall back to a temp path.
const socketPath =
  process.argv[2] ||
  path.join(os.tmpdir(), "edgejs-demo-" + process.pid + ".sock");

// Clean up stale socket file.
try {
  require("fs").unlinkSync(socketPath);
} catch (_) {
  // ignore
}

const server = net.createServer((conn) => {
  console.log("[hello.js] Client connected.");

  let buffer = "";

  conn.on("data", (chunk) => {
    buffer += chunk.toString();

    // Process newline-delimited messages.
    let idx;
    while ((idx = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 1);

      let msg;
      try {
        msg = JSON.parse(line);
      } catch (e) {
        console.error("[hello.js] Invalid JSON:", line);
        continue;
      }

      console.log("[hello.js] Received:", JSON.stringify(msg));

      // Echo back with type "response".
      const reply = {
        type: "response",
        method: msg.method || "echo",
        requestId: msg.requestId || null,
        payloads: msg.payloads || {},
      };

      conn.write(JSON.stringify(reply) + "\n");
    }
  });

  conn.on("end", () => {
    console.log("[hello.js] Client disconnected.");
  });

  conn.on("error", (err) => {
    console.error("[hello.js] Connection error:", err.message);
  });
});

server.listen(socketPath, () => {
  console.log("[hello.js] Echo server listening on", socketPath);
});

// Graceful shutdown.
process.on("SIGTERM", () => {
  console.log("[hello.js] SIGTERM received, shutting down.");
  server.close();
});

process.on("SIGINT", () => {
  console.log("[hello.js] SIGINT received, shutting down.");
  server.close();
});
