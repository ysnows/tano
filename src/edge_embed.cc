/**
 * @file edge_embed.cc
 * @brief Implementation of the Edge.js embedding API for mobile platforms.
 *
 * This file implements the public C API declared in edge_embed.h. It follows
 * the RunWithFreshEnv() pattern from edge_cli.cc but adapts it for embedder
 * use:
 *   - No signal handler installation (host app owns signals).
 *   - Thread-safe shutdown via uv_async_send().
 *   - Process exit interception via SetProcessExitHandler() so that
 *     process.exit() triggers graceful shutdown rather than ::exit().
 */
#include "edge_embed.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>

#include <uv.h>

#include "unofficial_napi.h"
#include "edge_environment.h"
#include "edge_environment_runtime.h"
#include "edge_env_loop.h"
#include "edge_runtime.h"
#include "edge_runtime_platform.h"

namespace {

std::once_flag g_embed_init_once;
bool g_embed_init_ok = false;

}  // namespace

/**
 * Internal representation of an EdgeRuntime handle.
 *
 * All mutable fields are either protected by atomics or only accessed from the
 * thread that calls EdgeRuntimeRun(). The shutdown_handle is the sole
 * cross-thread communication channel.
 */
struct EdgeRuntime {
  // Configuration (owned copies).
  std::string script_path;
  std::string extension_path;
  std::string socket_path;
  int argc = 0;
  char** argv_owned = nullptr;
  EdgeFatalErrorCallback on_fatal = nullptr;
  void* user_data = nullptr;

  // Runtime state.
  std::atomic<bool> running{false};
  std::atomic<bool> shutdown_requested{false};
  int exit_code = 0;
  std::string last_error;

  // Event loop shutdown handle (initialized during Run).
  uv_async_t shutdown_handle{};
  bool shutdown_handle_initialized = false;

  // N-API env (valid only during Run).
  napi_env env = nullptr;

  ~EdgeRuntime() {
    if (argv_owned != nullptr) {
      for (int i = 0; i < argc; ++i) {
        delete[] argv_owned[i];
      }
      delete[] argv_owned;
      argv_owned = nullptr;
    }
  }
};

// ---------------------------------------------------------------------------
// Shutdown handle callbacks
// ---------------------------------------------------------------------------

namespace {

void OnShutdownSignal(uv_async_t* handle) {
  auto* runtime = static_cast<EdgeRuntime*>(handle->data);
  if (runtime == nullptr) return;

  // Use Environment::Exit() to set the exiting_ flag — this is what
  // RunEventLoopUntilQuiescent checks (via IsEnvironmentExitRequested →
  // environment->exiting()) to break out of its re-entry loop.
  // Without this, uv_stop alone is insufficient because the runtime
  // re-enters uv_run after each iteration.
  if (runtime->env != nullptr) {
    auto* edge_env = edge::Environment::Get(runtime->env);
    if (edge_env != nullptr) {
      edge_env->Exit(0);
    }
  }

  // Stop the event loop so the current uv_run returns immediately.
  uv_stop(handle->loop);
}

void OnShutdownHandleClosed(uv_handle_t* handle) {
  // No-op: the handle is embedded in EdgeRuntime and freed in Destroy.
  (void)handle;
}

/**
 * Process exit handler installed on the edge::Environment. When JS calls
 * process.exit(), this handler intercepts it and triggers graceful shutdown
 * instead of calling ::exit() which would kill the host app.
 */
void EmbedProcessExitHandler(edge::Environment* environment, int exit_code) {
  if (environment == nullptr) return;

  napi_env env = environment->env();

  // Capture the exit code from process.exit(N) back to the EdgeRuntime struct
  // so EdgeRuntimeRun() returns the correct value to the host app.
  void* data = nullptr;
  if (napi_get_instance_data(env, &data) == napi_ok && data != nullptr) {
    auto* runtime = static_cast<EdgeRuntime*>(data);
    runtime->exit_code = exit_code;
  }

  // Stop the event loop so EdgeRuntimeRun can unwind.
  if (uv_loop_t* loop = environment->GetExistingEventLoop(); loop != nullptr) {
    uv_stop(loop);
  }

  // Terminate JS execution so we unwind through the cleanup path.
  (void)unofficial_napi_terminate_execution(env);
}

}  // namespace

// ---------------------------------------------------------------------------
// Public API implementation
// ---------------------------------------------------------------------------

