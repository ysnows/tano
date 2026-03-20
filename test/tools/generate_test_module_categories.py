#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from collections import Counter, defaultdict
from pathlib import Path

TEST_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = TEST_ROOT.parent

sys.path.insert(0, str(TEST_ROOT / "tools"))
sys.path.insert(0, str(TEST_ROOT))

import test as testmod  # noqa: E402


CATEGORIES = [
    "node:assert",
    "node:buffer",
    "node:console",
    "node:dgram",
    "node:diagnostics_channel",
    "node:dns",
    "node:events",
    "node:fs",
    "node:http",
    "node:https",
    "node:os",
    "node:path",
    "node:punycode",
    "node:querystring",
    "node:readline",
    "node:stream",
    "node:string_decoder",
    "node:timers",
    "node:tty",
    "node:url",
    "node:zlib",
    "node:async_hooks",
    "node:child_process",
    "node:cluster",
    "node:crypto",
    "node:domain",
    "node:http2",
    "node:module",
    "node:net",
    "node:perf_hooks",
    "node:process",
    "node:sys",
    "node:tls",
    "node:util",
    "node:v8",
    "node:vm",
    "node:wasi",
    "node:worker_threads",
    "node:inspector",
    "node:repl",
    "node:sqlite",
    "node:test",
    "node:trace_events",
    "other",
]

HARNESS_EXCLUDED_SUITES = {
    "cctest",
    "benchmark",
    "addons",
    "doctool",
    "embedding",
    "overlapped-checker",
    "wasi",
    "v8-updates",
    "code-cache",
    "internet",
    "tick-processor",
    "pummel",
    "wpt",
}

CONTENT_MODULE_MAP = {
    "assert": "node:assert",
    "node:assert": "node:assert",
    "buffer": "node:buffer",
    "node:buffer": "node:buffer",
    "console": "node:console",
    "node:console": "node:console",
    "dgram": "node:dgram",
    "node:dgram": "node:dgram",
    "diagnostics_channel": "node:diagnostics_channel",
    "node:diagnostics_channel": "node:diagnostics_channel",
    "dns": "node:dns",
    "node:dns": "node:dns",
    "events": "node:events",
    "node:events": "node:events",
    "fs": "node:fs",
    "node:fs": "node:fs",
    "fs/promises": "node:fs",
    "node:fs/promises": "node:fs",
    "http": "node:http",
    "node:http": "node:http",
    "https": "node:https",
    "node:https": "node:https",
    "os": "node:os",
    "node:os": "node:os",
    "path": "node:path",
    "node:path": "node:path",
    "punycode": "node:punycode",
    "node:punycode": "node:punycode",
    "querystring": "node:querystring",
    "node:querystring": "node:querystring",
    "readline": "node:readline",
    "node:readline": "node:readline",
    "stream": "node:stream",
    "node:stream": "node:stream",
    "stream/consumers": "node:stream",
    "node:stream/consumers": "node:stream",
    "stream/duplex": "node:stream",
    "node:stream/duplex": "node:stream",
    "stream/promises": "node:stream",
    "node:stream/promises": "node:stream",
    "stream/web": "node:stream",
    "node:stream/web": "node:stream",
    "string_decoder": "node:string_decoder",
    "node:string_decoder": "node:string_decoder",
    "timers": "node:timers",
    "node:timers": "node:timers",
    "timers/promises": "node:timers",
    "node:timers/promises": "node:timers",
    "tty": "node:tty",
    "node:tty": "node:tty",
    "url": "node:url",
    "node:url": "node:url",
    "zlib": "node:zlib",
    "node:zlib": "node:zlib",
    "async_hooks": "node:async_hooks",
    "node:async_hooks": "node:async_hooks",
    "child_process": "node:child_process",
    "node:child_process": "node:child_process",
    "cluster": "node:cluster",
    "node:cluster": "node:cluster",
    "crypto": "node:crypto",
    "node:crypto": "node:crypto",
    "domain": "node:domain",
    "node:domain": "node:domain",
    "http2": "node:http2",
    "node:http2": "node:http2",
    "module": "node:module",
    "node:module": "node:module",
    "net": "node:net",
    "node:net": "node:net",
    "perf_hooks": "node:perf_hooks",
    "node:perf_hooks": "node:perf_hooks",
    "process": "node:process",
    "node:process": "node:process",
    "sys": "node:sys",
    "node:sys": "node:sys",
    "tls": "node:tls",
    "node:tls": "node:tls",
    "util": "node:util",
    "node:util": "node:util",
    "v8": "node:v8",
    "node:v8": "node:v8",
    "vm": "node:vm",
    "node:vm": "node:vm",
    "wasi": "node:wasi",
    "node:wasi": "node:wasi",
    "worker_threads": "node:worker_threads",
    "node:worker_threads": "node:worker_threads",
    "inspector": "node:inspector",
    "node:inspector": "node:inspector",
    "repl": "node:repl",
    "node:repl": "node:repl",
    "sqlite": "node:sqlite",
    "node:sqlite": "node:sqlite",
    "test": "node:test",
    "node:test": "node:test",
    "trace_events": "node:trace_events",
    "node:trace_events": "node:trace_events",
}

