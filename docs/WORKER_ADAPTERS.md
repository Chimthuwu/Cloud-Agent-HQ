# Cloud Agent HQ — Worker Adapter Implementation Guide

**Version:** 1.0

---

## Overview

Worker adapters are the bridge between Cloud Agent HQ's common task contract and each coding CLI's unique interface. This guide documents the adapter interface contract and implementation patterns.

---

## Adapter Interface Contract

### Entry Point

Each worker adapter is a shell script at:
```
workers/<profile>/adapter.sh
```

### Invocation

```bash
./adapter.sh <task-json-file> <workspace-dir> <output-report-file>
```

### Arguments

| Arg | Description |
|-----|-------------|
| `$1` | Path to task contract JSON |
| `$2` | Repository workspace directory (already checked out) |
| `$3` | Path to write execution report JSON |

### Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `TASK_JSON` | Arg 1 | Task contract path |
| `WORKSPACE` | Arg 2 | Repo checkout directory |
| `REPORT_OUTPUT` | Arg 3 | Report output path |
| `GITHUB_TOKEN` | GitHub Actions | GitHub API token |
| `TARGET_REPO_PAT` | Repo secret | PAT for target repo push/PR |
| `<WORKER>_API_KEY` | Org secret | Worker-specific API key |
| `TASK_ID` | Task contract | Unique task identifier |
| `REPOSITORY` | Task contract | Target repository |
| `BASE_BRANCH` | Task contract | Base branch |
| `BRANCH_NAME` | GitHub Actions | Created working branch |

---

## Execution Report Schema

Adapters must write a JSON report matching `schemas/execution-report.json`:

```json
{
  "task_id": "string",
  "worker_profile": "opencode|codex|gemini|claude",
  "status": "success|partial|failed|timeout|cancelled",
  "branch": "string",
  "pr_number": 0,
  "pr_url": "string",
  "summary": "string",
  "changes": ["file1.js", "file2.ts"],
  "verification_results": {
    "commands_run": ["npm test"],
    "passed": ["npm test"],
    "failed": [],
    "output": "combined stdout/stderr"
  },
  "errors": ["error messages"],
  "warnings": ["warning messages"],
  "duration_seconds": 123,
  "tokens_used": {"input": 1000, "output": 2000, "total": 3000},
  "metadata": {},
  "started_at": "2026-11-21T14:30:00Z",
  "completed_at": "2026-11-21T14:35:00Z"
}
```

---

## Required Adapter Behavior

### 1. Parse Task Contract
```bash
TASK_ID=$(jq -r '.task_id' "$TASK_JSON_FILE")
INSTRUCTIONS=$(jq -r '.instructions' "$TASK_JSON_FILE")
VERIFICATION_CMDS=$(jq -c '.verification_commands // []' "$TASK_JSON_FILE")
```

### 2. Read Repository Instructions
Check for and read project instruction files:
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `TODO.md`, `docs/ARCHITECTURE.md`

### 3. Execute Worker CLI
Run the coding CLI with task instructions and appropriate permissions.

### 4. Run Verification Commands
Execute each command in `verification_commands`, capture results.

### 5. Commit Changes
```bash
git config user.name "cloud-agent[bot]"
git config user.email "cloud-agent@users.noreply.github.com"
git add -A
git commit -m "cloud-agent: $TASK_ID - <summary>"
```

### 6. Push Branch
```bash
git push origin "$BRANCH_NAME"
```

### 7. Create Pull Request
```bash
gh pr create --repo "$REPOSITORY" --base "$BASE_BRANCH" --head "$BRANCH_NAME" \
  --title "cloud-agent: $TASK_ID" --body "$PR_BODY"
```

### 8. Write Execution Report
Output JSON to `$REPORT_OUTPUT` matching schema.

---

## OpenCode Adapter Reference Implementation

See `workers/opencode/adapter.sh` for the reference implementation.

**Key patterns:**
- Uses `opencode run --instructions <file> --permission <perms>`
- Combines task instructions with repo context
- Streams output to log files
- Handles exit codes gracefully
- Creates PR with detailed body

---

## Adding a New Worker

1. **Create directory:** `workers/<profile>/`
2. **Add config:** `workers/<profile>/config.yaml`
3. **Implement adapter:** `workers/<profile>/adapter.sh`
4. **Add verify script:** `workers/<profile>/verify.sh`
5. **Create workflow:** `.github/workflows/worker-<profile>.yml`
6. **Register in:** `registry/workers.yaml`
7. **Add review adapter:** `workers/<profile>/review-adapter.sh`

