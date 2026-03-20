/**
 * @file edge_embed.h
 * @brief Public C API for embedding the Edge.js runtime in host applications.
 *
 * This header provides the embedding API for running the Edge.js runtime on a
 * background thread inside iOS/Android (or any other) host applications. The
 * runtime lifecycle is:
 *
 *   1. EdgeProcessInit()          -- once per process (thread-safe)
 *   2. EdgeRuntimeCreate(config)  -- allocate a runtime instance
 *   3. EdgeRuntimeRun(runtime)    -- blocking; run on a background thread
 *   4. EdgeRuntimeShutdown(rt)    -- thread-safe; signal graceful stop
 *   5. EdgeRuntimeDestroy(rt)     -- free resources after Run returns
 *
 * IMPORTANT: EdgeProcessInit() and EdgeInitializeCliProcess() (from edge_cli.h)
 * are mutually exclusive. Call exactly one of them per process. The CLI variant
 * installs signal handlers that conflict with host app signal handling;
 * EdgeProcessInit() intentionally omits signal handler installation so the host
 * app retains full control.
 */
#ifndef EDGE_EMBED_H_
#define EDGE_EMBED_H_

#ifdef __cplusplus
extern "C" {
#endif

/** Opaque handle to an Edge.js runtime instance. */
typedef struct EdgeRuntime EdgeRuntime;

/**
 * Callback invoked when a fatal error occurs during runtime execution.
 * @param message  Human-readable error description.
 * @param user_data  The user_data pointer from EdgeRuntimeConfig.
 */
typedef void (*EdgeFatalErrorCallback)(const char* message, void* user_data);

/** Configuration for creating an Edge.js runtime instance. */
typedef struct EdgeRuntimeConfig {
  /** Path to the JavaScript entry script (required). */
  const char* script_path;

  /** Path to the extension directory (optional, may be NULL). */
  const char* extension_path;

  /** Path to the Unix domain socket for IPC (optional, may be NULL). */
  const char* socket_path;

  /** Number of elements in argv (optional, 0 if unused). */
  int argc;

  /** Argument vector passed to process.argv (optional, may be NULL). */
  const char** argv;

  /** Callback for fatal errors (optional, may be NULL). */
  EdgeFatalErrorCallback on_fatal;

  /** Opaque user data forwarded to on_fatal (optional, may be NULL). */
  void* user_data;
} EdgeRuntimeConfig;

/** Status codes returned by Edge embedding API functions. */
typedef enum EdgeStatus {
  EDGE_OK = 0,
  EDGE_ERROR_INIT_FAILED = 1,
  EDGE_ERROR_OPENSSL_INIT = 2,
  EDGE_ERROR_ENV_CREATE = 3,
  EDGE_ERROR_SCRIPT_LOAD = 4,
  EDGE_ERROR_ALREADY_RUNNING = 5,
  EDGE_ERROR_NOT_RUNNING = 6,
} EdgeStatus;

/**
 * One-time process-wide initialization. Thread-safe (uses std::call_once).
 * Initializes OpenSSL but does NOT install signal handlers, making it safe
 * for embedding inside host applications that manage their own signals.
 *
 * @return EDGE_OK on success, or EDGE_ERROR_OPENSSL_INIT on failure.
 */
EdgeStatus EdgeProcessInit(void);

/**
 * Allocate and configure an Edge.js runtime instance.
 *
 * @param config  Configuration (must not be NULL). The struct and all pointed-to
 *                strings are copied; the caller may free them after this call.
 * @return A new runtime handle, or NULL on failure.
 */
EdgeRuntime* EdgeRuntimeCreate(const EdgeRuntimeConfig* config);

/**
 * Run the runtime's event loop. This function BLOCKS until the script exits
 * or EdgeRuntimeShutdown() is called from another thread.
 *
 * Typical usage: dispatch to a background thread.
 *
 * @param runtime  Handle from EdgeRuntimeCreate().
 * @return The script's exit code (0 on clean shutdown).
 */
int EdgeRuntimeRun(EdgeRuntime* runtime);

/**
 * Request graceful shutdown from any thread. This is thread-safe and may be
 * called while EdgeRuntimeRun() is blocking on another thread. The event loop
 * will stop at its next iteration.
 *
 * @param runtime  Handle from EdgeRuntimeCreate().
 */
void EdgeRuntimeShutdown(EdgeRuntime* runtime);

/**
 * Query whether the runtime is currently executing (EdgeRuntimeRun() is active).
 *
 * @param runtime  Handle from EdgeRuntimeCreate().
 * @return 1 if running, 0 otherwise.
 */
int EdgeRuntimeIsRunning(const EdgeRuntime* runtime);

/**
 * Free all resources associated with a runtime instance.
 * Must be called after EdgeRuntimeRun() has returned.
 *
 * @param runtime  Handle from EdgeRuntimeCreate(), or NULL (no-op).
 */
void EdgeRuntimeDestroy(EdgeRuntime* runtime);

/**
 * Retrieve the last error message from the runtime.
 *
 * @param runtime  Handle from EdgeRuntimeCreate().
 * @return A null-terminated string, or NULL if no error occurred.
 *         The pointer is valid until the next API call on this runtime or
 *         until EdgeRuntimeDestroy().
 */
const char* EdgeRuntimeGetError(const EdgeRuntime* runtime);

#ifdef __cplusplus
}
#endif
#endif /* EDGE_EMBED_H_ */