STRONG_CONTENT_CATEGORIES = (
    set(CONTENT_MODULE_MAP.values())
    - {
        "node:assert",
        "node:events",
        "node:os",
        "node:path",
        "node:process",
        "node:timers",
        "node:util",
    }
)

CONTENT_IMPORT_PATTERN = re.compile(
    r"(?:require\(\s*|import\(\s*|from\s+)[\"']((?:node:)?[a-zA-Z0-9_./-]+)[\"']"
)
FLAGS_DIRECTIVE_PATTERN = re.compile(r"//\s+Flags:(.*)")
SNAPSHOT_CLI_FLAG_PATTERN = re.compile(
    r"--(?:build-snapshot(?:-config)?|(?:no-)?node-snapshot|snapshot-[a-z0-9-]+)"
)

CUSTOM_V8_EXACT_FLAGS = {
    "--allow-natives-syntax",
    "--allow_natives_syntax",
    "--debug-arraybuffer-allocations",
    "--disallow-code-generation-from-strings",
    "--enable-sharedarraybuffer-per-context",
    "--expose-gc",
    "--expose_gc",
    "--expose_externalize_string",
    "--gc-global",
    "--harmony-import-attributes",
    "--jitless",
    "--js-source-phase-imports",
    "--no-concurrent-array-buffer-sweeping",
    "--no-liftoff",
    "--no-opt",
    "--noconcurrent_recompilation",
    "--predictable-gc-schedule",
}

CUSTOM_V8_PREFIX_FLAGS = (
    "--gc-",
    "--max-old-space-size",
    "--max_old_space_size",
    "--stress-",
    "--trace-gc",
    "--turbo-",
    "--no-turbo-",
    "--v8-pool-size",
)

