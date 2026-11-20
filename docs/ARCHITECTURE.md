# Cloud Agent HQ — Architecture

**Version:** 1.0
**Status:** Active Development
**Repository:** https://github.com/Chimthuwu/Cloud-Agent-HQ

---

## 1. System Overview

Cloud Agent HQ is a GitHub-native orchestration layer that enables Hermes (local control centre) to dispatch coding tasks to cloud-based GitHub Actions runners. Workers execute in isolated, ephemeral environments and return results via pull requests.

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   Hermes CLI    │────▶│  Cloud-Agent-HQ  │────▶│  GitHub Actions     │
│  (Control       │     │  (Orchestration  │     │  (Compute Layer)    │
│   Centre)       │     │   Repository)    │     │                     │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
                              │                          │
                              ▼                          ▼
                       ┌──────────────────┐     ┌─────────────────────┐
                       │  Registry &      │     │  Worker Adapters    │
                       │  Config (YAML)   │     │  (OpenCode, Codex,  │
                       └──────────────────┘     │   Gemini, Claude)   │
                                                └─────────────────────┘
```

### Core Principles

1. **GitHub as Source of Truth** — All state lives in repos (issues, PRs, Actions, registry files)
2. **No Persistent Servers** — $0/month via GitHub-hosted runners for public repos
3. **Worker Isolation** — Each task gets fresh runner, fresh checkout, unique branch
4. **Interchangeable Workers** — Common task contract, separate CLI adapters
5. **Independent Review** — Implementers ≠ reviewers; automated + human gates
6. **Hermes-Native** — Dispatch from existing Hermes CLI, no new UI needed

---

## 2. Component Architecture

### 2.1 Repository Structure

```
Cloud-Agent-HQ/
├── .github/
│   └── workflows/
│       ├── dispatch-task.yml          # Single task dispatch
│       ├── dispatch-batch.yml         # Multiple independent tasks
│       ├── worker-opencode.yml        # OpenCode worker execution
│       ├── worker-codex.yml           # Codex CLI worker execution
│       ├── worker-gemini.yml          # Gemini CLI worker execution
│       ├── worker-claude.yml          # Claude Code worker execution
│       ├── review-pr.yml              # Independent review automation
│       └── cleanup.yml                # Stale branch/PR cleanup
├── dispatch/
│   ├── task-contract.json             # JSON Schema for task payload
│   └── task-examples/                 # Example task definitions
├── registry/
│   ├── repos.yaml                     # Registered repositories
│   └── workers.yaml                   # Worker profiles & capabilities
├── workers/
│   ├── opencode/
│   │   ├── adapter.sh                 # Entry point script
│   │   ├── config.yaml                # Worker-specific config
│   │   └── verify.sh                  # Health check
│   ├── codex/
│   │   ├── adapter.sh
│   │   ├── config.yaml
│   │   └── verify.sh
│   ├── gemini/
│   │   ├── adapter.sh
│   │   ├── config.yaml
│   │   └── verify.sh
│   └── claude/
│       ├── adapter.sh
│       ├── config.yaml
│       └── verify.sh
├── schemas/
│   ├── task-contract.json             # Canonical task schema
│   ├── execution-report.json          # Worker output schema
│   └── review-report.json             # Reviewer output schema
├── scripts/
│   ├── dispatch-task.py               # Hermes CLI dispatch helper
│   ├── register-repo.py               # Repository registration
│   ├── list-workers.py                # Worker availability check
│   └── task-status.py                 # Check task/PR status
├── docs/
│   ├── ARCHITECTURE.md                # This file
│   ├── WORKER_ADAPTERS.md             # Adapter implementation guide
│   ├── TASK_CONTRACT.md               # Task payload specification
│   ├── HERMES_INTEGRATION.md          # Hermes slash commands
│   ├── REPOSITORY_REGISTRY.md         # Registry format & policy
│   ├── REVIEW_POLICY.md               # Independent review process
│   ├── SECURITY.md                    # Security boundaries
│   ├── TROUBLESHOOTING.md             # Common issues
│   └── RUNBOOKS/                      # Operational procedures
└── tests/
    ├── mock-worker.sh                 # Mock worker for infra tests
    ├── test-dispatch.sh               # Dispatch integration test
    └── test-concurrency.sh            # Concurrency load test
```

### 2.2 Data Flow

```
Task Submission (Hermes)
         │
         ▼