EdgeStatus EdgeProcessInit(void) {
  std::call_once(g_embed_init_once, []() {
    // Initialize OpenSSL. We intentionally do NOT call
    // ResetSignalHandlersLikeNode() or register SIGINT/SIGTERM handlers
    // because the host app (iOS/Android) owns signal handling.
    std::string error;
    if (!EdgeInitializeOpenSslForCli(&error)) {
      g_embed_init_ok = false;
      return;
    }
    g_embed_init_ok = true;
  });
  return g_embed_init_ok ? EDGE_OK : EDGE_ERROR_OPENSSL_INIT;
}

EdgeRuntime* EdgeRuntimeCreate(const EdgeRuntimeConfig* config) {
  if (config == nullptr) return nullptr;

  auto* runtime = new (std::nothrow) EdgeRuntime();
  if (runtime == nullptr) return nullptr;

  // Copy all strings so the caller can free the config immediately.
  if (config->script_path != nullptr) {
    runtime->script_path = config->script_path;
  }
  if (config->extension_path != nullptr) {
    runtime->extension_path = config->extension_path;
  }
  if (config->socket_path != nullptr) {
    runtime->socket_path = config->socket_path;
  }

  // Deep-copy argv.
  if (config->argc > 0 && config->argv != nullptr) {
    runtime->argc = config->argc;
    runtime->argv_owned = new (std::nothrow) char*[config->argc];
    if (runtime->argv_owned != nullptr) {
      for (int i = 0; i < config->argc; ++i) {
        if (config->argv[i] != nullptr) {
          const size_t len = std::strlen(config->argv[i]);
          runtime->argv_owned[i] = new (std::nothrow) char[len + 1];
          if (runtime->argv_owned[i] != nullptr) {
            std::memcpy(runtime->argv_owned[i], config->argv[i], len + 1);
          }
        } else {
          runtime->argv_owned[i] = nullptr;
        }
      }
    }
  }

  runtime->on_fatal = config->on_fatal;
  runtime->user_data = config->user_data;

  return runtime;
}