SPECIAL_CASES = {
    "abort/test-addon-register-signal-handler.js": "node:process",
    "abort/test-addon-uv-handle-leak.js": "other",
    "known_issues/test-stdin-is-always-net.socket.js": "node:net",
    "parallel/test-async-wrap-constructor.js": "node:async_hooks",
    "parallel/test-async-wrap-pop-id-during-load.js": "node:async_hooks",
    "parallel/test-async-wrap-promise-after-enabled.js": "node:async_hooks",
    "parallel/test-async-wrap-trigger-id.js": "node:async_hooks",
    "parallel/test-async-wrap-uncaughtexception.js": "node:async_hooks",
    "parallel/test-asyncresource-bind.js": "node:async_hooks",
    "parallel/test-blocklist.js": "node:net",
    "parallel/test-blocklist-clone.js": "node:net",
    "parallel/test-c-ares.js": "node:dns",
    "parallel/test-config-file.js": "node:process",
    "parallel/test-console.js": "node:console",
    "parallel/test-crypto.js": "node:crypto",
    "parallel/test-data-url.js": "node:url",
    "parallel/test-diagnostic-channel-http-request-created.js":
        "node:diagnostics_channel",
    "parallel/test-diagnostic-channel-http-response-created.js":
        "node:diagnostics_channel",
    "parallel/test-dotenv-edge-cases.js": "node:process",
    "parallel/test-dotenv-node-options.js": "node:process",
    "parallel/test-eventemitter-asyncresource.js": "node:events",
    "parallel/test-global-webcrypto.js": "node:crypto",
    "parallel/test-global-webstreams.js": "node:stream",
    "parallel/test-http.js": "node:http",
    "parallel/test-messagechannel.js": "node:worker_threads",
    "parallel/test-node-output-v8-warning.mjs": "node:v8",
    "parallel/test-node-output-vm.mjs": "node:vm",
    "parallel/test-queue-microtask-uncaught-asynchooks.js":
        "node:async_hooks",
    "parallel/test-resource-usage.js": "node:process",
    "parallel/test-safe-get-env.js": "node:process",
    "parallel/test-set-http-max-http-headers.js": "node:http",
    "parallel/test-set-incoming-message-header.js": "node:http",
    "parallel/test-sqlite.js": "node:sqlite",
    "parallel/test-sqlite-aggregate-function.mjs": "node:sqlite",
    "parallel/test-sqlite-authz.js": "node:sqlite",
    "parallel/test-sqlite-backup.mjs": "node:sqlite",
    "parallel/test-sqlite-config.js": "node:sqlite",
    "parallel/test-sqlite-custom-functions.js": "node:sqlite",
    "parallel/test-sqlite-database-sync-dispose.js": "node:sqlite",
    "parallel/test-sqlite-database-sync.js": "node:sqlite",
    "parallel/test-sqlite-named-parameters.js": "node:sqlite",
    "parallel/test-sqlite-statement-sync-columns.js": "node:sqlite",
    "parallel/test-sqlite-template-tag.js": "node:sqlite",
    "parallel/test-sqlite-transactions.js": "node:sqlite",
    "parallel/test-sqlite-typed-array-and-data-view.js": "node:sqlite",
    "parallel/test-stdin-from-file.js": "node:process",
    "parallel/test-stdin-hang.js": "node:process",
    "parallel/test-stdin-pause-resume-sync.js": "node:process",
    "parallel/test-stdin-pause-resume.js": "node:process",
    "parallel/test-stdin-pipe-large.js": "node:process",
    "parallel/test-stdin-pipe-resume.js": "node:process",
    "parallel/test-stdin-resume-pause.js": "node:process",
    "parallel/test-stdout-close-catch.js": "node:process",
    "parallel/test-stdout-close-unref.js": "node:process",
    "parallel/test-stdout-stderr-reading.js": "node:process",
    "parallel/test-stdout-stderr-write.js": "node:process",
    "parallel/test-stdout-to-file.js": "node:process",
    "parallel/test-sync-fileread.js": "node:fs",
    "parallel/test-timers.js": "node:timers",
    "parallel/test-ttywrap-stack.js": "node:tty",
    "parallel/test-unhandled-exception-with-worker-inuse.js":
        "node:worker_threads",
    "sequential/test-async-wrap-getasyncid.js": "node:async_hooks",
}


def sanitize_category_filename(category: str) -> str:
    return category.replace(":", "_").replace("/", "_") + ".txt"


def resolve_runner() -> str:
    requested = os.environ.get("NODE_TEST_RUNNER", "node")

    if requested == "node":
        explicit = os.environ.get("NODE_TEST_NODE_BINARY")
        if explicit and os.access(explicit, os.X_OK):
            return explicit

        release = TEST_ROOT.parent / "node" / "out" / "Release" / "node"
        if os.access(release, os.X_OK):
            return str(release)

        debug = TEST_ROOT.parent / "node" / "out" / "Debug" / "node"
        if os.access(debug, os.X_OK):
            return str(debug)

        from_path = shutil.which("node")
        if from_path:
            return from_path

        raise SystemExit(
            "Could not resolve a Node binary. Set NODE_TEST_RUNNER or "
            "NODE_TEST_NODE_BINARY."
        )

    if os.path.basename(requested) == "deno":
        return str(TEST_ROOT / "tools" / "deno-node-runner")

    if "/" not in requested:
        resolved = shutil.which(requested)
        if resolved:
            return resolved

    return requested


def parse_leading_flags_header(path: Path) -> list[str]:
    try:
        source = path.read_text(encoding="utf8", errors="ignore")
    except OSError:
        return []

    flags: list[str] = []
    for match in FLAGS_DIRECTIVE_PATTERN.finditer(source):
        flags.extend(match.group(1).strip().split())
    return flags


