#!/usr/bin/env bash
# Cloud Agent HQ — Claude Code Review Adapter (placeholder)

set -euo pipefail

REPOSITORY="${1:-}"
PR_NUMBER="${2:-}"
REPORT_OUTPUT="${3:-}"

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$REPORT_OUTPUT" <<EOF
{
  "task_id": "",
  "pr_number": $PR_NUMBER,
  "reviewer_profile": "claude",
  "decision": "comment",
  "summary": "Claude Code review adapter not yet implemented",
  "findings": [
    {
      "severity": "info",
      "category": "documentation",
      "file": "",
      "line": 0,
      "message": "Review adapter is a placeholder",
      "suggestion": "Implement when Claude Code OAuth automation is ready"
    }
  ],
  "verification": {
    "build_passed": false,
    "tests_passed": false,
    "lint_passed": false,
    "typecheck_passed": false,
    "custom_checks": {}
  },
  "requires_human_review": true,
  "duration_seconds": 0,
  "reviewed_at": "$STARTED_AT"
}
EOF

echo "⚠️  Claude Code review adapter not yet implemented"
exit 0