GitHub Actions: dispatch-task.yml (workflow_dispatch)
         │
         ├─▶ Validates task against schema
         ├─▶ Checks repository registry (public/private, registered)
         ├─▶ Checks worker availability (registry + concurrency)
         ├─▶ Creates GitHub Issue for tracking (optional)
         └─▶ Triggers worker workflow (worker-<profile>.yml)
                │
                ▼
         Worker Workflow (runs on ubuntu-latest)
                │
                ├─▶ Checkout target repo (base branch)
                ├─▶ Create unique branch: `cloud-agent/<task-id>/<timestamp>`
                ├─▶ Run worker adapter (OpenCode/Codex/Gemini/Claude)
                ├─▶ Adapter executes task, runs verification
                ├─▶ Commit & push changes
                ├─▶ Open Pull Request with execution report
                └─▶ Post result to tracking issue
                       │
                       ▼
              Review Process (review-pr.yml)
                       │
                       ├─▶ Automated checks (build, test, lint)
                       ├─▶ Independent reviewer (different worker profile)
                       ├─▶ Human review gate (optional)
                       └─▶ Merge or request changes
```

---

## 3. Task Contract

### 3.1 Canonical Schema (`schemas/task-contract.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Cloud Agent Task Contract",
  "type": "object",
  "required": ["task_id", "repository", "base_branch", "instructions", "worker_profile"],
  "properties": {
    "task_id": { "type": "string", "pattern": "^[a-z0-9-]+$" },
    "repository": { "type": "string", "pattern": "^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$" },
    "base_branch": { "type": "string", "default": "main" },
    "instructions": { "type": "string", "minLength": 10 },
    "worker_profile": { "type": "string", "enum": ["opencode", "codex", "gemini", "claude"] },
    "reviewer_profile": { "type": "string", "enum": ["opencode", "codex", "gemini", "claude", "human"] },
    "timeout_minutes": { "type": "integer", "minimum": 5, "maximum": 120, "default": 30 },
    "tool_permissions": { "type": "array", "items": { "type": "string" } },
    "environment_vars": { "type": "object" },
    "verification_commands": { "type": "array", "items": { "type": "string" } },
    "metadata": { "type": "object" }
  }
}
```

### 3.2 Task ID Format

`<repo-slug>-<sequential>-<timestamp>`
Example: `gamevolley-0042-20261121-143022`

### 3.3 Branch Naming

`cloud-agent/<task-id>/<worker-profile>`
Example: `cloud-agent/gamevolley-0042-20261121-143022/opencode`

---

## 4. Worker Adapter Interface

### 4.1 Common Contract

Each worker adapter implements:

```bash
# Entry point (called by GitHub Actions workflow)
./adapter.sh <task-json-file> <workspace-dir> <output-report-file>

# Environment variables provided:
#   TASK_JSON          - Path to task contract JSON
#   WORKSPACE          - Repository checkout directory
#   REPORT_OUTPUT      - Path to write execution report
#   GITHUB_TOKEN       - GitHub token for API access
#   REPO_OWNER, REPO_NAME, BASE_BRANCH, TASK_ID
```

### 4.2 Execution Report Schema (`schemas/execution-report.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Worker Execution Report",
  "type": "object",
  "required": ["task_id", "worker_profile", "status", "branch", "pr_number", "summary"],
  "properties": {
    "task_id": { "type": "string" },
    "worker_profile": { "type": "string" },
    "status": { "type": "string", "enum": ["success", "partial", "failed", "timeout"] },
    "branch": { "type": "string" },
    "pr_number": { "type": "integer" },
    "summary": { "type": "string" },
    "changes": { "type": "array", "items": { "type": "string" } },
    "verification_results": { "type": "object" },
    "errors": { "type": "array", "items": { "type": "string" } },
    "duration_seconds": { "type": "integer" },
    "tokens_used": { "type": "object" }
  }
}
```

### 4.3 Adapter Responsibilities

1. Parse task JSON
2. Read repository instructions (AGENTS.md, CLAUDE.md, README, etc.)
3. Inspect relevant code before modifying
4. Execute task using the CLI
5. Run verification commands
6. Commit changes with conventional commit messages
7. Push branch
8. Create PR via GitHub API/CLI
9. Write execution report to output path

---

## 5. Repository Registry (`registry/repos.yaml`)

```yaml
# Cloud Agent HQ Repository Registry
# Public repos: auto-eligible for cloud workers
# Private repos: require explicit enable + minute allowance check

