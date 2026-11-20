# Cloud Agent HQ — Hermes Integration

**Version:** 1.0

---

## Overview

This document describes how Hermes integrates with Cloud Agent HQ for cloud-based task dispatch and orchestration.

---

## Installation

### 1. Install Skill
```bash
# Copy skill to Hermes skills directory
cp -r cloud-agent-hq ~/.hermes/skills/

# Or use Hermes skill management
/hermes skill install cloud-agent-hq
```

### 2. Install Python Dependencies
```bash
pip install pyyaml jsonschema
```

### 3. Verify Installation
```
/cloud list-workers
```
Should show 4 worker profiles (opencode, codex, gemini, claude).

---

## Slash Commands

All commands are prefixed with `/cloud` (or configured alias).

### Dispatch Single Task
```
/cloud dispatch <repository> <instructions> [options]
```

**Options:**
| Flag | Description | Default |
|------|-------------|---------|
| `--worker` | Worker profile | `opencode` |
| `--branch` | Base branch | `main` |
| `--reviewer` | Reviewer profile | `different` |
| `--timeout` | Timeout minutes | `30` |
| `--verify` | Verification commands | `[]` |
| `--priority` | Task priority | `normal` |
| `--label` | GitHub labels | `[]` |
| `--env` | Environment variables | `{}`
| `--dry-run` | Validate only | `false` |

**Examples:**
```
/cloud dispatch Chimthuwu/GameVolley "Fix loading screen bug in src/loading.js"
/cloud dispatch Chimthuwu/GameVolley "Add unit tests" --worker codex --reviewer human
/cloud dispatch Chimthuwu/GameVolley "Refactor preview" --verify "npm test" "npm run lint" --priority high
```

### Dispatch Batch Tasks
```
/cloud batch <tasks-file.json> [--parallel 3]
```

**Task file format:** Array of task objects (see TASK_CONTRACT.md)

### Check Task Status
```
/cloud status <task-id>
```
Shows tracking issue, state, labels, last update.

### List Workers
```
/cloud list-workers
```
Shows all registered worker profiles with capabilities.

### View Logs
```
/cloud logs <task-id>
```
Opens GitHub Actions run URL for the task.

### Retry Failed Task
```
/cloud retry <task-id> [--worker opencode]
```
Re-dispatches the same task (optionally with different worker).

### Cancel Running Task
```
/cloud cancel <task-id>
```
Cancels the GitHub Actions workflow run.

### Register Repository
```
/register-repo <owner/repo> [options]
```

**Options:**
| Flag | Description | Default |
|------|-------------|---------|
| `--visibility` | `public` or `private` | Required |
| `--branch` | Default branch | `main` |
| `--workers` | Comma-separated worker list | `opencode,codex,gemini,claude` |
| `--notes` | Description | `""` |

**Examples:**
```
/register-repo Chimthuwu/NewProject --public
/register-repo Chimthuwu/PrivateBot --private --workers opencode --notes "Internal tool"
```

---

## Configuration

### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `CLOUD_AGENT_HQ_REPO` | HQ repository | `Chimthuwu/Cloud-Agent-HQ` |
| `GH_TOKEN` / `GITHUB_TOKEN` | GitHub CLI auth | Auto-detected |

### GitHub Secrets Required (in Cloud-Agent-HQ repo)
| Secret | Purpose |
|--------|---------|
| `OPENCODE_GO_API_KEY` | OpenCode API key |
| `CLOUD_AGENT_HQ_PAT` | PAT for target repos |
| `OPENAI_API_KEY` | For Codex (when ready) |
| `GOOGLE_API_KEY` | For Gemini (when ready) |
| `ANTHROPIC_API_KEY` | For Claude Code (when ready) |

---

## Repository Detection Policy (Enforced)

This skill enforces the global repository-detection policy:

### Before Any Development Task:
1. **Check for existing Git repository** in current directory
2. **If found:**
   - Identify exact GitHub repository (`git remote get-url origin`)
   - Inspect current branch and working tree state
   - Check latest remote commits
   - Identify existing project instructions (AGENTS.md, CLAUDE.md, etc.)
   - Determine public/private
   - Check if registered with Cloud Agent HQ
3. **If not found:**
   - **STOP** before creating files
   - Ask: "Is this project something you'd like to keep in a GitHub repository?"
   - If yes: "Should the repository be public or private?"
   - Create/register accordingly

### Public Repository Auto-Adoption
Once registered as public with `auto_dispatch: true`:
- Hermes automatically uses cloud workers for development
- Tasks split and dispatched independently
- No manual `/cloud dispatch` needed for routine work

---

## Programmatic Usage

### Python API
```python
from scripts.dispatch_task import CloudAgentHQ

hq = CloudAgentHQ()

# Dispatch single task
task = hq.build_task_contract(
    repo="Chimthuwu/GameVolley",
    instructions="Fix the bug in loading.js",
    worker="opencode"
)
result = hq.dispatch_task(task)

# Check status
status = hq.check_task_status("gamevolley-0042-20261121-143022")

# List workers
workers = hq.list_workers()

# Register repo
hq.register_repository("Chimthuwu/NewRepo", "public")
```

### Direct CLI
```bash
# Dispatch
python scripts/dispatch-task.py dispatch Chimthuwu/GameVolley "Fix bug" --worker opencode

# Batch
python scripts/dispatch-task.py batch tasks.json --parallel 3

# Status
python scripts/dispatch-task.py status gamevolley-0042-20261121-143022

# Register
python scripts/dispatch-task.py register-repo Chimthuwu/NewRepo --public
```

---

## Workflow Integration

### Typical Development Flow

1. **Start work on a project**
   ```
   cd /path/to/project
   # Hermes detects repo, checks registration
   ```

2. **Describe work to Hermes**
   ```
   "Take a look at my GameVolley repository. I want the loading system improved, 
   the game validation fixed and the preview reliability tested. Delegate whatever 
   can be done independently."
   ```

3. **Hermes:**
   - Identifies repository (Chimthuwu/GameVolley)
   - Inspects current state and instructions
   - Plans work, splits into independent tasks
   - Dispatches cloud workers via `/cloud dispatch` or batch
   - Monitors execution via tracking issues
   - Collects PRs, coordinates reviews
   - Reports completed/failed/outstanding work

4. **You:**
   - Review PRs at your leisure
   - Merge when ready
   - Computer can be off while workers execute

---

## Troubleshooting

### "Repository not registered"
```bash
/register-repo Chimthuwu/MyRepo --public
```

### "Worker not available"
```bash
/cloud list-workers
# Check registry/workers.yaml for configuration
```

### "Dispatch failed"
- Check GitHub Actions: https://github.com/Chimthuwu/Cloud-Agent-HQ/actions
- Verify secrets: `OPENCODE_GO_API_KEY`, `CLOUD_AGENT_HQ_PAT`
- Check task contract validation errors

### "Task stuck"
```bash
/cloud status <task-id>
# Check tracking issue for workflow link
/cloud cancel <task-id>
/cloud retry <task-id>
```

---

## Best Practices

1. **Always let Hermes detect the repo first** - don't manually specify unless needed
2. **Use batch for independent tasks** - reduces overhead
3. **Specify verification commands** - catches issues early
4. **Use appropriate priority** - affects review SLA
5. **Register repos before starting work** - enables auto-dispatch
6. **Review PRs promptly** - keeps workflow moving