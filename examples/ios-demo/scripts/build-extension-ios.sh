#!/usr/bin/env bash
#
# Build an Enconvo extension for iOS
#
# Usage: ./build-extension-ios.sh <module-path> [output-dir]
#
# This script:
# 1. Builds the extension using `npx enconvo build`
# 2. Copies the compiled output to the iOS bundle's extensions directory
# 3. Replaces @enconvo/api with the iOS shim (since the macOS SDK has incompatible deps)
#
# Example:
#   ./build-extension-ios.sh ../../modules/translate js/extensions/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

MODULE_PATH="${1:?Usage: $0 <module-path> [output-dir]}"
OUTPUT_DIR="${2:-$PROJECT_DIR/js/extensions}"

# Resolve absolute paths
MODULE_PATH="$(cd "$MODULE_PATH" && pwd)"
MODULE_NAME="$(basename "$MODULE_PATH")"

echo "=== Building extension for iOS: $MODULE_NAME ==="
echo "Source: $MODULE_PATH"
echo "Output: $OUTPUT_DIR/$MODULE_NAME"

# Step 1: Build with enconvo CLI
echo "--- Building with npx enconvo build..."
cd "$MODULE_PATH"
npx enconvo build 2>&1 | tail -5

# Step 2: Find the compiled output
# The build output goes to ~/.config/enconvo/extension/{name}/ or ~/.config/.enconvo/.extension/{name}/
COMPILED_PATH="$HOME/.config/enconvo/extension/$MODULE_NAME"
if [ ! -d "$COMPILED_PATH" ]; then
    COMPILED_PATH="$HOME/.config/.enconvo/.extension/$MODULE_NAME"
fi
if [ ! -d "$COMPILED_PATH" ]; then
    echo "ERROR: Compiled extension not found at expected paths"
    exit 1
fi

echo "--- Compiled output found at: $COMPILED_PATH"

# Step 3: Copy to iOS bundle
mkdir -p "$OUTPUT_DIR/$MODULE_NAME"
cp -r "$COMPILED_PATH"/* "$OUTPUT_DIR/$MODULE_NAME/"

# Step 4: Ensure package.json doesn't have "type": "module" (CommonJS required)
if grep -q '"type": "module"' "$OUTPUT_DIR/$MODULE_NAME/package.json" 2>/dev/null; then
    echo "--- Removing 'type: module' from package.json (CommonJS required for iOS)"
    sed -i '' 's/"type": "module",//' "$OUTPUT_DIR/$MODULE_NAME/package.json"
fi

echo "--- Copied to $OUTPUT_DIR/$MODULE_NAME/"
echo ""

# Step 5: Report
JS_COUNT=$(find "$OUTPUT_DIR/$MODULE_NAME" -name "*.js" | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR/$MODULE_NAME" | cut -f1)
echo "=== Done: $MODULE_NAME ($JS_COUNT JS files, $TOTAL_SIZE) ==="
echo ""
echo "Note: This extension uses the iOS @enconvo/api shim."
echo "The shim is at: js/node_modules/@enconvo/api/index.js"
echo "If the extension fails to load, check for unresolved dynamic requires."