### Config Template (`config.yaml`)
```yaml
model:
  default: "model-name"
  env_var: "WORKER_MODEL"
execution:
  timeout_minutes: 30
  max_retries: 1
permissions:
  default: ["read", "write", "edit", "bash"]
git:
  author_name: "cloud-agent[bot]"
  author_email: "cloud-agent@users.noreply.github.com"
```

### Workflow Template
```yaml
name: Worker - <Profile>
on:
  workflow_dispatch:
    inputs:
      task_json: {required: true, type: string}
      task_id: {required: true, type: string}
      repository: {required: true, type: string}
      base_branch: {required: true, type: string, default: "main"}
      timeout_minutes: {required: true, type: string, default: "30"}
      tracking_issue: {required: true, type: string}
permissions:
  contents: read
jobs:
  execute:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ github.event.inputs.timeout_minutes }}
    env:
      TASK_ID: ${{ github.event.inputs.task_id }}
      REPOSITORY: ${{ github.event.inputs.repository }}
      BASE_BRANCH: ${{ github.event.inputs.base_branch }}
      TRACKING_ISSUE: ${{ github.event.inputs.tracking_issue }}
      WORKER_API_KEY: ${{ secrets.WORKER_API_KEY }}
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      TARGET_REPO_PAT: ${{ secrets.CLOUD_AGENT_HQ_PAT }}
    steps:
      - uses: actions/checkout@v4
        with: {path: cloud-agent-hq}
      - name: Write task JSON
        run: echo '${{ github.event.inputs.task_json }}' > task.json
      - name: Setup & install CLI
        run: |
          # Install worker CLI
      - name: Checkout target repo
        uses: actions/checkout@v4
        with:
          repository: ${{ github.event.inputs.repository }}
          ref: ${{ github.event.inputs.base_branch }}
          token: ${{ secrets.CLOUD_AGENT_HQ_PAT }}
          path: target-repo
      - name: Create branch & run adapter
        working-directory: target-repo
        run: |
          BRANCH_NAME="cloud-agent/${{ github.event.inputs.task_id }}/<profile>"
          git checkout -b "$BRANCH_NAME"
          bash ../cloud-agent-hq/workers/<profile>/adapter.sh ../task.json . ../execution-report.json
      - name: Handle results
        # ... update tracking issue, upload artifact
concurrency:
  group: cloud-agent-<profile>-${{ github.event.inputs.task_id }}
  cancel-in-progress: false
```

---

## Authentication Patterns

| Worker | Method | CI Automation |
|--------|--------|---------------|
| OpenCode | API Key (`OPENCODE_GO_API_KEY`) | ✅ Ready |
| Codex | Device Code OAuth | ⚠️ Needs automation |
| Gemini | API Key (`GOOGLE_API_KEY`) | ✅ Ready (when CLI installed) |
| Claude Code | OAuth (`ANTHROPIC_API_KEY`) | ⚠️ Needs automation |

**For CI-ready workers:** Store API key in GitHub Organization secrets.

**For OAuth workers:** Need to implement device-code flow automation or use service accounts.

---

## Testing Adapters

### Local Testing
```bash
# Create test task
cat > test-task.json <<'EOF'
{
  "task_id": "test-001-20261121-120000",
  "repository": "Chimthuwu/GameVolley",
  "base_branch": "main",
  "instructions": "Create a simple test file test-output.txt with content 'Hello from OpenCode'",
  "worker_profile": "opencode",
  "verification_commands": ["cat test-output.txt"]
}
EOF

# Run adapter locally
mkdir -p test-workspace
cd test-workspace
git clone https://github.com/Chimthuwu/GameVolley .
../workers/opencode/adapter.sh ../test-task.json . ../execution-report.json

# Check report
cat ../execution-report.json | jq .
```

### CI Testing
Use `tests/mock-worker.sh` for infrastructure tests without real AI calls.

---

## Best Practices

1. **Always read repo instructions first** - AGENTS.md, CLAUDE.md, etc.
2. **Use unique branch names** - `cloud-agent/<task-id>/<worker>`
3. **Conventional commits** - `cloud-agent: <task-id> - <summary>`
4. **Detailed PR bodies** - Include task ID, summary, changes, verification
5. **Handle failures gracefully** - Write report even on failure
6. **Respect timeouts** - Check `timeout_minutes` from task
7. **Log extensively** - GitHub Actions logs are primary debugging tool
8. **Never expose secrets** - Use env vars, never echo them