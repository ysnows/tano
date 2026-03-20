# Node.js Core Tests

This directory contains code and data used to test the Node.js implementation.

For a detailed guide on how to write tests in this
directory, see [the guide on writing tests](../doc/contributing/writing-tests.md).

On how to run tests in this directory, see
[the contributing guide](../doc/contributing/pull-requests.md#step-6-test).

For the tests to run on Windows, be sure to clone Node.js source code with the
`autocrlf` git config flag set to true.

## Test Directories

| Directory        | Runs on CI | Purpose                                                                                                       |
| ---------------- | ---------- | ------------------------------------------------------------------------------------------------------------- |
| `abort`          | Yes        | Tests that use `--abort-on-uncaught-exception` and other cases where we want to avoid generating a core file. |
| `addons`         | Yes        | Tests for [addon][] functionality along with some tests that require an addon.                                |
| `async-hooks`    | Yes        | Tests for [async\_hooks][async_hooks] functionality.                                                          |
| `benchmark`      | Yes        | Test minimal functionality of benchmarks.                                                                     |
| `cctest`         | Yes        | C++ tests that are run as part of the build process.                                                          |
| `code-cache`     | No         | Tests for a Node.js binary compiled with V8 code cache.                                                       |
| `common`         | _N/A_      | Common modules shared among many tests.[^1]                                                                   |
| `doctool`        | Yes        | Tests for the documentation generator.                                                                        |
| `es-module`      | Yes        | Test ESM module loading.                                                                                      |
| `fixtures`       | _N/A_      | Test fixtures used in various tests throughout the test suite.                                                |
| `internet`       | No         | Tests that make real outbound network connections.[^2]                                                        |
| `js-native-api`  | Yes        | Tests for Node.js-agnostic [Node-API][] functionality.                                                        |
| `known_issues`   | Yes        | Tests reproducing known issues within the system.[^3]                                                         |
| `message`        | Yes        | Tests for messages that are output for various conditions                                                     |
| `node-api`       | Yes        | Tests for Node.js-specific [Node-API][] functionality.                                                        |
| `parallel`       | Yes        | Various tests that are able to be run in parallel.                                                            |
| `pseudo-tty`     | Yes        | Tests that require stdin/stdout/stderr to be a TTY.                                                           |
| `pummel`         | No         | Various tests for various modules / system functionality operating under load.                                |
| `sequential`     | Yes        | Various tests that must not run in parallel.                                                                  |
| `testpy`         | _N/A_      | Test configuration utility used by various test suites.                                                       |
| `tick-processor` | No         | Tests for the V8 tick processor integration.[^4]                                                              |
| `v8-updates`     | No         | Tests for V8 performance integration.                                                                         |

## Cross-runtime runner

Use `test/nodejs_test_harness` to run the JavaScript suites with a
selectable runtime:

```sh
NODE_TEST_RUNNER=node ./test/nodejs_test_harness
```

Repository-local `edge` example:

```sh
NODE_TEST_RUNNER="$(pwd)/build-edge-rename/edge" \
./test/nodejs_test_harness --category=node:assert
```

This runner:

- Selects the runtime from `NODE_TEST_RUNNER`.
- Uses `out/Release/node` (or `out/Debug/node`) when `NODE_TEST_RUNNER=node`.
- Allows explicit Node path via `NODE_TEST_NODE_BINARY=/path/to/node`.
- Uses `test/tools/deno-node-runner` automatically when
  `NODE_TEST_RUNNER=deno`.
- Unsets `FORCE_COLOR` and `NO_COLOR` to avoid color-related snapshot noise.
- Executes all suites that have a `testcfg.py`, excluding:
  `cctest`, `benchmark`, `addons`, `doctool`, `embedding`,
  `overlapped-checker`, `wasi`, `v8-updates`, `code-cache`, `internet`,
  `tick-processor`, `pummel`, and `wpt`.

Tests in `parallel/` are run in parallel and tests in `sequential/` are run
serially using the existing `tools/test.py` scheduling.

### Category filters

You can run only the tests that belong to one or more generated module
categories:

```sh
./test/nodejs_test_harness --category=node:assert
./test/nodejs_test_harness --categories=node:assert,node:buffer
```

When category filters are used, the harness refreshes
`test/module-categories/*.txt` via
`test/tools/generate_test_module_categories.py` and expands the selected
categories into explicit test paths before invoking `tools/test.py`.

### `// Flags:` skipping

By default, tests whose first meaningful line is `// Flags:` are skipped.
Customize this behavior with `NODE_TEST_SKIP_FLAGS`:

- `prefix` (default): skip only tests that begin with `// Flags:`.
- `any`: skip any test file containing `// Flags:`.
- `none` (or `0`/`false`): do not skip tests because of `// Flags:`.

You can also exclude additional suites via `NODE_TEST_EXCLUDE_SUITES`
(comma-separated list).

The execution harness used by `execute_the_tests` is vendored in
`test/tools/`
(`test.py`, `utils.py`, `pseudo-tty.py`, `run-worker.js`, `run-valgrind.py`)
so the runner does not depend on `../tools`.

[^1]: [Documentation](./common/README.md)

[^2]: Tests for networking related modules may also be present in other directories, but those tests do
    not make outbound connections.

[^3]: All tests inside of this directory are expected to fail. If a test doesn't fail on certain platforms,
    those should be skipped via `known_issues.status`.

[^4]: The tests are for the logic in `lib/internal/v8_prof_processor.js` and `lib/internal/v8_prof_polyfill.js`.
    The tests confirm that the profile processor packages the correct set of scripts from V8 and introduces the
    correct platform specific logic.

[Node-API]: https://nodejs.org/api/n-api.html
[addon]: https://nodejs.org/api/addons.html
[async_hooks]: https://nodejs.org/api/async_hooks.html