def uses_custom_v8_flags(path: Path) -> bool:
    for token in parse_leading_flags_header(path):
        if token in CUSTOM_V8_EXACT_FLAGS:
            return True
        if any(token.startswith(prefix) for prefix in CUSTOM_V8_PREFIX_FLAGS):
            return True
    return False


def uses_snapshot_cli_flags(path: Path) -> bool:
    try:
        source = path.read_text(encoding="utf8", errors="ignore")
    except OSError:
        return False
    return SNAPSHOT_CLI_FLAG_PATTERN.search(source) is not None


def selected_suites() -> list[str]:
    excluded = set(HARNESS_EXCLUDED_SUITES)
    for value in os.environ.get("NODE_TEST_EXCLUDE_SUITES", "").split(","):
        value = value.strip()
        if value:
            excluded.add(value)

    return [
        entry.name
        for entry in sorted(TEST_ROOT.iterdir())
        if entry.is_dir()
        and entry.name not in excluded
        and (entry / "testcfg.py").is_file()
    ]


def build_case_list() -> tuple[int, list[dict[str, str]]]:
    suites = selected_suites()
    parser = testmod.BuildOptions()
    options, _ = parser.parse_known_args([])
    options.timeout = 10
    options.test_root = str(TEST_ROOT)
    options.shell = resolve_runner()

    if not testmod.ProcessOptions(options):
        raise SystemExit("Could not initialize test.py options")

    original_skip_flags = os.environ.get("NODE_TEST_SKIP_FLAGS")
    os.environ["NODE_TEST_SKIP_FLAGS"] = "none"
    try:
        repositories = [
            testmod.TestRepository(str(TEST_ROOT / name))
            for name in testmod.GetSuites(str(TEST_ROOT))
        ]
        root_suite = testmod.LiteralTestSuite(repositories, str(TEST_ROOT))
        paths = testmod.ArgsToTestPaths(
            str(TEST_ROOT), suites, testmod.GetSuites(str(TEST_ROOT))
        )
        processor = testmod.GetSpecialCommandProcessor(options.special_command)
        context = testmod.Context(
            str(WORKSPACE),
            testmod.VERBOSE,
            options.shell,
            options.node_args,
            options.expect_fail,
            options.timeout,
            processor,
            options.suppress_dialogs,
            options.store_unexpected_output,
            options.repeat,
            options.abort_on_timeout,
        )

        for requested_mode in options.mode:
            if requested_mode:
                context.default_mode = requested_mode
                break
        else:
            context.default_mode = "none"

        sections = []
        defs = {}
        root_suite.GetTestStatus(context, sections, defs)
        config = testmod.Configuration(sections, defs)

        all_cases = []
        for arch in options.arch:
            for mode in options.mode:
                vm = context.GetVm(arch, mode)
                if not os.path.exists(vm):
                    continue

                if "llrt" in vm:
                    vm_arch = "arm64"
                else:
                    arch_context = testmod.Execute([vm, "-p", "process.arch"], context)
                    vm_arch = arch_context.stdout.rstrip()
                    if arch_context.exit_code != 0 or vm_arch == "undefined":
                        continue

                env = {
                    "mode": mode,
                    "system": testmod.utils.GuessOS(),
                    "arch": vm_arch,
                    "type": testmod.get_env_type(vm, options.type, context),
                    "asan": testmod.get_asan_state(vm, context),
                    "pointer_compression": testmod.get_pointer_compression_state(
                        vm, context
                    ),
                }

                for path in paths:
                    test_list = root_suite.ListTests([], path, context, arch, mode)
                    cases, _ = config.ClassifyTests(test_list, env)
                    all_cases.extend(cases)
    finally:
        if original_skip_flags is None:
            os.environ.pop("NODE_TEST_SKIP_FLAGS", None)
        else:
            os.environ["NODE_TEST_SKIP_FLAGS"] = original_skip_flags

    discovered = len(all_cases)
    cases_to_run = [
        case
        for case in all_cases
        if testmod.SKIP not in case.outcomes
        and not any(skip in case.file for skip in options.skip_tests)
        and not (
            options.flaky_tests == testmod.SKIP
            and {testmod.SLOW, testmod.FLAKY} & case.outcomes
        )
    ]

    records = []
    for case in sorted(cases_to_run, key=lambda item: item.file):
        relfile = os.path.relpath(case.file, TEST_ROOT).replace(os.sep, "/")
        abspath = Path(case.file)
        if uses_custom_v8_flags(abspath):
            continue
        if uses_snapshot_cli_flags(abspath):
            continue
        records.append(
            {
                "relfile": relfile,
                "suite": relfile.split("/", 1)[0],
                "basename": Path(relfile).stem.lower(),
                "abspath": str(abspath),
            }
        )

    return discovered, records


