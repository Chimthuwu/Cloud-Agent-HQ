# Cloud Agent HQ — Task Contract Specification

**Version:** 1.0
**Schema:** `schemas/task-contract.json`

---

## Overview

The Task Contract is the canonical data structure that defines a coding task for Cloud Agent HQ workers. It serves as the single source of truth for task dispatch, worker execution, and result reporting.

All tasks must conform to the JSON Schema at `schemas/task-contract.json`.

---

## Field Reference

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `task_id` | string | Unique identifier (format: `repo-slug-NNNN-YYYYMMDD-HHMMSS`) |
| `repository` | string | Target repository in `owner/name` format |
| `base_branch` | string | Base branch to work from (default: `main`) |
| `instructions` | string | Detailed task instructions (min 10 chars) |
| `worker_profile` | string | Worker to execute: `opencode`, `codex`, `gemini`, `claude` |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `reviewer_profile` | string | `different` | Reviewer: `opencode`, `codex`, `gemini`, `claude`, `human`, `different` |
| `timeout_minutes` | integer | 30 | Max execution time (5-120) |
| `tool_permissions` | array | `["read","write","edit","bash","grep","glob"]` | Allowed tools for worker |
| `environment_vars` | object | `{}` | Additional env vars for worker |
| `verification_commands` | array | `[]` | Commands to run after implementation |
| `metadata` | object | `{}` | Arbitrary tracking metadata |
| `priority` | string | `normal` | `low`, `normal`, `high`, `urgent` |
| `labels` | array | `[]` | GitHub labels for tracking issue |

---

## Task ID Format

```
<repo-slug>-<sequential>-<timestamp>
```

**Examples:**
- `gamevolley-0042-20261121-143022`
- `lisa-0001-20261121-150000`
- `cloud-agent-hq-0010-20261121-160000`

**Rules:**
- Repo slug: lowercase, hyphens only (from `owner/name`)
- Sequential: 4-digit zero-padded (per repo)
- Timestamp: UTC `YYYYMMDD-HHMMSS`

---

## Worker Profiles

| Profile | CLI | Auth | Best For |
|---------|-----|------|----------|
| `opencode` | `opencode` | API Key | General coding, refactoring, testing |
| `codex` | `codex` | Device Code | Debugging, code review (OAuth pending) |
| `gemini` | `gemini` | API Key | Large context, documentation |
| `claude` | `claude` | OAuth | Architecture, complex reasoning |

---

## Verification Commands

Commands run after worker implementation to validate results.

**Common patterns:**
```json
{
  "verification_commands": [
    "npm test",
    "npm run lint",
    "npm run typecheck",
    "python -m pytest",
    "cargo test",
    "go test ./...",
    "./build.sh"
  ]
}
```

**Results captured in execution report:**
- `verification_results.commands_run` - All commands executed
- `verification_results.passed` - Commands that succeeded
- `verification_results.failed` - Commands that failed
- `verification_results.output` - Combined stdout/stderr

---

## Example Task Contracts

### Simple Bug Fix (OpenCode)
```json
{
  "task_id": "gamevolley-0042-20261121-143022",
  "repository": "Chimthuwu/GameVolley",
  "base_branch": "main",
  "instructions": "Fix the loading screen bug in src/loading.js. The spinner doesn't stop when assets finish loading. Check the assetLoaded callback and ensure loadingComplete is called.",
  "worker_profile": "opencode",
  "reviewer_profile": "codex",
  "timeout_minutes: 30,
  "verification_commands": ["npm test", "npm run lint"],
  "priority": "high",
  "labels": ["bugfix", "loading"]
}
```

### Feature Implementation (OpenCode)
```json
{
  "task_id": "gamevolley-0043-20261121-143500",
  "repository": "Chimthuwu/GameVolley",
  "base_branch": "main",
  "instructions": "Implement game validation system in src/validation.js. Add validateGameConfig() that checks required fields, valid ranges, and cross-field dependencies. Export as default. Follow existing code style in src/*.js.",
  "worker_profile": "opencode",
  "reviewer_profile": "different",
  "timeout_minutes: 45,
  "verification_commands": ["npm test", "npm run lint", "node -e \"require('./src/validation.js')\""],
  "priority": "normal",
  "labels": ["feature", "validation"]
}
```

### Documentation Update (Gemini - when ready)
```json
{
  "task_id": "lisa-0001-20261121-150000",
  "repository": "Chimthuwu/LISA",
  "base_branch": "main",
  "instructions": "Update AGENTS.md and SETUP.agent.md to reflect new Cloud Agent HQ integration. Document the /cloud slash commands, repository registration process, and worker profiles. Keep existing formatting and style.",
  "worker_profile": "gemini",
  "reviewer_profile": "human",
  "timeout_minutes: 30,
  "verification_commands": ["markdownlint AGENTS.md SETUP.agent.md"],
  "priority": "low",
  "labels": ["documentation"]
}
```

---

## Dispatch Methods

### Via Hermes Slash Command
```
/cloud dispatch Chimthuwu/GameVolley "Fix loading bug" --worker opencode --verify "npm test"
```

### Via Python Script
```bash
python scripts/dispatch-task.py dispatch Chimthuwu/GameVolley "Fix loading bug" --worker opencode --verify "npm test"
```

### Via GitHub API (workflow_dispatch)
```bash
gh api --method POST /repos/Chimthuwu/Cloud-Agent-HQ/actions/workflows/dispatch-task.yml/dispatches \
  -f ref=main \
  -f inputs[task_json]='{"task_id":"...",...}'
```

---

## Validation

Tasks are validated at dispatch time:
1. Required fields present
2. JSON Schema validation
3. Repository registered in `registry/repos.yaml`
4. Worker profile allowed for repository
5. Private repo constraints checked

Invalid tasks fail fast with descriptive errors.

---

## Versioning

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-11-21 | Initial specification |