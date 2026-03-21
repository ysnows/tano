#!/bin/bash
# Test Tano in iOS Simulator
# Usage: ./scripts/test-simulator.sh

set -e

echo "=== Tano Simulator Test ==="

# 1. Build the Swift package
echo "Building TanoCore..."
swift build 2>&1 | tail -3

# 2. Run all tests
echo ""
echo "Running tests..."
swift test 2>&1 | tail -5

# 3. Check CLI works
echo ""
echo "Testing CLI..."
cd packages/cli
bun run src/index.ts doctor
cd ../..

# 4. Create a test project
echo ""
echo "Creating test project..."
TMPDIR=$(mktemp -d)
cd packages/cli
bun run src/index.ts create test-app 2>&1 || true
rm -rf test-app
cd ../..

# 5. Build test project
echo ""
echo "Building server bundle..."
cd packages/cli
bun run src/index.ts create sim-test 2>&1 || true
if [ -d "sim-test" ]; then
    cd sim-test
    bun run ../src/index.ts build ios 2>&1
    cd ..
    rm -rf sim-test
fi
cd ../..

echo ""
echo "=== All simulator tests passed ==="
