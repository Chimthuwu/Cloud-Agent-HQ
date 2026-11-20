#!/usr/bin/env bash
# Cloud Agent HQ — Claude Code Worker Adapter
# Placeholder adapter - needs Claude Code installation and OAuth automation

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

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cd "$WORKSPACE"

cat > "$REPORT_OUTPUT" <<EOF
{
  "task_id": "$TASK_ID",
  "worker_profile": "claude",
  "status": "failed",
  "branch": "",
  "pr_number": 0,
  "pr_url": "",
  "summary": "Claude Code adapter not yet implemented - requires OAuth automation for headless CI",
  "changes": [],
  "verification_results": {
    "commands_run": [],
    "passed": [],
    "failed": [],
    "output": ""
  },
  "errors": ["Claude Code requires OAuth automation not yet implemented for headless CI"],
  "warnings": [],
  "duration_seconds": 0,
  "tokens_used": {"input": 0, "output": 0, "total": 0},
  "metadata": {},
  "started_at": "$STARTED_AT",
  "completed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "❌ Claude Code worker not yet implemented"
echo "   Requires: Anthropic OAuth automation for headless CI"
exit 1