int EdgeRuntimeRun(EdgeRuntime* runtime) {
  if (runtime == nullptr) return 1;

  // Prevent double-run.
  bool expected = false;
  if (!runtime->running.compare_exchange_strong(expected, true)) {
    runtime->last_error = "Runtime is already running";
    return 1;
  }

  runtime->shutdown_requested.store(false);
  runtime->exit_code = 0;
  runtime->last_error.clear();

  // -----------------------------------------------------------------------
  // Step 1: Create the N-API environment (mirrors RunWithFreshEnv).
  // -----------------------------------------------------------------------
  napi_env env = nullptr;
  void* env_scope = nullptr;
  const napi_status create_status =
      unofficial_napi_create_env(8, &env, &env_scope);
  if (create_status != napi_ok || env == nullptr || env_scope == nullptr) {
    runtime->last_error = "Failed to create N-API environment";
    runtime->running.store(false);
    if (runtime->on_fatal != nullptr) {
      runtime->on_fatal(runtime->last_error.c_str(), runtime->user_data);
    }
    return 1;
  }
  runtime->env = env;

  // -----------------------------------------------------------------------
  // Step 2: Attach the Edge environment for runtime operation.
  // -----------------------------------------------------------------------
  if (!EdgeAttachEnvironmentForRuntime(env)) {
    (void)unofficial_napi_release_env(env_scope);
    runtime->env = nullptr;
    runtime->last_error = "Failed to attach runtime environment";
    runtime->running.store(false);
    if (runtime->on_fatal != nullptr) {
      runtime->on_fatal(runtime->last_error.c_str(), runtime->user_data);
    }
    return 1;
  }

  // -----------------------------------------------------------------------
  // Step 3: Install custom process exit handler.
  // -----------------------------------------------------------------------
  // Override the default handler so process.exit() does not call ::exit()
  // which would terminate the host application.
  auto* edge_env = edge::Environment::Get(env);
  if (edge_env != nullptr) {
    edge_env->SetProcessExitHandler(EmbedProcessExitHandler);
  }

  // Store runtime pointer as instance data so the process exit handler
  // can write back the exit code from process.exit(N).
  (void)napi_set_instance_data(env, runtime, nullptr, nullptr);

  // -----------------------------------------------------------------------
  // Step 4: Install runtime platform hooks.
  // -----------------------------------------------------------------------
  if (EdgeRuntimePlatformInstallHooks(env) != napi_ok) {
    EdgeEnvironmentRunCleanup(env);
    EdgeEnvironmentRunAtExitCallbacks(env);
    (void)unofficial_napi_release_env(env_scope);
    runtime->env = nullptr;
    runtime->last_error = "Failed to install runtime platform hooks";
    runtime->running.store(false);
    if (runtime->on_fatal != nullptr) {
      runtime->on_fatal(runtime->last_error.c_str(), runtime->user_data);
    }
    return 1;
  }

  // -----------------------------------------------------------------------
  // Step 5: Initialize the shutdown handle for cross-thread signaling.
  // -----------------------------------------------------------------------
  uv_loop_t* loop = nullptr;
  if (edge_env != nullptr) {
    loop = edge_env->event_loop();
  }
  if (loop == nullptr) {
    loop = EdgeGetEnvLoop(env);
  }

  if (loop != nullptr) {
    runtime->shutdown_handle.data = runtime;
    if (uv_async_init(loop, &runtime->shutdown_handle, OnShutdownSignal) == 0) {
      runtime->shutdown_handle_initialized = true;
      // Unref so the shutdown handle alone does not keep the loop alive.
      uv_unref(reinterpret_cast<uv_handle_t*>(&runtime->shutdown_handle));
    }
  }

  // If shutdown was already requested before we got here, honor it.
  if (runtime->shutdown_requested.load()) {
    if (loop != nullptr) {
      uv_stop(loop);
    }
  }

  // -----------------------------------------------------------------------
  // Step 6: Run the script with the event loop.
  // -----------------------------------------------------------------------
  std::string script_error;
  // Save any exit code set by the process exit handler (from process.exit(N))
  // before EdgeRunScriptFileWithLoop potentially overwrites it.
  const int pre_run_exit_code = runtime->exit_code;
  int script_exit_code = EdgeRunScriptFileWithLoop(
      env,
      runtime->script_path.c_str(),
      &script_error,
      true,   // keep_event_loop_alive
      nullptr // native_main_builtin_id
  );

  // Prefer the exit code from process.exit(N) if the handler captured one,
  // otherwise use the script runner's return value.
  if (runtime->exit_code != pre_run_exit_code) {
    // Handler was invoked and set a specific exit code — keep it.
  } else {
    runtime->exit_code = script_exit_code;
  }

  if (!script_error.empty()) {
    runtime->last_error = script_error;
  }

  // -----------------------------------------------------------------------
  // Step 7: Cleanup.
  // -----------------------------------------------------------------------

  // Close the shutdown handle if it was initialized.
  if (runtime->shutdown_handle_initialized) {
    uv_close(reinterpret_cast<uv_handle_t*>(&runtime->shutdown_handle),
             OnShutdownHandleClosed);
    // Drain any pending close callbacks.
    if (loop != nullptr) {
      uv_run(loop, UV_RUN_NOWAIT);
    }
    runtime->shutdown_handle_initialized = false;
  }

  // Run environment cleanup and at-exit callbacks.
  EdgeEnvironmentRunCleanup(env);
  EdgeEnvironmentRunAtExitCallbacks(env);

  // Release the N-API environment scope.
  const napi_status release_status = unofficial_napi_release_env(env_scope);
  if (release_status != napi_ok && runtime->last_error.empty()) {
    runtime->last_error = "Failed to release N-API environment";
  }

  runtime->env = nullptr;
  runtime->running.store(false);

  return runtime->exit_code;
}

void EdgeRuntimeShutdown(EdgeRuntime* runtime) {
  if (runtime == nullptr) return;

  runtime->shutdown_requested.store(true);

  // If the shutdown handle is initialized and we are running, wake up the
  // event loop from any thread.
  if (runtime->shutdown_handle_initialized && runtime->running.load()) {
    uv_async_send(&runtime->shutdown_handle);
  }
}

int EdgeRuntimeIsRunning(const EdgeRuntime* runtime) {
  if (runtime == nullptr) return 0;
  return runtime->running.load() ? 1 : 0;
}

void EdgeRuntimeDestroy(EdgeRuntime* runtime) {
  delete runtime;
}

const char* EdgeRuntimeGetError(const EdgeRuntime* runtime) {
  if (runtime == nullptr) return nullptr;
  if (runtime->last_error.empty()) return nullptr;
  return runtime->last_error.c_str();
}
