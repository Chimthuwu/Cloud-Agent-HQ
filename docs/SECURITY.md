# Cloud Agent HQ — Security Boundaries

**Version:** 1.0

---

## Threat Model

Cloud Agent HQ operates on a **trusted control plane, untrusted execution plane** model:

- **Control Plane (Trusted):** Hermes, Cloud-Agent-HQ repo, registry, dispatch logic
- **Execution Plane (Untrusted):** GitHub Actions runners, worker CLIs, target repositories
- **Boundary:** GitHub Actions workflow isolation, secret scoping, permission limits

---

## Secret Management

### Organization Secrets (Chimthuwu)
| Secret | Purpose | Scope |
|--------|---------|-------|
| `OPENCODE_GO_API_KEY` | OpenCode API authentication | Worker workflows |
| `OPENAI_API_KEY` | Codex/OpenAI API | Worker workflows |
| `GOOGLE_API_KEY` | Gemini API | Worker workflows |
| `ANTHROPIC_API_KEY` | Claude Code API | Worker workflows |
| `CLOUD_AGENT_HQ_PAT` | GitHub PAT for target repos | All workflows |

### Repository Secrets (Per Target Repo)
| Secret | Purpose |
|--------|---------|
| `CLOUD_AGENT_HQ_PAT` | PAT with `repo` scope for push/PR |

### Rules
- **Never commit secrets** to any repository
- **Use GitHub Environments** for production secrets
- **Rotate secrets quarterly** (documented in RUNBOOKS/secrets-rotation.md)
- **No secrets in workflow logs** - use `::add-mask::` for sensitive output

---

## Permission Model

### GitHub Token Permissions (GITHUB_TOKEN)

| Workflow | Permissions |
|----------|-------------|
| `dispatch-task.yml` | `contents: read`, `issues: write`, `actions: read` |
| `worker-*.yml` | `contents: read` (target repo via PAT) |
| `review-pr.yml` | `contents: read`, `pull_requests: write`, `issues: write` |

**Principle:** Minimum permissions necessary. No `admin`, `delete`, or `security_events`.

### Target Repository Access

Workers use `TARGET_REPO_PAT` (repository secret) with scopes:
- `contents: read/write` - Checkout, commit, push
- `pull_requests: write` - Create PRs
- `issues: write` - Comment on tracking issues (in HQ repo)

**Never** use `GITHUB_TOKEN` for target repo writes - it only has HQ repo permissions.

---

## Worker Isolation

Each task executes in a **fresh GitHub Actions runner**:
- No shared filesystem between tasks
- No persistent state
- Unique branch per task (`cloud-agent/<task-id>/<worker>`)
- Ephemeral environment destroyed after completion

**No self-hosted runners** - all execution on GitHub-hosted runners.

---

## Untrusted Input Handling

### Never Execute Untrusted Content With Privileges

| Input Source | Risk | Mitigation |
|--------------|------|------------|
| GitHub Issue body | User-controlled | Never pass to CLI with secrets |
| PR description | User-controlled | Never execute as code |
| Task instructions | Hermes-generated | Validated against schema |
| Repository files | Project-controlled | Read-only for context |

**Rule:** Worker adapters only execute the worker CLI with structured instructions, never arbitrary shell commands from untrusted sources.

---

## Registry Protection

### Cloud-Agent-HQ Repository
- Branch protection on `main`
- Required reviews for registry changes
- Status checks (schema validation)
- Only maintainers can merge

### Registry Files
- `registry/repos.yaml` - Controls which repos are accessible
- `registry/workers.yaml` - Controls worker capabilities
- Changes require PR + review

**Workers cannot modify registries** - no write access to HQ repo.

---

## Concurrency & DoS Protection

### Limits
- Per-worker max concurrent (registry/workers.yaml)
- Global max concurrent (GitHub Free: 20 public)
- Queue pattern for excess tasks
- Per-task timeout (max 120 min)

### Abuse Prevention
- Unique task IDs prevent duplicate execution
- `concurrency` groups prevent same-task re-run
- Rate limiting via GitHub API limits
- Tracking issues provide audit trail

---

## Pull Request Security

### PR Creation
- Workers create PRs from isolated branches
- PRs require review before merge
- Base branch protection enforced

### PR Review
- Independent reviewer (different worker or human)
- Automated checks must pass
- No auto-merge without approval

### Merge
- Squash merge (linear history)
- Branch deleted after merge
- No force-push allowed

---

## Audit & Monitoring

### Tracking
- Every task creates GitHub Issue in HQ repo
- Issues labeled: `cloud-agent-task`, `<worker>`, `<priority>`
- Execution reports uploaded as artifacts (30-day retention)
- Review reports uploaded as artifacts

### Alerting (Future)
- Failed task rate > threshold
- Minute budget consumption > 80%
- Secret scanning alerts
- Dependency vulnerability alerts

---

## Incident Response

### Compromised Worker
1. Revoke API key in provider dashboard
2. Rotate GitHub PAT
3. Audit recent task executions
4. Check for unauthorized PRs/commits

### Compromised Target Repo
1. Revoke `CLOUD_AGENT_HQ_PAT` for that repo
2. Audit recent cloud-agent branches/PRs
3. Check for malicious code in merged PRs
4. Rotate all related secrets

### Secret Leak in Logs
1. Rotate affected secret immediately
2. Invalidate GitHub Actions cache
3. Check log retention settings
4. Audit access to leaked secret

---

## Compliance

### Data Handling
- No PII in task contracts or reports
- Execution logs may contain code snippets
- Artifacts retained 30 days max
- No persistent storage of user data

### Provider ToS
- Respect OpenRouter, OpenAI, Google, Anthropic ToS
- Free tier quotas monitored
- No automated ToS violations

---

## Security Runbooks

| Scenario | Runbook |
|----------|---------|
| Secret rotation | `docs/RUNBOOKS/secrets-rotation.md` |
| Compromised worker | `docs/RUNBOOKS/compromised-worker.md` |
| Compromised target repo | `docs/RUNBOOKS/compromised-target-repo.md` |
| Minute budget exceeded | `docs/RUNBOOKS/minute-budget.md` |
| Secret in logs | `docs/RUNBOOKS/secret-in-logs.md` |

---

## Security Checklist (Per Release)

- [ ] All secrets in GitHub (not in repo)
- [ ] Workflow permissions minimized
- [ ] Registry changes require review
- [ ] Worker isolation verified
- [ ] Untrusted input paths audited
- [ ] Dependency vulnerabilities scanned
- [ ] Secret scanning enabled
- [ ] Runbooks up to date