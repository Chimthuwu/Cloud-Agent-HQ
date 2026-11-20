# Cloud Agent HQ — Repository Registry Policy

**Version:** 1.0

---

## Overview

The Repository Registry (`registry/repos.yaml`) is the authoritative list of repositories that Cloud Agent HQ can operate on. It enforces security boundaries, tracks capabilities, and enables automated workflow adoption.

---

## Registration Requirements

### Public Repositories
- **Auto-eligible** for cloud workers (GitHub Actions free tier)
- **No minute budget constraints**
- **Auto-dispatch enabled by default**
- **All worker profiles available**

### Private Repositories
- **Require explicit registration** with `auto_dispatch: true`
- **Minute budget check required** before enabling
- **Worker profile restrictions may apply** (OAuth limitations)
- **Default: auto_dispatch: false**

---

## Registry Schema

```yaml
repositories:
  - name: "owner/repo"           # Required: GitHub repository
    visibility: public|private   # Required: public or private
    default_branch: main         # Required: default branch
    registered_at: "YYYY-MM-DD"  # Required: registration date
    instructions_files: []       # Optional: project instruction files
    worker_profiles: []          # Optional: allowed workers
    review_required: true        # Optional: require review before merge
    auto_dispatch: true          # Optional: allow automated dispatch
    minute_budget_check: false   # Optional: for private repos
    notes: ""                    # Optional: human-readable notes
    labels: []                   # Optional: classification labels
```

---

## Instruction Files

Cloud Agent HQ workers read these files for project context:

| File | Purpose |
|------|---------|
| `AGENTS.md` | General agent instructions (preferred) |
| `CLAUDE.md` | Claude-specific instructions |
| `README.md` | Project overview |
| `TODO.md` | Current task list |
| `docs/ARCHITECTURE.md` | Architecture documentation |

Workers combine these with task instructions for context.

---

## Worker Profile Compatibility

| Worker | Public Repos | Private Repos |
|--------|--------------|---------------|
| OpenCode | ✅ Full | ✅ Full (API key) |
| Codex | ✅ Full | ⚠️ OAuth needed |
| Gemini | ✅ Full | ✅ Full (API key) |
| Claude Code | ✅ Full | ⚠️ OAuth needed |

Private repo access for OAuth-based workers requires organization-level OAuth app configuration.

---

## Registration Process

### Via Hermes Slash Command
```
/register-repo Chimthuwu/MyRepo --public --workers opencode,codex --notes "New project"
```

### Via Python Script
```bash
python scripts/dispatch-task.py register-repo Chimthuwu/MyRepo --public --workers opencode,codex
```

### Manual (PR to Cloud-Agent-HQ)
1. Edit `registry/repos.yaml`
2. Add repository entry
3. Submit PR for review
4. Merge triggers validation workflow

---

## Validation Rules

On registration and dispatch:
1. Repository exists and is accessible
2. Visibility matches GitHub setting
3. Default branch exists
4. At least one instruction file exists (warn if not)
5. Worker profiles are valid and supported
6. Private repos: minute budget verified (when implemented)

---

## Auto-Dispatch Policy

**Public repos with `auto_dispatch: true`:**
- Hermes automatically uses cloud workers for development tasks
- No manual intervention needed
- Tasks split and dispatched independently where possible

**Private repos / `auto_dispatch: false`:**
- Manual dispatch required via `/cloud dispatch`
- Each task explicitly authorized
- Minute consumption tracked

---

## Labels

Standard labels for classification:
- `cloud-agent:ready` - Registered and validated
- `cloud-agent:public` - Public repository
- `cloud-agent:private` - Private repository
- `cloud-agent:deferred` - Private, waiting for budget verification
- `cloud-agent:archived` - No longer active

---

## Example Registrations

### Public Game Project
```yaml
- name: "Chimthuwu/GameVolley"
  visibility: public
  default_branch: main
  registered_at: "2026-11-21"
  instructions_files: [AGENTS.md, CLAUDE.md, README.md, TODO.md]
  worker_profiles: [opencode, codex, gemini, claude]
  review_required: true
  auto_dispatch: true
  notes: "Electron game, TypeScript/JS, low-risk test target"
  labels: [cloud-agent:ready, cloud-agent:public]
```

### Private Bot Framework
```yaml
- name: "Chimthuwu/LISA"
  visibility: private
  default_branch: main
  registered_at: "2026-11-21"
  instructions_files: [AGENTS.md, SETUP.agent.md, GOALS.md, TODO.md]
  worker_profiles: [opencode, codex]
  review_required: true
  auto_dispatch: false
  minute_budget_check: true
  notes: "Private - requires Actions minute budget verification"
  labels: [cloud-agent:private, cloud-agent:deferred]
```

---

## Maintenance

- Review registry quarterly
- Remove archived repositories
- Update instruction file paths if project structure changes
- Verify worker profile compatibility after CLI updates
- Audit minute consumption for private repos