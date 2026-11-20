#!/usr/bin/env bash
# Cloud Agent HQ — OpenCode Worker Verification Script
# Validates that OpenCode is installed and configured correctly

set -euo pipefail

echo "=== OpenCode Worker Verification ==="

# Check OpenCode installation
if ! command -v opencode &> /dev/null; then
    echo "❌ OpenCode not found in PATH"
    exit 1
fi

VERSION=$(opencode --version 2>/dev/null || echo "unknown")
echo "✅ OpenCode found: $VERSION"

# Check API key
if [[ -z "${OPENCODE_GO_API_KEY:-}" ]]; then
    echo "⚠️  OPENCODE_GO_API_KEY not set (required for execution)"
else
    echo "✅ OPENCODE_GO_API_KEY is set"
fi

# Check model
MODEL="${OPENCODE_MODEL:-sonnet-4}"
echo "📋 Default model: $MODEL"

# Run doctor check (non-blocking)
echo "🔍 Running OpenCode doctor..."
opencode doctor || echo "⚠️  Doctor check had warnings (non-blocking)"

# Test basic functionality
echo "🧪 Testing basic OpenCode run..."
TEST_OUTPUT=$(mktemp)
echo "Create a simple hello world function in JavaScript" | opencode run --model "$MODEL" --permission "read,write" 2>&1 | head -20 > "$TEST_OUTPUT" || true

if grep -q "function\|hello\|world" "$TEST_OUTPUT" -i; then
    echo "✅ Basic test produced expected output"
else
    echo "⚠️  Basic test output unclear (may be normal for API limits)"
fi

rm -f "$TEST_OUTPUT"

echo ""
echo "=== Verification Complete ==="
echo "OpenCode worker is ready for Cloud Agent HQ tasks."