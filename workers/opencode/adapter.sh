#!/usr/bin/env bash
# Cloud Agent HQ — OpenCode Worker Adapter
# Entry point for OpenCode worker execution in GitHub Actions
#
# Usage: ./adapter.sh <task-json-file> <workspace-dir> <output-report-file>
#
# Environment variables:
#   TASK_JSON          - Path to task contract JSON (arg 1)
#   WORKSPACE          - Repository checkout directory (arg 2)
#   REPORT_OUTPUT      - Path to write execution report (arg 3)
#   GITHUB_TOKEN       - GitHub token for API access
#   TARGET_REPO_PAT    - PAT for target repository push/PR
#   OPENCODE_GO_API_KEY - OpenCode API key
#   OPENCODE_MODEL     - OpenCode model to use
#   TASK_ID            - Task identifier
#   REPOSITORY         - Target repository (owner/name)
#   BASE_BRANCH        - Base branch
#   BRANCH_NAME        - Working branch name

set -euo pipefail

# Parse arguments
TASK_JSON_FILE="${1:-}"
WORKSPACE="${2:-}"
REPORT_OUTPUT="${3:-}"

if [[ -z "$TASK_JSON_FILE" || -z "$WORKSPACE" || -z "$REPORT_OUTPUT" ]]; then
    echo "Usage: $0 <task-json-file> <workspace-dir> <output-report-file>" >&2
    exit 1
fi

# Load task details
TASK_ID=$(jq -r '.task_id' "$TASK_JSON_FILE")
REPOSITORY=$(jq -r '.repository' "$TASK_JSON_FILE")
BASE_BRANCH=$(jq -r '.base_branch' "$TASK_JSON_FILE")
INSTRUCTIONS=$(jq -r '.instructions' "$TASK_JSON_FILE")
VERIFICATION_CMDS=$(jq -c '.verification_commands // []' "$TASK_JSON_FILE")
TOOL_PERMISSIONS=$(jq -c '.tool_permissions // ["read", "write", "edit", "bash", "grep", "glob"]' "$TASK_JSON_FILE")
ENV_VARS=$(jq -c '.environment_vars // {}' "$TASK_JSON_FILE")

# Start timing
START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize report
REPORT_FILE="$REPORT_OUTPUT"
WORK_DIR="$WORKSPACE"
cd "$WORK_DIR"

# Helper: append to report
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
  "verification_results": {
    "commands_run": [],
    "passed": [],
    "failed": [],
    "output": ""
  },
  "errors": [],
  "warnings": [],
  "duration_seconds": 0,
  "tokens_used": {
    "input": 0,
    "output": 0,
    "total": 0
  },
  "metadata": {},
  "started_at": "$STARTED_AT",
  "completed_at": ""
}
EOF
}

report_update() {
    local key="$1"
    local value="$2"
    jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
}

report_update_string() {
    local key="$1"
    local value="$2"
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
}

report_append_array() {
    local key="$1"
    local value="$2"
    jq --arg k "$key" --arg v "$value" '.[$k] += [$v]' "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
}

report_finalize() {
    local status="$1"
    local summary="$2"
    local branch="$3"
    local pr_number="$4"
    local pr_url="$5"
    local changes_json="$6"
    local verification_json="$7"
    local errors_json="$8"
    local warnings_json="$9"
    local duration="${10}"
    local tokens_json="${11}"
    local completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq -n \
      --arg task_id "$TASK_ID" \
      --arg worker_profile "opencode" \
      --arg status "$status" \
      --arg branch "$branch" \
      --argjson pr_number "$pr_number" \
      --arg pr_url "$pr_url" \
      --arg summary "$summary" \
      --argjson changes "$changes_json" \
      --argjson verification_results "$verification_json" \
      --argjson errors "$errors_json" \
      --argjson warnings "$warnings_json" \
      --argjson duration_seconds "$duration" \
      --argjson tokens_used "$tokens_json" \
      --arg metadata "{}" \
      --arg started_at "$STARTED_AT" \
      --arg completed_at "$completed_at" \
      '{
        task_id: $task_id,
        worker_profile: $worker_profile,
        status: $status,
        branch: $branch,
        pr_number: $pr_number,
        pr_url: $pr_url,
        summary: $summary,
        changes: $changes,
        verification_results: $verification_results,
        errors: $errors,
        warnings: $warnings,
        duration_seconds: $duration_seconds,
        tokens_used: $tokens_used,
        metadata: ($metadata | fromjson),
        started_at: $started_at,
        completed_at: $completed_at
      }' > "$REPORT_FILE"
}

# Initialize report
report_init

# Export environment variables for OpenCode
export OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY:-}"
export OPENCODE_MODEL="${OPENCODE_MODEL:-sonnet-4}"

# Apply additional environment variables from task
echo "$ENV_VARS" | jq -r 'to_entries[] | "export \(.key)=\(.value)"' | while read -r line; do
    eval "$line"
done

# Prepare instructions for OpenCode
# Combine task instructions with repository context
FULL_INSTRUCTIONS="$INSTRUCTIONS"

# Add repo-specific context if available
if [[ -f "AGENTS.md" ]]; then
    FULL_INSTRUCTIONS+="\n\n--- REPOSITORY AGENTS.md ---\n$(cat AGENTS.md)"
fi
if [[ -f "CLAUDE.md" ]]; then
    FULL_INSTRUCTIONS+="\n\n--- REPOSITORY CLAUDE.md ---\n$(cat CLAUDE.md)"
fi
if [[ -f "README.md" ]]; then
    FULL_INSTRUCTIONS+="\n\n--- REPOSITORY README.md ---\n$(cat README.md)"
fi
if [[ -f "TODO.md" ]]; then
    FULL_INSTRUCTIONS+="\n\n--- REPOSITORY TODO.md ---\n$(cat TODO.md)"
