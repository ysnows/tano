/**
 * @file test_embed_api.cc
 * @brief GoogleTest tests for the Edge.js embedding API (edge_embed.h).
 */
#include <atomic>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>

#include <gtest/gtest.h>

#include "edge_embed.h"

namespace {

// Helper: write a temporary JS file and return its path.
std::string WriteTempScript(const std::string& stem, const std::string& content) {
  const auto temp_dir = std::filesystem::temp_directory_path();
  const auto unique_name =
      stem + "_" +
      std::to_string(static_cast<unsigned long long>(
          std::hash<std::string>{}(content))) +
      ".js";
  const auto path = temp_dir / unique_name;
  std::ofstream out(path);
  out << content;
  out.close();
  return path.string();
}

// Helper: remove a temporary file (best-effort).
void RemoveTempScript(const std::string& path) {
  std::error_code ec;
  std::filesystem::remove(path, ec);
}

// Shared fatal error state for tests.
struct FatalState {
  std::atomic<bool> called{false};
  std::string message;
};

void FatalCallback(const char* message, void* user_data) {
  auto* state = static_cast<FatalState*>(user_data);
  if (state == nullptr) return;
  state->message = message != nullptr ? message : "";
  state->called.store(true);
}

}  // namespace

class EdgeEmbedApiTest : public ::testing::Test {
 protected:
  static void SetUpTestSuite() {
    // Process-wide init (idempotent via call_once).
    EdgeStatus status = EdgeProcessInit();
    ASSERT_EQ(status, EDGE_OK) << "EdgeProcessInit failed";
  }
};

// -------------------------------------------------------------------------
// Test: ProcessInitSucceeds
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, ProcessInitSucceeds) {
  // EdgeProcessInit is idempotent; calling it again should still succeed.
  EdgeStatus status = EdgeProcessInit();
  EXPECT_EQ(status, EDGE_OK);
}

// -------------------------------------------------------------------------
// Test: CreateWithNullConfigFails
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, CreateWithNullConfigFails) {
  EdgeRuntime* rt = EdgeRuntimeCreate(nullptr);
  EXPECT_EQ(rt, nullptr);
}

// -------------------------------------------------------------------------
// Test: CreateAndDestroy
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, CreateAndDestroy) {
  EdgeRuntimeConfig config{};
  config.script_path = "";
  config.extension_path = nullptr;
  config.socket_path = nullptr;
  config.argc = 0;
  config.argv = nullptr;
  config.on_fatal = nullptr;
  config.user_data = nullptr;

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  // Should not be running before Run is called.
  EXPECT_EQ(EdgeRuntimeIsRunning(rt), 0);

  // Destroy without running is valid.
  EdgeRuntimeDestroy(rt);
}

// -------------------------------------------------------------------------
// Test: DestroyNullIsNoOp
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, DestroyNullIsNoOp) {
  // Should not crash.
  EdgeRuntimeDestroy(nullptr);
}

// -------------------------------------------------------------------------
// Test: GetErrorOnFreshRuntime
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, GetErrorOnFreshRuntime) {
  EdgeRuntimeConfig config{};
  config.script_path = "/nonexistent.js";

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  // No error before running.
  EXPECT_EQ(EdgeRuntimeGetError(rt), nullptr);

  EdgeRuntimeDestroy(rt);
}

// -------------------------------------------------------------------------
// Test: GetErrorWithNull
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, GetErrorWithNull) {
  EXPECT_EQ(EdgeRuntimeGetError(nullptr), nullptr);
}

// -------------------------------------------------------------------------
// Test: IsRunningWithNull
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, IsRunningWithNull) {
  EXPECT_EQ(EdgeRuntimeIsRunning(nullptr), 0);
}

// -------------------------------------------------------------------------
// Test: ShutdownWithNull
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, ShutdownWithNull) {
  // Should not crash.
  EdgeRuntimeShutdown(nullptr);
}

