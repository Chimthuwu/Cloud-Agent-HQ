#!/usr/bin/env bash
# Cloud Agent HQ — OpenCode Worker Adapter
# Entry point for OpenCode worker execution in GitHub Actions

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

FULL_INSTRUCTIONS="$INSTRUCTIONS"
[[ -f "AGENTS.md" ]] && FULL_INSTRUCTIONS+="\n\n--- REPOSITORY AGENTS.md ---\n$(cat AGENTS.md)"
[[ -f "CLAUDE.md" ]] && FULL_INSTRUCTIONS+="\n\n--- REPOSITORY CLAUDE.md ---\n$(cat CLAUDE.md)"
[[ -f "README.md" ]] && FULL_INSTRUCTIONS+="\n\n--- REPOSITORY README.md ---\n$(cat README.md)"
[[ -f "TODO.md" ]] && FULL_INSTRUCTIONS+="\n\n--- REPOSITORY TODO.md ---\n$(cat TODO.md)"

INSTRUCTIONS_FILE="/tmp/opencode-instructions-$TASK_ID.txt"
echo -e "$FULL_INSTRUCTIONS" > "$INSTRUCTIONS_FILE"

echo "=== Starting OpenCode task: $TASK_ID ==="
echo "Repository: $REPOSITORY"
echo "Branch: $BASE_BRANCH"
echo "Workspace: $WORK_DIR"
echo "Instructions: ${#FULL_INSTRUCTIONS} chars"

OPENCODE_OUTPUT="/tmp/opencode-output-$TASK_ID.log"
OPENCODE_ERROR="/tmp/opencode-error-$TASK_ID.log"
PERMS_ARG=$(echo "$TOOL_PERMISSIONS" | jq -r 'join(",")')

set +e
# Try piping message via stdin to opencode run
cat "$INSTRUCTIONS_FILE" | opencode run \
    --model "$OPENCODE_MODEL" \
    --permission "$PERMS_ARG" \
    2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
OPENCODE_EXIT=${PIPESTATUS[0]}
set -e

echo "DEBUG: OpenCode exit code: $OPENCODE_EXIT"
if [[ -f "$OPENCODE_ERROR" ]]; then
    echo "DEBUG: stderr output:"
    cat "$OPENCODE_ERROR"
fi
if [[ -f "$OPENCODE_OUTPUT" ]]; then
    echo "DEBUG: stdout output (first 500 chars):"
    head -c 500 "$OPENCODE_OUTPUT"
    echo "..."
fi

if [[ $OPENCODE_EXIT -ne 0 ]]; then
    ERROR_OUTPUT=$(cat "$OPENCODE_ERROR" 2>/dev/null || echo "No stderr")
    report_append_array "errors" "OpenCode execution failed: $ERROR_OUTPUT"
fi

CHANGES=$(git status --porcelain | awk '{print $2}' | jq -R . | jq -s .)
CHANGES_ARRAY=$(echo "$CHANGES" | jq -c '.')

VERIFICATION_PASSED=()
VERIFICATION_FAILED=()
VERIFICATION_OUTPUT=""

for cmd in $(echo "$VERIFICATION_CMDS" | jq -r '.[]'); do
    echo "Running verification: $cmd"
    report_append_array "verification_results.commands_run" "$cmd"
    if eval "$cmd" >>"$OPENCODE_OUTPUT" 2>&1; then
        VERIFICATION_PASSED+=("$cmd")
        report_append_array "verification_results.passed" "$cmd"
        VERIFICATION_OUTPUT+="\n✅ $cmd"
    else
        VERIFICATION_FAILED+=("$cmd")
        report_append_array "verification_results.failed" "$cmd"
        VERIFICATION_OUTPUT+="\n❌ $cmd"
    fi
done

report_update_string "verification_results.output" "$VERIFICATION_OUTPUT"

if [[ $OPENCODE_EXIT -ne 0 ]]; then
    FINAL_STATUS="failed"
    SUMMARY="OpenCode execution failed with exit code $OPENCODE_EXIT"
