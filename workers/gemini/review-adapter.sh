#!/usr/bin/env bash
# Cloud Agent HQ — Gemini Review Adapter (placeholder)

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
  "reviewer_profile": "gemini",
  "decision": "comment",
  "summary": "Gemini review adapter not yet implemented",
  "findings": [
    {
      "severity": "info",
      "category": "documentation",
      "file": "",
      "line": 0,
      "message": "Review adapter is a placeholder",
      "suggestion": "Implement when Gemini CLI is verified"
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

echo "⚠️  Gemini review adapter not yet implemented"
exit 0