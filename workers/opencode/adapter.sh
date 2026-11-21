#!/usr/bin/env bash
# Cloud Agent HQ — OpenCode Worker Adapter (minimal test)

set -euo pipefail

TASK_JSON_FILE="${1:-}"
WORKSPACE="${2:-}"
REPORT_OUTPUT="${3:-}"

if [[ -z "$TASK_JSON_FILE" || -z "$WORKSPACE" || -z "$REPORT_OUTPUT" ]]; then
    echo "Usage: $0 <task-json-file> <workspace-dir> <output-report-file>" >&2
    exit 1
fi

TASK_ID=$(jq -r '.task_id' "$TASK_JSON_FILE")
REPOSITORY=$(jq -r '.repository' "$TASK_JSON_FILE")
BASE_BRANCH=$(jq -r '.base_branch' "$TASK_JSON_FILE")
INSTRUCTIONS=$(jq -r '.instructions' "$TASK_JSON_FILE")
VERIFICATION_CMDS=$(jq -c '.verification_commands // []' "$TASK_JSON_FILE")
TOOL_PERMISSIONS=$(jq -c '.tool_permissions // ["read", "write", "edit", "bash", "grep", "glob"]' "$TASK_JSON_FILE")
ENV_VARS=$(jq -c '.environment_vars // {}' "$TASK_JSON_FILE")

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

REPORT_FILE="$REPORT_OUTPUT"
WORK_DIR="$WORKSPACE"
cd "$WORK_DIR"

report_init() {
    cat > "$REPORT_FILE" <<EOF
{
  "task_id": "$TASK_ID",
  "worker_profile": "opencode",
  "status": "running",
  "branch": "",
  "pr_number": 0,
  "pr_url": "",
  "summary": "",
  "changes": [],
  "verification_results": {"commands_run": [], "passed": [], "failed": [], "output": ""},
  "errors": [], "warnings": [],
  "duration_seconds": 0,
  "tokens_used": {"input": 0, "output": 0, "total": 0},
  "metadata": {},
  "started_at": "$STARTED_AT",
  "completed_at": ""
}
EOF
}

report_append_array() { jq --arg k "$1" --arg v "$2" '.[$k] += [$v]' "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"; }
report_update_string() { jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"; }

report_finalize() {
    local status="$1" summary="$2" branch="$3" pr_number="$4" pr_url="$5" changes_json="$6" verification_json="$7" errors_json="$8" warnings_json="$9" duration="${10}" tokens_json="${11}"
    local completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --arg task_id "$TASK_ID" --arg worker_profile "opencode" --arg status "$status" --arg branch "$branch" --argjson pr_number "$pr_number" --arg pr_url "$pr_url" --arg summary "$summary" --argjson changes "$changes_json" --argjson verification_results "$verification_json" --argjson errors "$errors_json" --argjson warnings "$warnings_json" --argjson duration_seconds "$duration" --argjson tokens_used "$tokens_json" --arg metadata "{}" --arg started_at "$STARTED_AT" --arg completed_at "$completed_at" \
      '{task_id: $task_id, worker_profile: $worker_profile, status: $status, branch: $branch, pr_number: $pr_number, pr_url: $pr_url, summary: $summary, changes: $changes, verification_results: $verification_results, errors: $errors, warnings: $warnings, duration_seconds: $duration_seconds, tokens_used: $tokens_used, metadata: ($metadata | fromjson), started_at: $started_at, completed_at: $completed_at}' > "$REPORT_FILE"
}

report_init
export OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY:-}"
export OPENCODE_MODEL="${OPENCODE_MODEL:-sonnet-4}"
echo "$ENV_VARS" | jq -r 'to_entries[] | "export \(.key)=\(.value)"' | while read -r line; do eval "$line"; done

echo "=== Starting OpenCode task: $TASK_ID ==="
echo "Repository: $REPOSITORY"
echo "Branch: $BASE_BRANCH"
echo "Workspace: $WORK_DIR"

OPENCODE_OUTPUT="/tmp/opencode-output-$TASK_ID.log"
OPENCODE_ERROR="/tmp/opencode-error-$TASK_ID.log"

