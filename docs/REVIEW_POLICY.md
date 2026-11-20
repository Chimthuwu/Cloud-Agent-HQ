# Cloud Agent HQ — Review Policy

**Version:** 1.0

---

## Principle: Implementers ≠ Reviewers

No coding agent should approve its own work. Every pull request must pass independent review before merge.

---

## Reviewer Assignment

| Implementer | Default Reviewer | Human Override |
|-------------|------------------|----------------|
| OpenCode | Codex | `--reviewer human` |
| Codex | OpenCode | `--reviewer human` |
| Gemini | OpenCode | `--reviewer human` |
| Claude Code | OpenCode | `--reviewer human` |

**`different` (default):** Auto-assign a different worker profile.
**`human`:** Route to manual human review.

---

## Review Criteria

Reviewers must evaluate:

### 1. Task Completion
- Did the implementation address all requirements?
- Are edge cases handled?
- Is the scope complete (no missing pieces)?

### 2. Architectural Compatibility
- Fits existing project architecture
- Follows established patterns and conventions
- No inappropriate abstractions or over-engineering

### 3. Existing Conventions
- Code style matches project (linting passes)
- Naming conventions followed
- File organization consistent
- Import/export patterns match

### 4. Regression Prevention
- Existing tests still pass
- No broken functionality
- No performance regressions
- No security regressions

### 5. Security
- No secrets, keys, or credentials in code
- No dangerous patterns (eval, exec, SQL injection)
- Proper input validation
- Least-privilege principles

### 6. Test Coverage
- New code has tests
- Critical paths covered
- Edge cases tested
- Tests are meaningful (not just coverage theater)

### 7. Build & Runtime
- Build succeeds
- Type checking passes
- Linting passes
- Application starts/runs without errors

---

## Review Decision Types

| Decision | When | Action |
|----------|------|--------|
| **Approve** | All criteria met, no blocking issues | PR ready for merge |
| **Request Changes** | Blocking issues found | Implementer must address |
| **Comment** | Minor suggestions, non-blocking | Optional improvements |

---

## Automated Verification

Every review includes automated checks:

```yaml
verification:
  build_passed: true/false
  tests_passed: true/false
  lint_passed: true/false
  typecheck_passed: true/false
  custom_checks: {}
```

**Policy:** Automated checks must pass before human/worker review completes.

---

## Review Report Schema

See `schemas/review-report.json` for the structured output format.

**Key fields:**
- `decision`: approve | request_changes | comment
- `findings[]`: Structured findings with severity, category, file, line
- `verification`: Automated check results
- `requires_human_review`: Boolean flag

---

## Severity Levels

| Level | Emoji | Description |
|-------|-------|-------------|
| `critical` | 🔴 | Blocks merge - security, data loss, crash |
| `major` | 🟠 | Blocks merge - broken functionality, major bug |
| `minor` | 🟡 | Should fix - style, minor bug, missing test |
| `info` | 🔵 | Informational - suggestion, documentation |
| `praise` | 🟢 | Positive - good pattern, clever solution |

---

## Categories

| Category | Focus |
|----------|-------|
| `task_completion` | Requirements fulfilled |
| `architecture` | Design, patterns, structure |
| `conventions` | Style, naming, organization |
| `regression` | Broken existing functionality |
| `security` | Vulnerabilities, secrets, unsafe code |
| `testing` | Coverage, quality, missing tests |
| `build` | Compilation, type errors, lint |
| `documentation` | Comments, docs, README |
| `performance` | Efficiency, bottlenecks |

---

## Merge Gates

A PR can be merged when:
1. ✅ All status checks pass (build, test, lint, typecheck)
2. ✅ At least 1 approving review (worker or human)
3. ✅ No outstanding "Request Changes"
4. ✅ Branch up to date with base
5. ✅ Linear history (squash merge)

**Auto-merge:** Enabled for `approve` decisions with all checks passing.

---

## Failed Reviews

When review decision is `request_changes`:
1. Review posted to PR with detailed findings
2. Tracking issue updated with `review:changes-requested` label
3. Implementer worker can be re-dispatched with feedback
4. New PR iteration triggers new review cycle

**Re-dispatch example:**
```
/cloud retry gamevolley-0042-20261121-143022 --worker opencode
```

---

## Human Review Escalation

Trigger human review when:
- Worker reviewers disagree
- Security-sensitive changes
- Architectural decisions
- `requires_human_review: true` in review report
- Explicit `--reviewer human` flag

---

## Review SLA

| Priority | Review Target |
|----------|---------------|
| `urgent` | 30 minutes |
| `high` | 2 hours |
| `normal` | 24 hours |
| `low` | 72 hours |

Cloud workers typically complete reviews in minutes.

---

## Reviewer Configuration

Each worker profile can have review-specific config in `workers/<profile>/config.yaml`:

```yaml
review:
  model: "review-optimized-model"  # Optional: different model for review
  focus_areas:
    - security
    - testing
    - architecture
  strict_mode: false  # If true, minor issues become major
```