def infer_category_from_source(path: Path, cache: dict[Path, str | None]) -> str | None:
    if path in cache:
        return cache[path]

    try:
        source = path.read_text(encoding="utf8", errors="ignore")
    except OSError:
        cache[path] = None
        return None

    found = {
        CONTENT_MODULE_MAP[module]
        for module in CONTENT_IMPORT_PATTERN.findall(source)
        if module in CONTENT_MODULE_MAP
    }
    strong = {category for category in found if category in STRONG_CONTENT_CATEGORIES}
    guess = next(iter(strong)) if len(strong) == 1 else None
    cache[path] = guess
    return guess


def startswith_any(value: str, prefixes: tuple[str, ...]) -> bool:
    return value.startswith(prefixes)


def classify_record(record: dict[str, str], cache: dict[Path, str | None]) -> str:
    relfile = record["relfile"]
    suite = record["suite"]
    basename = record["basename"]

    if relfile in SPECIAL_CASES:
        return SPECIAL_CASES[relfile]

    if suite == "async-hooks":
        return "node:async_hooks"
    if suite in {"es-module", "module-hooks"}:
        return "node:module"
    if suite == "test-runner":
        return "node:test"
    if suite == "sqlite":
        return "node:sqlite"
    if suite in {"js-native-api", "node-api"}:
        return "other"
    if suite == "test426":
        return "node:vm"
    if suite == "wasm-allocation":
        return "node:v8"
    if suite == "client-proxy":
        return "node:https" if "https" in basename else "node:http"
    if suite == "sea":
        if "inspect" in basename:
            return "node:inspector"
        if "worker" in basename:
            return "node:worker_threads"
        if "snapshot" in basename:
            return "node:v8"
        return "node:module"
    if suite == "report":
        return "node:worker_threads" if "worker" in basename else "node:process"
    if suite == "message":
        if "assert" in basename:
            return "node:assert"
        if "console" in basename:
            return "node:console"
        if "util" in basename or "inspect" in basename:
            return "node:util"
        if "tick" in basename:
            return "node:timers"
        return "node:process"

    if startswith_any(basename, ("test-http2", "http2")):
        return "node:http2"
    if startswith_any(basename, ("test-https", "https")):
        return "node:https"
    if (
        startswith_any(basename, ("test-http", "http"))
        or "http-parser" in basename
    ):
        return "node:http"
    if startswith_any(basename, ("test-assert", "internal_assert")):
        return "node:assert"
    if basename == "assert_throws_stack":
        return "node:assert"
    if startswith_any(basename, ("test-buffer", "buffer")) or "slowbuffer" in basename:
        return "node:buffer"
    if startswith_any(basename, ("test-console", "console")):
        return "node:console"
    if startswith_any(basename, ("test-dgram", "dgram")):
        return "node:dgram"
    if startswith_any(
        basename,
        ("test-diagnostic", "diagnostic-channel", "diagnostics-", "diagnostics_channel"),
    ):
        return "node:diagnostics_channel"
    if startswith_any(basename, ("test-dns", "dns")):
        return "node:dns"
    if startswith_any(basename, ("test-events", "events", "test-event-", "event-")):
        return "node:events"
    if (
        startswith_any(
            basename,
            (
                "test-fs",
                "fs-",
                "test-fsevent",
                "test-fsreq",
                "test-filehandle",
                "test-watch",
                "test-run-watch",
                "test-opendir",
                "test-sync-fileread",
            ),
        )
        or "statwatcher" in basename
    ):
        return "node:fs"
    if startswith_any(basename, ("test-os", "os-")):
        return "node:os"
    if startswith_any(basename, ("test-path", "path-")) or "node-modules-paths" in basename:
        return "node:path"
    if startswith_any(basename, ("test-punycode", "punycode")):
        return "node:punycode"
    if startswith_any(basename, ("test-querystring", "querystring")):
        return "node:querystring"
    if startswith_any(basename, ("test-readline", "readline")):
        return "node:readline"
    if startswith_any(
        basename,
        (
            "test-stream",
            "stream",
            "test-readable",
            "readable",
            "test-writable",
            "writable",
            "test-duplex",
            "duplex",
            "test-pipeline",
            "pipeline",
            "test-compose",
            "compose",
            "test-fastutf8stream",
            "fastutf8stream",
        ),
    ):
        return "node:stream"
    if startswith_any(
        basename,
        (
            "test-string-decoder",
            "string-decoder",
            "test-string_decoder",
            "string_decoder",
            "test-stringbytes",
            "stringbytes",
        ),
    ):
        return "node:string_decoder"
    if (
        startswith_any(
            basename,
            (
                "test-timers",
                "timers",
                "test-next-tick",
                "next-tick",
                "test-nexttick",
                "nexttick",
                "test-setimmediate",
                "test-queue-microtask",
            ),
        )
        or basename == "max_tick_depth"
    ):
        return "node:timers"
    if (
        startswith_any(
            basename,
            ("test-tty", "tty-", "stdin-", "stdout-", "stderr-", "stdio-"),
        )
        or basename == "stdin-setrawmode"
        or ("stdio" in basename and suite == "pseudo-tty")
    ):
        return "node:tty"
    if startswith_any(
        basename, ("test-url", "url-", "whatwg-url", "test-whatwg-url")
    ) or "urlpattern" in basename:
        return "node:url"
    if startswith_any(basename, ("test-zlib", "zlib")):
        return "node:zlib"
    if startswith_any(
        basename,
        (
            "test-async-hooks",
            "async-hooks",
            "test-async-local-storage",
            "async-local-storage",
            "test-als-",
            "test-async-wrap",
            "test-asyncresource",
            "test-embedder.api.async-resource",
            "test-getaddrinforeqwrap",
            "test-getnameinforeqwrap",
            "test-graph.",
            "test-fseventwrap",
            "test-fsreqcallback",
            "test-disable-in-init",
            "test-enable-",
            "test-emit-",
            "test-destroy-not-blocked",
            "test-filehandle-no-reuse",
            "test-callback-error",
        ),
    ):
        return "node:async_hooks"
    if startswith_any(
        basename, ("test-child-process", "child-process", "test-stdin-child-proc")
    ) or basename == "node_run_non_existent":
        return "node:child_process"
    if startswith_any(basename, ("test-cluster", "cluster")):
        return "node:cluster"
    if startswith_any(
        basename,
        ("test-crypto", "crypto", "test-webcrypto", "webcrypto"),
    ) or any(token in basename for token in ("x509", "openssl", "fips")):
        return "node:crypto"
    if startswith_any(basename, ("test-domain", "domain")):
        return "node:domain"
    if (
        startswith_any(
            basename,
            (
                "test-module",
                "module",
                "test-cjs-",
                "test-require-",
                "test-esm-",
                "test-import-",
                "test-loaders-",
                "test-policy-",
                "test-disable-require-module",
                "test-directory-import",
                "test-find-package-json",
                "test-shadow-realm-custom-loaders",
                "test-shadow-realm-preload-module",
            ),
        )
        or "import-meta" in basename
        or "legacymainresolve" in basename
    ):
        return "node:module"
    if startswith_any(
        basename,
        ("test-net", "net-", "test-socket", "socket", "test-tcp", "tcp", "test-blocklist"),
    ):
        return "node:net"
    if startswith_any(
        basename,
        (
            "test-perf-hooks",
            "perf-hooks",
            "test-performance",
            "performance",
            "test-cpu-prof",
            "test-diagnostic-dir-cpu-prof",
            "test-diagnostic-dir-heap-prof",
        ),
    ) or basename == "test-tojson-perf_hooks":
        return "node:perf_hooks"
    if startswith_any(
        basename,
        (
            "test-process",
            "process",
            "test-cli-",
            "test-abortcontroller",
            "test-abort-controller",
            "test-abortsignal",
            "test-signal",
            "test-warning",
            "test-env",
            "test-dotenv",
            "test-config-file",
            "test-safe-get-env",
            "test-permission",
            "test-fatal-error",
            "test-init",
            "test-cwd",
            "test-resource-usage",
            "test-setproctitle",
            "test-disable-sigusr1",
            "test-kill-segfault",
            "test-beforeexit-event-exit",
        ),
    ):
        return "node:process"
    if startswith_any(basename, ("test-sys", "sys")):
        return "node:sys"
    if startswith_any(basename, ("test-tls", "tls")) or "tlssocket" in basename:
        return "node:tls"
    if startswith_any(
        basename,
        ("test-util", "util", "test-parse-args"),
    ) or any(token in basename for token in ("inspect", "callbackify", "promisify", "deprecate")):
        return "node:util"
    if startswith_any(
        basename,
        (
            "test-v8",
            "v8",
            "test-heap",
            "heapdump",
            "test-startup",
            "test-no-node-snapshot",
        ),
    ) or any(token in basename for token in ("heapsnapshot", "serdes")):
        return "node:v8"
    if startswith_any(
        basename,
        (
            "test-vm",
            "vm",
            "test-compile",
            "compile",
            "test-contextify",
            "test-node-output-vm",
            "test-shadow-realm",
        ),
    ):
        return "node:vm"
    if startswith_any(basename, ("test-wasi", "wasi")):
        return "node:wasi"
    if startswith_any(
        basename,
        ("test-worker", "worker", "test-messagechannel", "test-broadcastchannel"),
    ) or basename == "test-is-internal-thread":
        return "node:worker_threads"
    if startswith_any(
        basename,
        ("test-inspector", "inspector", "test-debugger", "debugger", "test-debug-", "test-inspect"),
    ) or basename == "test-error-reporting":
        return "node:inspector"
    if startswith_any(basename, ("test-repl", "repl")):
        return "node:repl"
    if startswith_any(basename, ("test-sqlite", "sqlite")) or "/sqlite/" in relfile:
        return "node:sqlite"
    if startswith_any(
        basename,
        (
            "test-output-",
            "test-runner",
            "test-watch",
            "test-run-watch",
            "test-testpy",
            "test-parse-test-envs",
            "test-parse-test-only-envs",
        ),
    ):
        return "node:test"
    if startswith_any(
        basename,
        (
            "test-trace-events",
            "trace-events",
            "test-tracing",
            "test-trace-",
            "trace-",
        ),
    ):
        return "node:trace_events"

    guessed = infer_category_from_source(Path(record["abspath"]), cache)
    return guessed or "other"