elif [[ ${#VERIFICATION_FAILED[@]} -gt 0 ]]; then
    FINAL_STATUS="partial"
    SUMMARY="OpenCode completed but ${#VERIFICATION_FAILED[@]} verification command(s) failed"
else
    FINAL_STATUS="success"
    SUMMARY="Task completed successfully with all verifications passing"
fi

PR_NUMBER=0; PR_URL=""; BRANCH_NAME=""
if [[ "$CHANGES" != "[]" ]]; then
    BRANCH_NAME=$(git branch --show-current)
    git add -A
    git commit -m "cloud-agent: $TASK_ID - $SUMMARY\n\nAutomated implementation by Cloud Agent HQ (OpenCode worker)\n\nTask: $TASK_ID\nRepository: $REPOSITORY\nWorker: opencode\nModel: $OPENCODE_MODEL\n\nChanges:\n$(git diff --name-only HEAD~1 | sed 's/^/- /')\n\nVerification: ${#VERIFICATION_PASSED[@]} passed, ${#VERIFICATION_FAILED[@]} failed"
    git push origin "$BRANCH_NAME" 2>&1 | tee -a "$OPENCODE_OUTPUT"
    
    PR_BODY="## Cloud Agent Task: $TASK_ID\n\n**Repository:** $REPOSITORY\n**Worker:** OpenCode\n**Model:** $OPENCODE_MODEL\n**Base Branch:** $BASE_BRANCH\n**Branch:** \`$BRANCH_NAME\`\n**Status:** $FINAL_STATUS\n\n### Summary\n$SUMMARY\n\n### Changes\n$(git diff --name-only HEAD~1 | sed 's/^/- /')\n\n### Verification Results\n$(printf '%s\n' "${VERIFICATION_PASSED[@]}" | sed 's/^/- ✅ /')\n$(printf '%s\n' "${VERIFICATION_FAILED[@]}" | sed 's/^/- ❌ /')\n\n### Instructions Executed\n$INSTRUCTIONS\n\n---\n*Generated by Cloud Agent HQ - OpenCode worker*"
    
    PR_OUTPUT=$(gh pr create --repo "$REPOSITORY" --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "cloud-agent: $TASK_ID" --body "$PR_BODY" 2>&1)
    if [[ $? -eq 0 ]]; then
        PR_URL=$(echo "$PR_OUTPUT" | grep -o 'https://github.com/[^ ]*')
        PR_NUMBER=$(echo "$PR_URL" | grep -o '[0-9]*$')
        echo "Created PR: $PR_URL (#$PR_NUMBER)"
    else
        echo "Failed to create PR: $PR_OUTPUT"
        report_append_array "errors" "PR creation failed: $PR_OUTPUT"
        FINAL_STATUS="failed"
    fi
else
    SUMMARY="No changes made - $SUMMARY"
    FINAL_STATUS="partial"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOKENS_JSON='{"input": 0, "output": 0, "total": 0}'

report_finalize "$FINAL_STATUS" "$SUMMARY" "$BRANCH_NAME" "$PR_NUMBER" "$PR_URL" "$CHANGES_ARRAY" "$(jq -n --argjson passed "$(echo "${VERIFICATION_PASSED[@]}" | jq -R . | jq -s .)" --argjson failed "$(echo "${VERIFICATION_FAILED[@]}" | jq -R . | jq -s .)" --arg output "$VERIFICATION_OUTPUT" '{commands_run: $passed + $failed, passed: $passed, failed: $failed, output: $output}')" "$(jq -n --argjson errors "$(cat "$REPORT_FILE" | jq -c '.errors')" '$errors')" "$(jq -n --argjson warnings "$(cat "$REPORT_FILE" | jq -c '.warnings')" '$warnings')" "$DURATION" "$TOKENS_JSON"

echo "=== Task $TASK_ID completed with status: $FINAL_STATUS ==="
echo "Duration: ${DURATION}s"
echo "Report written to: $REPORT_FILE"

if [[ "$FINAL_STATUS" == "success" ]]; then exit 0; elif [[ "$FINAL_STATUS" == "partial" ]]; then exit 0; else exit 1; fi