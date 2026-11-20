#!/usr/bin/env bash
# Cloud Agent HQ — OpenCode Review Adapter
# Performs independent code review of a PR using OpenCode

set -euo pipefail

REPOSITORY="${1:-}"
PR_NUMBER="${2:-}"
REPORT_OUTPUT="${3:-}"

if [[ -z "$REPOSITORY" || -z "$PR_NUMBER" || -z "$REPORT_OUTPUT" ]]; then
    echo "Usage: $0 <repository> <pr-number> <output-report-file>" >&2
    exit 1
fi

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize report
cat > "$REPORT_OUTPUT" <<EOF
{
  "task_id": "",
  "pr_number": $PR_NUMBER,
  "reviewer_profile": "opencode",
  "decision": "comment",
  "summary": "OpenCode review adapter not yet fully implemented",
  "findings": [
    {
      "severity": "info",
      "category": "documentation",
      "file": "",
      "line": 0,
      "message": "Review adapter is a placeholder - implement automated review with OpenCode",
      "suggestion": "Run OpenCode with review-focused instructions on PR diff"
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

echo "⚠️  OpenCode review adapter is a placeholder"
echo "   Implement: Fetch PR diff, run OpenCode with review instructions, parse output"
exit 0