fi

# Write instructions to a file to avoid command-line argument issues
INSTRUCTIONS_FILE="/tmp/opencode-instructions-$TASK_ID.txt"
echo -e "$FULL_INSTRUCTIONS" > "$INSTRUCTIONS_FILE"

echo "=== Starting OpenCode task: $TASK_ID ==="
echo "Repository: $REPOSITORY"
echo "Branch: $BASE_BRANCH"
echo "Workspace: $WORK_DIR"
echo "Instructions file: $INSTRUCTIONS_FILE"

# Build OpenCode command
# OpenCode CLI usage: opencode run [flags] [<message...>]
# We'll pass the instructions file as the message by reading it
# Since message is variadic, we need to pass it as a single argument
# Use cat to read the file and pass as argument

OPENCODE_OUTPUT="/tmp/opencode-output-$TASK_ID.log"
OPENCODE_ERROR="/tmp/opencode-error-$TASK_ID.log"

# Build OpenCode command
PERMS_ARG=$(echo "$TOOL_PERMISSIONS" | jq -r 'join(",")')

set +e
# Read instructions file content and pass as single argument
INSTRUCTIONS_CONTENT=$(cat "$INSTRUCTIONS_FILE")
opencode run \
    --model "$OPENCODE_MODEL" \
    --permission "$PERMS_ARG" \
    "$INSTRUCTIONS_CONTENT" \
    2>"$OPENCODE_ERROR" | tee "$OPENCODE_OUTPUT"
OPENCODE_EXIT=${PIPESTATUS[0]}
set -e

# Check OpenCode exit code
if [[ $OPENCODE_EXIT -ne 0 ]]; then
    echo "OpenCode exited with code $OPENCODE_EXIT"
    ERROR_OUTPUT=$(cat "$OPENCODE_ERROR")
    report_append_array "errors" "OpenCode execution failed: $ERROR_OUTPUT"
fi

# Collect changed files
CHANGES=$(git status --porcelain | awk '{print $2}' | jq -R . | jq -s .)
CHANGES_ARRAY=$(echo "$CHANGES" | jq -c '.')

# Run verification commands
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

# Determine overall status
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

# Commit and push changes if any
PR_NUMBER=0
PR_URL=""
BRANCH_NAME=""

if [[ "$CHANGES" != "[]" ]]; then
    # Get current branch name
    BRANCH_NAME=$(git branch --show-current)
    
    # Commit changes
    git add -A
    git commit -m "cloud-agent: $TASK_ID - $SUMMARY

Automated implementation by Cloud Agent HQ (OpenCode worker)

Task: $TASK_ID
Repository: $REPOSITORY
Worker: opencode
Model: $OPENCODE_MODEL

Changes:
$(git diff --name-only HEAD~1 | sed 's/^/- /')

Verification: ${#VERIFICATION_PASSED[@]} passed, ${#VERIFICATION_FAILED[@]} failed"
    
    # Push branch
    git push origin "$BRANCH_NAME" 2>&1 | tee -a "$OPENCODE_OUTPUT"
    
    # Create Pull Request using GitHub CLI
    PR_BODY="## Cloud Agent Task: $TASK_ID

**Repository:** $REPOSITORY
**Worker:** OpenCode
**Model:** $OPENCODE_MODEL
**Base Branch:** $BASE_BRANCH
**Branch:** \`$BRANCH_NAME\`
**Status:** $FINAL_STATUS

### Summary
$SUMMARY

### Changes
$(git diff --name-only HEAD~1 | sed 's/^/- /')

### Verification Results
$(printf '%s\n' "${VERIFICATION_PASSED[@]}" | sed 's/^/- ✅ /')
$(printf '%s\n' "${VERIFICATION_FAILED[@]}" | sed 's/^/- ❌ /')

### Instructions Executed
$INSTRUCTIONS

---
*Generated by Cloud Agent HQ - OpenCode worker*"
    
    PR_OUTPUT=$(gh pr create \
        --repo "$REPOSITORY" \
        --base "$BASE_BRANCH" \
        --head "$BRANCH_NAME" \
        --title "cloud-agent: $TASK_ID" \
        --body "$PR_BODY" \
        2>&1)
    
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

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Finalize report
TOKENS_JSON='{"input": 0, "output": 0, "total": 0}'  # OpenCode doesn't expose token counts easily

report_finalize \
    "$FINAL_STATUS" \
    "$SUMMARY" \
    "$BRANCH_NAME" \
    "$PR_NUMBER" \
    "$PR_URL" \
    "$CHANGES_ARRAY" \
    "$(jq -n --argjson passed "$(echo "${VERIFICATION_PASSED[@]}" | jq -R . | jq -s .)" --argjson failed "$(echo "${VERIFICATION_FAILED[@]}" | jq -R . | jq -s .)" --arg output "$VERIFICATION_OUTPUT" '{commands_run: $passed + $failed, passed: $passed, failed: $failed, output: $output}')" \
    "$(jq -n --argjson errors "$(cat "$REPORT_FILE" | jq -c '.errors')" '$errors')" \
    "$(jq -n --argjson warnings "$(cat "$REPORT_FILE" | jq -c '.warnings')" '$warnings')" \
    "$DURATION" \
    "$TOKENS_JSON"

echo "=== Task $TASK_ID completed with status: $FINAL_STATUS ==="
echo "Duration: ${DURATION}s"
echo "Report written to: $REPORT_FILE"

# Exit with appropriate code for GitHub Actions
if [[ "$FINAL_STATUS" == "success" ]]; then
    exit 0
elif [[ "$FINAL_STATUS" == "partial" ]]; then
    exit 0  # Partial success still counts as completed
else
    exit 1
fi