set +e
# Test 1: Simplest possible command - no flags, just message
echo "TEST 1: opencode run \"hello\""
opencode run "hello" 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT1=${PIPESTATUS[0]}
echo "Exit code: $EXIT1"
cat "$OPENCODE_ERROR"
echo "---"

# Test 2: With model flag
echo "TEST 2: opencode run --model sonnet-4 \"hello\""
opencode run --model sonnet-4 "hello" 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT2=${PIPESTATUS[0]}
echo "Exit code: $EXIT2"
cat "$OPENCODE_ERROR"
echo "---"

# Test 3: With permission flag
echo "TEST 3: opencode run --model sonnet-4 --permission read,write \"hello\""
opencode run --model sonnet-4 --permission read,write "hello" 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT3=${PIPESTATUS[0]}
echo "Exit code: $EXIT3"
cat "$OPENCODE_ERROR"
echo "---"

# Test 4: Message first, then flags
echo "TEST 4: opencode run \"hello\" --model sonnet-4 --permission read,write"
opencode run "hello" --model sonnet-4 --permission read,write 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT4=${PIPESTATUS[0]}
echo "Exit code: $EXIT4"
cat "$OPENCODE_ERROR"
echo "---"

# Test 5: opencode (no subcommand) with --prompt
echo "TEST 5: opencode --prompt \"hello\" --model sonnet-4 --permission read,write"
opencode --prompt "hello" --model sonnet-4 --permission read,write 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT5=${PIPESTATUS[0]}
echo "Exit code: $EXIT5"
cat "$OPENCODE_ERROR"
echo "---"

# Test 6: opencode run with --format json
echo "TEST 6: opencode run --format json --model sonnet-4 --permission read,write \"hello\""
opencode run --format json --model sonnet-4 --permission read,write "hello" 2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
EXIT6=${PIPESTATUS[0]}
echo "Exit code: $EXIT6"
cat "$OPENCODE_ERROR"
echo "---"

set -e

# Use the first successful test
if [[ $EXIT1 -eq 0 ]]; then
    echo "Using TEST 1 method"
    METHOD=1
elif [[ $EXIT2 -eq 0 ]]; then
    echo "Using TEST 2 method"
    METHOD=2
elif [[ $EXIT3 -eq 0 ]]; then
    echo "Using TEST 3 method"
    METHOD=3
elif [[ $EXIT4 -eq 0 ]]; then
    echo "Using TEST 4 method"
    METHOD=4
elif [[ $EXIT5 -eq 0 ]]; then
    echo "Using TEST 5 method"
    METHOD=5
elif [[ $EXIT6 -eq 0 ]]; then
    echo "Using TEST 6 method"
    METHOD=6
else
    echo "All tests failed!"
    report_append_array "errors" "All OpenCode test methods failed"
    FINAL_STATUS="failed"
    SUMMARY="OpenCode CLI not working in this environment"
fi

# For now, just report test results
FINAL_STATUS="partial"
SUMMARY="OpenCode CLI tests completed. Exit codes: 1=$EXIT1, 2=$EXIT2, 3=$EXIT3, 4=$EXIT4, 5=$EXIT5, 6=$EXIT6"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOKENS_JSON='{"input": 0, "output": 0, "total": 0}'

CHANGES="[]"
VERIFICATION_JSON='{"commands_run": [], "passed": [], "failed": [], "output": ""}'

report_finalize "$FINAL_STATUS" "$SUMMARY" "" 0 "" "$CHANGES" "$VERIFICATION_JSON" "$(jq -n --argjson errors "$(cat "$REPORT_FILE" | jq -c '.errors')" '$errors')" "$(jq -n --argjson warnings "$(cat "$REPORT_FILE" | jq -c '.warnings')" '$warnings')" "$DURATION" "$TOKENS_JSON"

echo "=== Task $TASK_ID completed with status: $FINAL_STATUS ==="
echo "Duration: ${DURATION}s"
echo "Report written to: $REPORT_FILE"

exit 0