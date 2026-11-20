#!/usr/bin/env bash
# Cloud Agent HQ — Mock Worker Adapter
# For infrastructure testing without real AI calls

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

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cd "$WORKSPACE"

echo "=== Mock Worker: $TASK_ID ==="
echo "Repository: $REPOSITORY"
echo "Instructions: ${INSTRUCTIONS:0:80}..."

# Simulate work
sleep 2

# Create a test file to show changes
TEST_FILE="cloud-agent-test-${TASK_ID}.txt"
cat > "$TEST_FILE" <<EOF
Mock worker test output for task: $TASK_ID
Repository: $REPOSITORY
Instructions: $INSTRUCTIONS
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
This file was created by the mock worker to simulate changes.
EOF

# Run verification commands (mock)
VERIFICATION_PASSED=()
VERIFICATION_FAILED=()
VERIFICATION_OUTPUT=""

for cmd in $(echo "$VERIFICATION_CMDS" | jq -r '.[]'); do
    echo "Mock verification: $cmd"
    if [[ "$cmd" == *"fail"* ]]; then
        VERIFICATION_FAILED+=("$cmd")
        VERIFICATION_OUTPUT+="\n❌ $cmd (mock failure)"
    else
        VERIFICATION_PASSED+=("$cmd")
        VERIFICATION_OUTPUT+="\n✅ $cmd (mock success)"
    fi
done

# Collect changes
CHANGES=$(git status --porcelain | awk '{print $2}' | jq -R . | jq -s .)

# Determine status
if [[ ${#VERIFICATION_FAILED[@]} -gt 0 ]]; then
    FINAL_STATUS="partial"
    SUMMARY="Mock worker completed but ${#VERIFICATION_FAILED[@]} verification(s) failed"
else
    FINAL_STATUS="success"
    SUMMARY="Mock worker completed successfully"
fi

# Commit and push
BRANCH_NAME=$(git branch --show-current)
PR_NUMBER=0
PR_URL=""

if [[ "$CHANGES" != "[]" ]]; then
    git add -A
    git commit -m "cloud-agent: $TASK_ID - $SUMMARY (MOCK)

Automated mock implementation by Cloud Agent HQ

Task: $TASK_ID
Worker: mock
Changes: $(echo "$CHANGES" | jq -r '.[]' | tr '\n' ' ')

Verification: ${#VERIFICATION_PASSED[@]} passed, ${#VERIFICATION_FAILED[@]} failed" || true
    
    # Don't actually push in mock mode
    echo "Mock: Would push branch $BRANCH_NAME and create PR"
    PR_NUMBER=999
    PR_URL="https://github.com/$REPOSITORY/pull/999"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Write report
cat > "$REPORT_OUTPUT" <<EOF
{
  "task_id": "$TASK_ID",
  "worker_profile": "mock",
  "status": "$FINAL_STATUS",
  "branch": "$BRANCH_NAME",
  "pr_number": $PR_NUMBER,
  "pr_url": "$PR_URL",
  "summary": "$SUMMARY",
  "changes": $CHANGES,
  "verification_results": {
    "commands_run": $(echo "${VERIFICATION_PASSED[@]} ${VERIFICATION_FAILED[@]}" | jq -R . | jq -s .),
    "passed": $(echo "${VERIFICATION_PASSED[@]}" | jq -R . | jq -s .),
    "failed": $(echo "${VERIFICATION_FAILED[@]}" | jq -R . | jq -s .),
    "output": "$VERIFICATION_OUTPUT"
  },
  "errors": [],
  "warnings": ["This is a mock worker - no real AI execution"],
  "duration_seconds": $DURATION,
  "tokens_used": {"input": 0, "output": 0, "total": 0},
  "metadata": {"mock": true},
  "started_at": "$STARTED_AT",
  "completed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "=== Mock Worker Complete: $FINAL_STATUS ==="
echo "Report: $REPORT_OUTPUT"

# Exit appropriately
if [[ "$FINAL_STATUS" == "success" ]]; then
    exit 0
else
    exit 0  # Partial still exits 0 for infrastructure test
fi