def write_category_files(
    output_dir: Path, categorized: dict[str, list[str]]
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for category in CATEGORIES:
        lines = sorted(categorized.get(category, []))
        filename = output_dir / sanitize_category_filename(category)
        with filename.open("w", encoding="utf8") as handle:
            if lines:
                handle.write("\n".join(lines))
                handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate one test-per-line category files for nodejs_test_harness."
    )
    parser.add_argument(
        "--output-dir",
        default=str(TEST_ROOT / "module-categories"),
        help="Directory that will receive the generated .txt files.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write the generated category files to --output-dir.",
    )
    args = parser.parse_args()

    discovered, records = build_case_list()
    cache: dict[Path, str | None] = {}
    categorized: dict[str, list[str]] = defaultdict(list)

    for record in records:
        category = classify_record(record, cache)
        if category not in CATEGORIES:
            raise ValueError(f"Unexpected category {category!r} for {record['relfile']}")
        categorized[category].append(record["relfile"])

    written = sum(len(items) for items in categorized.values())
    if written != len(records):
        raise ValueError(f"Expected {len(records)} runnable tests, wrote {written}")

    seen = set()
    for category, items in categorized.items():
        for item in items:
            if item in seen:
                raise ValueError(f"Duplicate assignment for {item}")
            seen.add(item)

    if len(seen) != len(records):
        raise ValueError("Not all runnable tests were assigned to a category")

    if args.write:
        write_category_files(Path(args.output_dir), categorized)

    print(f"Discovered: {discovered}")
    print(f"Skipped: {discovered - len(records)}")
    print(f"Runnable: {len(records)}")
    for category in CATEGORIES:
        print(f"{category}\t{len(categorized.get(category, []))}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
