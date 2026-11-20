#!/usr/bin/env bash
# Cloud Agent HQ — Concurrency Load Test
# Tests multiple parallel task dispatches

set -euo pipefail

HQ_REPO="Chimthuwu/Cloud-Agent-HQ"
TEST_REPO="Chimthuwu/GameVolley"
PARALLEL=${1:-3}

echo "=== Cloud Agent HQ Concurrency Test ==="
echo "Parallel tasks: $PARALLEL"
echo "HQ Repository: $HQ_REPO"
echo "Test Repository: $TEST_REPO"

# Generate multiple test tasks
TASKS=()
for i in $(seq 1 $PARALLEL); do
    TASK_ID="gamevolley-concurrent-${i}-$(date +%Y%m%d-%H%M%S)"
    cat > "/tmp/test-task-${i}.json" <<EOF
{
  "task_id": "$TASK_ID",
  "repository": "$TEST_REPO",
  "base_branch": "main",
  "instructions": "Create test file cloud-agent-concurrent-${i}.txt with content 'Concurrent test ${i} of $PARALLEL at $(date)'",
  "worker_profile": "opencode",
  "reviewer_profile": "different",
  "timeout_minutes": 10,
  "verification_commands": ["cat cloud-agent-concurrent-${i}.txt"],
  "priority": "normal",
  "labels": ["test", "concurrency", "batch-${i}"]
}
EOF
    TASKS+=("$TASK_ID")
    echo "📋 Task $i: $TASK_ID"
done

# Dispatch all tasks
echo ""
echo "🚀 Dispatching $PARALLEL tasks in parallel..."
for i in $(seq 1 $PARALLEL); do
    TASK_ID="${TASKS[$i-1]}"
    echo "  Dispatching $TASK_ID..."
    gh workflow run dispatch-task.yml \
      --repo "$HQ_REPO" \
      -f task_json="$(cat /tmp/test-task-${i}.json | jq -c .)" \
      -f task_id="$TASK_ID" \
      -f repository="$TEST_REPO" \
      -f worker_profile="opencode" \
      -f base_branch="main" \
      -f timeout_minutes="10" \
      -f tracking_issue="0" &
    # Small delay to avoid rate limiting
    sleep 1
done

wait
echo "✅ All dispatch workflows triggered"

# Monitor
echo ""
echo "📊 Monitor at: https://github.com/$HQ_REPO/actions"
echo "🔍 Check tracking issues at: https://github.com/$HQ_REPO/issues?q=label%3Acloud-agent-task"

# Wait for completion (simplified - in reality would poll)
echo ""
echo "⏳ Waiting for completions (check GitHub Actions)..."
echo "   Run: gh run list --repo $HQ_REPO --workflow=worker-opencode.yml --limit=$PARALLEL"

echo ""
echo "=== Concurrency Test Dispatched ==="
echo "Check GitHub Actions for results"