repositories:
  - name: "Chimthuwu/GameVolley"
    visibility: public
    default_branch: main
    registered_at: "2026-11-21"
    instructions_files: [AGENTS.md, CLAUDE.md, README.md, TODO.md]
    worker_profiles: [opencode, codex, gemini, claude]
    review_required: true
    auto_dispatch: true
    notes: "Electron game, TypeScript/JS, low-risk test target"

  - name: "Chimthuwu/LISA"
    visibility: private
    default_branch: main
    registered_at: "2026-11-21"
    instructions_files: [AGENTS.md, SETUP.agent.md, GOALS.md, TODO.md]
    worker_profiles: [opencode, codex]
    review_required: true
    auto_dispatch: false
    notes: "Private - requires Actions minute budget verification"
    minute_budget_check: true

# Future registrations added here
```

---

## 6. Worker Registry (`registry/workers.yaml`)

```yaml
# Cloud Agent HQ Worker Profiles
# Each profile maps to a GitHub Actions workflow + adapter

workers:
  opencode:
    name: "OpenCode"
    cli: "opencode"
    version: ">=2.3.0"
    auth_method: "api_key"  # OPENCODE_GO_API_KEY
    config_file: "workers/opencode/config.yaml"
    adapter: "workers/opencode/adapter.sh"
    verify_script: "workers/opencode/verify.sh"
    default_model: "sonnet-4"  # or via OPENCODE_MODEL
    max_concurrent: 5
    timeout_minutes: 30
    capabilities:
      - code_generation
      - refactoring
      - testing
      - documentation
    supported_repos: ["public", "private"]

  codex:
    name: "Codex CLI"
    cli: "codex"
    version: ">=0.170.0"
    auth_method: "device_code"  # Requires OAuth flow
    config_file: "workers/codex/config.yaml"
    adapter: "workers/codex/adapter.sh"
    verify_script: "workers/codex/verify.sh"
    default_model: "gpt-4o"
    max_concurrent: 3
    timeout_minutes: 30
    capabilities:
      - code_generation
      - debugging
      - code_review
    supported_repos: ["public"]  # Private needs org OAuth

  gemini:
    name: "Gemini CLI"
    cli: "gemini"
    version: ">=0.1.0"
    auth_method: "api_key"  # GOOGLE_API_KEY or GEMINI_API_KEY
    config_file: "workers/gemini/config.yaml"
    adapter: "workers/gemini/adapter.sh"
    verify_script: "workers/gemini/verify.sh"
    default_model: "gemini-2.5-pro"
    max_concurrent: 3
    timeout_minutes: 30
    capabilities:
      - code_generation
      - large_context_analysis
      - documentation
    supported_repos: ["public"]

  claude:
    name: "Claude Code"
    cli: "claude"
    version: ">=2.1.322"
    auth_method: "oauth"  # Anthropic OAuth
    config_file: "workers/claude/config.yaml"
    adapter: "workers/claude/adapter.sh"
    verify_script: "workers/claude/verify.sh"
    default_model: "claude-sonnet-4"
    max_concurrent: 2
    timeout_minutes: 45
    capabilities:
      - code_generation
      - architecture
      - code_review
      - complex_reasoning
    supported_repos: ["public"]  # Private needs org OAuth
```

---

## 7. Concurrency & Queue Management

### 7.1 GitHub Actions Concurrency

```yaml
# In each worker workflow:
concurrency:
  group: cloud-agent-${{ github.workflow }}-${{ inputs.task_id }}
  cancel-in-progress: false  # Never cancel - each task unique
```

### 7.2 Global Concurrency Limit

- **Repository-level:** `max-parallel` in workflow dispatch
- **Organization-level:** GitHub Free = 20 concurrent jobs (public), varies for private
- **Worker-profile-level:** Defined in `workers.yaml` (`max_concurrent`)

### 7.3 Queue Pattern (for >10 workers)

When concurrency limit reached:
1. Dispatch workflow creates Issue with `queued` label
2. Separate `queue-processor.yml` workflow runs on schedule (every 5 min)
3. Processor checks running job count via GitHub API
4. If slots available, triggers next queued task
5. Prevents "thundering herd" of workflow runs

---

## 8. Security Boundaries

| Layer | Protection |
|-------|------------|
| **Secrets** | GitHub Environments + Repository/Org secrets; never in repo |
| **Permissions** | `GITHUB_TOKEN` with minimal scopes (`contents: write`, `pull_requests: write`, `issues: write`) |
| **Worker Isolation** | Fresh runner per job; no shared filesystem |
| **PR Validation** | Required reviews, status checks, branch protection |
| **Secret Scanning** | GitHub secret scanning enabled on HQ repo |
| **Untrusted Input** | Never execute Issue/PR body content with privileged tokens |
| **Permission Escalation** | Workers cannot modify workflows, registry, or their own permissions |

### Secret Management

```
GitHub Organization Secrets (Chimthuwu):
├── OPENCODE_GO_API_KEY          # OpenCode API key
├── GITHUB_PAT_CLOUD_AGENT       # Dedicated PAT for cloud operations (if needed)
├── ANTHROPIC_API_KEY            # For Claude Code (if not OAuth)
├── GOOGLE_API_KEY               # For Gemini CLI
└── OPENAI_API_KEY               # For Codex (if not device code)

