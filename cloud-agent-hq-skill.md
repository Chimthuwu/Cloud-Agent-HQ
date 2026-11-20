---
name: cloud-agent-hq
version: "1.0.0"
description: "Hermes integration for Cloud Agent HQ - cloud-based multi-agent orchestration"
category: autonomous-ai-agents
author: "Chimthuwu"
homepage: "https://github.com/Chimthuwu/Cloud-Agent-HQ"
license: "MIT"
min_hermes_version: "0.50.0"
tags:
  - cloud
  - agents
  - orchestration
  - github-actions
  - opencode
  - codex
  - gemini
  - claude
---

# Cloud Agent HQ Skill for Hermes

This skill provides slash commands and programmatic integration for Hermes to dispatch coding tasks to Cloud Agent HQ - a GitHub Actions-based cloud execution infrastructure for interchangeable coding workers (OpenCode, Codex, Gemini, Claude Code).

## Slash Commands

### `/cloud dispatch`
Dispatch a single coding task to a cloud worker.

**Usage:**
```
/cloud dispatch <repository> <instructions> [--worker opencode|codex|gemini|claude] [--branch main] [--reviewer opencode|codex|gemini|claude|human] [--timeout 30] [--verify "cmd1" "cmd2"] [--priority normal] [--label "label1"]
```

**Examples:**
```
/cloud dispatch Chimthuwu/GameVolley "Fix the loading screen bug in main.js" --worker opencode
/cloud dispatch Chimthuwu/GameVolley "Add unit tests for game validation" --worker codex --reviewer human
/cloud dispatch Chimthuwu/GameVolley "Refactor the preview reliability module" --worker opencode --verify "npm test" "npm run lint"
```

### `/cloud batch`
Dispatch multiple independent tasks from a JSON file.

**Usage:**
```
/cloud batch <tasks-file.json> [--parallel 3]
```

**Task file format:**
```json
[
  {
    "repository": "Chimthuwu/GameVolley",
    "instructions": "Fix loading screen bug",
    "worker": "opencode",
    "branch": "main",
    "reviewer": "different",
    "timeout_minutes": 30,
    "verification_commands": ["npm test"],
    "priority": "normal",
    "labels": ["bugfix"]
  }
]
```

### `/cloud status`
Check the status of a dispatched task.

**Usage:**
```
/cloud status <task-id>
```

### `/cloud list-workers`
List available worker profiles and their capabilities.

**Usage:**
```
/cloud list-workers
```

### `/cloud logs`
View logs for a running or completed task.

**Usage:**
```
/cloud logs <task-id>
```

### `/cloud retry`
Retry a failed task.

**Usage:**
```
/cloud retry <task-id> [--worker opencode]
```

### `/cloud cancel`
Cancel a running task.

**Usage:**
```
/cloud cancel <task-id>
```

### `/register-repo`
Register a repository with Cloud Agent HQ.

**Usage:**
```
/register-repo <owner/repo> [--public|--private] [--branch main] [--workers opencode,codex] [--notes "description"]
```

## Installation

1. Copy this skill directory to your Hermes skills directory:
   ```
   cp -r cloud-agent-hq ~/.hermes/skills/
   ```

2. Ensure the dispatch script is executable:
   ```
   chmod +x ~/.hermes/skills/cloud-agent-hq/scripts/dispatch-task.py
   ```

3. Install Python dependencies:
   ```
   pip install pyyaml jsonschema
   ```

4. Reload Hermes skills or restart Hermes.

## Configuration

The skill uses the Cloud Agent HQ repository at `Chimthuwu/Cloud-Agent-HQ` by default. This can be overridden by setting the `CLOUD_AGENT_HQ_REPO` environment variable.

Required GitHub secrets in the Cloud-Agent-HQ repository:
- `OPENCODE_GO_API_KEY` - OpenCode API key
- `CLOUD_AGENT_HQ_PAT` - GitHub PAT with repo scope for target repositories
- `OPENAI_API_KEY` - For Codex (when implemented)
- `GOOGLE_API_KEY` - For Gemini (when implemented)
- `ANTHROPIC_API_KEY` - For Claude Code (when implemented)

## Architecture

Cloud Agent HQ uses GitHub Actions as the compute layer:
1. Hermes dispatches task via `/cloud dispatch` → triggers `dispatch-task.yml` workflow
2. Dispatch workflow validates task, checks registries, creates tracking issue
3. Dispatch workflow triggers appropriate worker workflow (`worker-opencode.yml`, etc.)
4. Worker workflow:
   - Checks out target repository
   - Creates isolated branch
   - Runs worker adapter (OpenCode/Codex/Gemini/Claude)
   - Commits changes, pushes branch
   - Creates Pull Request with execution report
5. Review workflow (`review-pr.yml`) can be triggered for independent review
6. Results reported back via GitHub Issues and PR comments

## Repository Detection Policy

This skill enforces the global repository-detection policy:
- Before any development task, checks for existing Git repository
- If found, identifies exact GitHub repo and inspects state
- If not found, prompts user before creating repository
- Public repos auto-adopt cloud workflow
- Private repos require minute budget verification

## Security

- No credentials stored in repository
- GitHub secrets used for all API keys
- Least-privilege GITHUB_TOKEN permissions
- Workers cannot modify workflows or registries
- Independent review required before merge

## Cost

- $0/month for public repositories (GitHub Actions free tier)
- Private repositories consume included Actions minutes
- AI inference via existing free-tier providers (OpenRouter, etc.)

## Documentation

- [Architecture](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/ARCHITECTURE.md)
- [Worker Adapters](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/WORKER_ADAPTERS.md)
- [Task Contract](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/TASK_CONTRACT.md)
- [Repository Registry](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/REPOSITORY_REGISTRY.md)
- [Review Policy](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/REVIEW_POLICY.md)
- [Security](https://github.com/Chimthuwu/Cloud-Agent-HQ/blob/main/docs/SECURITY.md)