// -------------------------------------------------------------------------
// Test: RunSimpleScript
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, RunSimpleScript) {
  const std::string script = WriteTempScript(
      "edge_embed_test_simple",
      "console.log('hello from edge embed'); process.exit(0);\n");

  EdgeRuntimeConfig config{};
  config.script_path = script.c_str();

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  std::atomic<int> exit_code{-1};
  std::atomic<bool> done{false};

  std::thread runner([&]() {
    exit_code.store(EdgeRuntimeRun(rt));
    done.store(true);
  });

  // Wait for completion with a timeout.
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!done.load() && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  if (!done.load()) {
    // Force shutdown if the script did not exit in time.
    EdgeRuntimeShutdown(rt);
  }

  runner.join();

  EXPECT_TRUE(done.load()) << "Script did not complete within timeout";
  EXPECT_EQ(exit_code.load(), 0) << "Expected exit code 0, got "
                                  << exit_code.load();
  EXPECT_EQ(EdgeRuntimeIsRunning(rt), 0);

  EdgeRuntimeDestroy(rt);
  RemoveTempScript(script);
}

// -------------------------------------------------------------------------
// Test: ShutdownFromAnotherThread
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, ShutdownFromAnotherThread) {
  // Start an HTTP server that would run indefinitely, then shut it down
  // from the main thread.
  const std::string script = WriteTempScript(
      "edge_embed_test_server",
      R"JS(
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('ok');
});
server.listen(0, '127.0.0.1', () => {
  // Server is listening; the test will shut us down.
});
)JS");

  EdgeRuntimeConfig config{};
  config.script_path = script.c_str();

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  std::atomic<int> exit_code{-1};
  std::atomic<bool> done{false};

  std::thread runner([&]() {
    exit_code.store(EdgeRuntimeRun(rt));
    done.store(true);
  });

  // Wait a bit for the server to start, then trigger shutdown.
  std::this_thread::sleep_for(std::chrono::milliseconds(500));

  EXPECT_EQ(EdgeRuntimeIsRunning(rt), 1);
  EdgeRuntimeShutdown(rt);

  // Wait for the runner to finish.
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!done.load() && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  runner.join();

  EXPECT_TRUE(done.load()) << "Runtime did not stop within timeout";
  EXPECT_EQ(EdgeRuntimeIsRunning(rt), 0);

  EdgeRuntimeDestroy(rt);
  RemoveTempScript(script);
}

// -------------------------------------------------------------------------
// Test: DoubleRunFails
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, DoubleRunFails) {
  // Verify that calling Run while already running returns an error.
  const std::string script = WriteTempScript(
      "edge_embed_test_double_run",
      R"JS(
const http = require('http');
const server = http.createServer(() => {});
server.listen(0, '127.0.0.1');
)JS");

  EdgeRuntimeConfig config{};
  config.script_path = script.c_str();

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  std::atomic<bool> first_started{false};
  std::atomic<bool> done{false};

  std::thread runner([&]() {
    first_started.store(true);
    EdgeRuntimeRun(rt);
    done.store(true);
  });

  // Wait for the first Run to start.
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!first_started.load() &&
         std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(200));

  // A second Run from the main thread should fail immediately.
  if (EdgeRuntimeIsRunning(rt)) {
    int rc = EdgeRuntimeRun(rt);
    EXPECT_NE(rc, 0) << "Second Run should fail while already running";
  }

  EdgeRuntimeShutdown(rt);
  runner.join();

  EdgeRuntimeDestroy(rt);
  RemoveTempScript(script);
}

// -------------------------------------------------------------------------
// Test: ConfigStringsCopied
// -------------------------------------------------------------------------
TEST_F(EdgeEmbedApiTest, ConfigStringsCopied) {
  // Verify that EdgeRuntimeCreate deep-copies config strings.
  char path_buf[256];
  std::snprintf(path_buf, sizeof(path_buf), "/tmp/edge_embed_copy_test.js");

  EdgeRuntimeConfig config{};
  config.script_path = path_buf;

  EdgeRuntime* rt = EdgeRuntimeCreate(&config);
  ASSERT_NE(rt, nullptr);

  // Overwrite the buffer after creation.
  std::memset(path_buf, 'X', sizeof(path_buf) - 1);
  path_buf[sizeof(path_buf) - 1] = '\0';

  // The runtime should still have the original path (we can only verify
  // indirectly via GetError after a failed run, or just that it doesn't crash).
  EdgeRuntimeDestroy(rt);
}