Repository Secrets (per target repo):
├── CLOUD_AGENT_HQ_PAT           # PAT with repo scope for HQ to dispatch
└── (worker-specific keys as needed)
```

---

## 9. Hermes Integration

### 9.1 Slash Commands (Added to Hermes)

```
/cloud dispatch <repo> <instructions> [--worker opencode|codex|gemini|claude] [--branch main] [--reviewer opencode|human]
/cloud batch <repo> <tasks-file.json> [--worker opencode] [--parallel 3]
/cloud status <task-id|pr-number>
/cloud list-workers
/register-repo <owner/repo> [--public|--private]
/cloud logs <task-id>
/cloud retry <task-id>
/cloud cancel <task-id>
```

### 9.2 Implementation

- `scripts/dispatch-task.py` — Core dispatch logic
- Hermes skill: `cloud-agent-hq` with slash command handlers
- Uses `gh workflow run` or `gh api` to trigger `dispatch-task.yml`

---

## 10. Review & Merge Policy

### 10.1 Reviewer Assignment

- **Default:** Different worker profile than implementer (e.g., OpenCode → Codex)
- **Human:** `@human` flag routes to manual review
- **Auto:** Automated checks always run (build, test, lint)

### 10.2 Review Criteria

1. Task completion (did it do what was asked?)
2. Architectural compatibility
3. Existing conventions followed
4. No regressions (tests pass)
5. Security issues (no secrets, no dangerous patterns)
6. Test coverage for new code
7. Build/runtime verification

### 10.3 Merge Gates

- All status checks pass
- At least 1 approving review (worker or human)
- No requested changes outstanding
- Branch up to date with base
- Linear history (squash merge)

---

## 11. Operational Runbooks

| Scenario | Runbook |
|----------|---------|
| Register new public repo | `docs/RUNBOOKS/register-public-repo.md` |
| Register new private repo | `docs/RUNBOOKS/register-private-repo.md` |
| Worker fails verification | `docs/RUNBOOKS/worker-verification-failure.md` |
| Concurrency exhausted | `docs/RUNBOOKS/concurrency-exhausted.md` |
| PR stuck in review | `docs/RUNBOOKS/pr-stuck-in-review.md` |
| Secrets rotation | `docs/RUNBOOKS/secrets-rotation.md` |
| GitHub Actions minute budget | `docs/RUNBOOKS/minute-budget.md` |

---

## 12. Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| HQ Repository | ✅ Created | `Chimthuwu/Cloud-Agent-HQ` |
| Architecture Doc | ✅ This file | |
| Task Contract Schema | 🔄 Next | `schemas/task-contract.json` |
| Execution Report Schema | 🔄 Next | `schemas/execution-report.json` |
| Repository Registry | 🔄 Next | `registry/repos.yaml` |
| Worker Registry | 🔄 Next | `registry/workers.yaml` |
| Dispatch Workflow | ⏳ Pending | `.github/workflows/dispatch-task.yml` |
| OpenCode Adapter | ⏳ Pending | `workers/opencode/adapter.sh` |
| Codex Adapter | ⏳ Pending | `workers/codex/adapter.sh` |
| Gemini Adapter | ⏳ Pending | `workers/gemini/adapter.sh` |
| Claude Adapter | ⏳ Pending | `workers/claude/adapter.sh` |
| Review Workflow | ⏳ Pending | `.github/workflows/review-pr.yml` |
| Hermes Slash Commands | ⏳ Pending | `scripts/dispatch-task.py` + skill |
| Test Infrastructure | ⏳ Pending | `tests/` |
| Documentation | ⏳ Pending | `docs/` |

---

## 13. Next Steps (Immediate)

1. Create JSON schemas (`task-contract.json`, `execution-report.json`, `review-report.json`)
2. Create registry files (`repos.yaml`, `workers.yaml`)
3. Implement `dispatch-task.yml` workflow
4. Implement OpenCode worker adapter (first verified worker)
5. Create Hermes dispatch script (`scripts/dispatch-task.py`)
6. Register GameVolley as first test repository
7. Run end-to-end test with a low-risk task
8. Document and iterate