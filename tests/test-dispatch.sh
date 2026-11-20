#!/usr/bin/env bash
# Cloud Agent HQ — Dispatch Integration Test
# Tests the dispatch workflow end-to-end with mock worker

set -euo pipefail

HQ_REPO="Chimthuwu/Cloud-Agent-HQ"
TEST_REPO="Chimthuwu/GameVolley"

echo "=== Cloud Agent HQ Dispatch Integration Test ==="
echo "HQ Repository: $HQ_REPO"
echo "Test Repository: $TEST_REPO"

# Check prerequisites
for cmd in gh jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd not found"
        exit 1
    fi
done
echo "✅ Prerequisites met"

# Generate test task
TASK_ID="gamevolley-test-$(date +%Y%m%d-%H%M%S)"
cat > /tmp/test-task.json <<EOF
{
  "task_id": "$TASK_ID",
  "repository": "$TEST_REPO",
  "base_branch": "main",
  "instructions": "Create a test file cloud-agent-test-$TASK_ID.txt with content 'Hello from Cloud Agent HQ test at $(date)'",
  "worker_profile": "opencode",
  "reviewer_profile": "different",
  "timeout_minutes": 10,
  "verification_commands": ["cat cloud-agent-test-$TASK_ID.txt"],
  "priority": "normal",
  "labels": ["test", "integration"]
}
EOF

echo "📋 Test task created: $TASK_ID"
cat /tmp/test-task.json | jq .

# Option 1: Trigger via workflow_dispatch (requires gh auth)
echo ""
echo "🚀 Triggering dispatch workflow..."
gh workflow run dispatch-task.yml \
  --repo "$HQ_REPO" \
  -f task_json="$(cat /tmp/test-task.json | jq -c .)" \
  -f task_id="$TASK_ID" \
  -f repository="$TEST_REPO" \
  -f worker_profile="opencode" \
  -f base_branch="main" \
  -f timeout_minutes="10" \
  -f tracking_issue="0"

echo "✅ Dispatch workflow triggered"
echo "📊 Monitor at: https://github.com/$HQ_REPO/actions"

# Wait for workflow to start
echo "⏳ Waiting for workflow to start..."
sleep 10

# Find the workflow run
RUN_ID=$(gh run list --repo "$HQ_REPO" --workflow=dispatch-task.yml --limit=1 --json databaseId --jq '.[0].databaseId')
echo "🔍 Workflow run ID: $RUN_ID"

# Watch the run
echo "👀 Watching workflow (timeout 5 min)..."
gh run watch "$RUN_ID" --repo "$HQ_REPO" --timeout=300 || true

# Check results
echo ""
echo "📋 Checking tracking issue..."
gh issue list --repo "$HQ_REPO" --label "cloud-agent-task" --search "$TASK_ID" --json number,title,state,labels,body --jq '.[] | select(.title | contains("'$TASK_ID'"))'

echo ""
echo "=== Integration Test Complete ==="
echo "Check GitHub Actions for full results"