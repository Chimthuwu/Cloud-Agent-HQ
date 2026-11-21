#!/usr/bin/env python3
"""
Cloud Agent HQ — Hermes Dispatch Script
Dispatch tasks from Hermes CLI to Cloud Agent HQ GitHub Actions workflows.

Usage:
    python dispatch-task.py <repository> <instructions> [options]
    python dispatch-task.py --batch <tasks-file.json> [options]

Examples:
    python dispatch-task.py Chimthuwu/GameVolley "Fix the loading screen bug" --worker opencode
    python dispatch-task.py Chimthuwu/GameVolley "Add unit tests for game validation" --worker codex --reviewer human
    python dispatch-task.py --batch tasks.json --parallel 3
"""

import argparse
import json
import os
import sys
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List
import uuid

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

try:
    import yaml
except ImportError:
    print("PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)


class CloudAgentHQ:
    def __init__(self, hq_repo: str = "Chimthuwu/Cloud-Agent-HQ"):
        self.hq_repo = hq_repo
        self.gh_cli = "gh"
    
    def _run_gh(self, args: List[str], capture: bool = True) -> subprocess.CompletedProcess:
        """Run gh CLI command."""
        cmd = [self.gh_cli] + args
        result = subprocess.run(cmd, capture_output=capture, text=True)
        if result.returncode != 0 and capture:
            print(f"gh command failed: {' '.join(cmd)}")
            print(f"stderr: {result.stderr}")
        return result
    
    def _generate_task_id(self, repo: str) -> str:
        """Generate unique task ID."""
        repo_slug = repo.lower().replace("/", "-").replace(".", "-")
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        unique = uuid.uuid4().hex[:6]
        return f"{repo_slug}-{timestamp}-{unique}"
    
    def load_registry(self, registry_path: str) -> Dict[str, Any]:
        """Load YAML registry file."""
        with open(registry_path) as f:
            return yaml.safe_load(f)
    
    def validate_repository(self, repo: str, worker: str) -> Dict[str, Any]:
        """Check if repository is registered and supports the worker."""
        registry = self.load_registry(PROJECT_ROOT / "registry" / "repos.yaml")
        
        for r in registry.get("repositories", []):
            if r["name"] == repo:
                if worker not in r.get("worker_profiles", []):
                    raise ValueError(f"Worker '{worker}' not allowed for repository '{repo}'")
                if r.get("visibility") == "private" and not r.get("auto_dispatch", False):
                    raise ValueError(f"Private repository '{repo}' has auto_dispatch=false")
                return r
        
        raise ValueError(f"Repository '{repo}' not registered in Cloud-Agent-HQ")
    
    def validate_worker(self, worker: str) -> Dict[str, Any]:
        """Check if worker is defined in registry."""
        registry = self.load_registry(PROJECT_ROOT / "registry" / "workers.yaml")
        worker_config = registry.get("workers", {}).get(worker)
        
        if not worker_config:
            raise ValueError(f"Worker '{worker}' not defined in registry")
        
        return worker_config
    
    def build_task_contract(self, 
                           repo: str,
                           instructions: str,
                           worker: str,
                           base_branch: str = "main",
                           reviewer: str = "different",
                           timeout_minutes: int = 30,
                           verification_commands: Optional[List[str]] = None,
                           environment_vars: Optional[Dict[str, str]] = None,
                           tool_permissions: Optional[List[str]] = None,
                           priority: str = "normal",
                           labels: Optional[List[str]] = None,
                           metadata: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Build a task contract JSON."""
        task_id = self._generate_task_id(repo)
        
        task = {
            "task_id": task_id,
            "repository": repo,
            "base_branch": base_branch,
            "instructions": instructions,
            "worker_profile": worker,
            "reviewer_profile": reviewer,
            "timeout_minutes": timeout_minutes,
            "verification_commands": verification_commands or [],
            "environment_vars": environment_vars or {},
            "tool_permissions": tool_permissions or ["read", "write", "edit", "bash", "grep", "glob"],
            "priority": priority,
            "labels": labels or [],
            "metadata": metadata or {}
        }
        
        # Validate against schema
        schema_path = PROJECT_ROOT / "schemas" / "task-contract.json"
        if schema_path.exists():
            import jsonschema
            with open(schema_path) as f:
                schema = json.load(f)
            jsonschema.validate(task, schema)
        
        return task
    
    def dispatch_task(self, task: Dict[str, Any], dry_run: bool = False) -> Dict[str, Any]:
        """Dispatch a task via GitHub Actions workflow_dispatch."""
        task_json = json.dumps(task)
        
        if dry_run:
            print("=== DRY RUN ===")
            print(f"Task ID: {task['task_id']}")
            print(f"Repository: {task['repository']}")
            print(f"Worker: {task['worker_profile']}")
            print(f"Base Branch: {task['base_branch']}")
            print(f"Instructions: {task['instructions'][:100]}...")
            return {"success": True, "dry_run": True, "task_id": task["task_id"]}
        
        # Trigger dispatch workflow
        cmd = [
            "workflow", "run", "dispatch-task.yml",
            "--repo", self.hq_repo,
            "-f", f"task_json={task_json}",
            "-f", f"task_id={task['task_id']}",
            "-f", f"repository={task['repository']}",
            "-f", f"worker_profile={task['worker_profile']}",
            "-f", f"base_branch={task['base_branch']}",
            "-f", f"timeout_minutes={task.get('timeout_minutes', 30)}",
            "-f", f"tracking_issue=0"  # Will be created by workflow
        ]
        
        # Note: gh workflow run doesn't support passing JSON directly well
        # We'll use the API approach instead
        return self._dispatch_via_api(task)
    
    def _dispatch_via_api(self, task: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatch using GitHub API via gh."""
        task_json = json.dumps(task)
        
        # Use gh api to create workflow_dispatch event
        cmd = [
            "api", "--method", "POST",
            f"/repos/{self.hq_repo}/actions/workflows/dispatch-task.yml/dispatches",
            "-f", f"ref=main",
            "-f", f"inputs[task_json]={task_json}",
            "-f", f"inputs[dry_run]=false"
        ]
        
        result = self._run_gh(cmd)
        if result.returncode == 0:
            return {"success": True, "task_id": task["task_id"]}
        else:
            return {"success": False, "error": result.stderr}
    
    def check_task_status(self, task_id: str) -> Dict[str, Any]:
        """Check status of a dispatched task."""
        # Search for the tracking issue
        cmd = [
            "issue", "list",
            "--repo", self.hq_repo,
            "--label", "cloud-agent-task",
            "--search", task_id,
            "--json", "number,title,state,labels,body,updatedAt"
        ]
        
        result = self._run_gh(cmd)
        if result.returncode == 0:
            issues = json.loads(result.stdout)
            if issues:
                issue = issues[0]
                return {
                    "task_id": task_id,
                    "issue_number": issue["number"],
                    "title": issue["title"],
                    "state": issue["state"],
                    "labels": [l["name"] for l in issue["labels"]],
                    "updated_at": issue["updatedAt"]
                }
        return {"task_id": task_id, "found": False}
    
    def list_workers(self) -> List[Dict[str, Any]]:
        """List available worker profiles."""
        registry = self.load_registry(PROJECT_ROOT / "registry" / "workers.yaml")
        workers = []
        for name, config in registry.get("workers", {}).items():
            workers.append({
                "name": name,
                "display_name": config.get("name", name),
                "description": config.get("description", ""),
                "cli": config.get("cli", ""),
                "version": config.get("version_requirement", ""),
                "max_concurrent": config.get("max_concurrent", 0),
                "capabilities": config.get("capabilities", []),
                "supported_repos": config.get("supported_repositories", [])
            })
        return workers
    
    def register_repository(self, repo: str, visibility: str, 
                           default_branch: str = "main",
                           instructions_files: Optional[List[str]] = None,
                           worker_profiles: Optional[List[str]] = None,
                           auto_dispatch: bool = True,
                           notes: str = "") -> bool:
        """Register a new repository."""
        registry_path = PROJECT_ROOT / "registry" / "repos.yaml"
        registry = self.load_registry(registry_path)
        
        # Check if already registered
        for r in registry.get("repositories", []):
            if r["name"] == repo:
                print(f"Repository {repo} already registered")
                return False
        
        new_repo = {
            "name": repo,
            "visibility": visibility,
            "default_branch": default_branch,
            "registered_at": datetime.now().strftime("%Y-%m-%d"),
            "instructions_files": instructions_files or ["AGENTS.md", "CLAUDE.md", "README.md", "TODO.md"],
            "worker_profiles": worker_profiles or ["opencode", "codex", "gemini", "claude"],
            "review_required": True,
            "auto_dispatch": auto_dispatch,
            "notes": notes,
            "labels": [f"cloud-agent:{visibility}", "cloud-agent:ready"]
        }
        
        if visibility == "private":
            new_repo["minute_budget_check"] = True
            new_repo["auto_dispatch"] = False
        
        registry.setdefault("repositories", []).append(new_repo)
        
        with open(registry_path, "w") as f:
            yaml.dump(registry, f, default_flow_style=False, sort_keys=False)
        
        print(f"Registered {repo} ({visibility})")
        return True


def main():
    parser = argparse.ArgumentParser(description="Cloud Agent HQ - Hermes Dispatch")
    subparsers = parser.add_subparsers(dest="command", required=True)
    
    # dispatch command
    dispatch_parser = subparsers.add_parser("dispatch", help="Dispatch a single task")
    dispatch_parser.add_argument("repository", help="Target repository (owner/name)")
    dispatch_parser.add_argument("instructions", help="Task instructions")
    dispatch_parser.add_argument("--worker", default="opencode", choices=["opencode", "codex", "gemini", "claude"])
    dispatch_parser.add_argument("--branch", default="main")
    dispatch_parser.add_argument("--reviewer", default="different", choices=["opencode", "codex", "gemini", "claude", "human", "different"])
    dispatch_parser.add_argument("--timeout", type=int, default=30)
    dispatch_parser.add_argument("--verify", nargs="*", default=[], help="Verification commands")
    dispatch_parser.add_argument("--env", nargs="*", default=[], help="Environment variables as KEY=VALUE")
    dispatch_parser.add_argument("--priority", default="normal", choices=["low", "normal", "high", "urgent"])
    dispatch_parser.add_argument("--label", action="append", default=[], help="Labels to apply")
    dispatch_parser.add_argument("--dry-run", action="store_true", help="Validate only, don't dispatch")
    
    # batch command
    batch_parser = subparsers.add_parser("batch", help="Dispatch multiple tasks from JSON file")
    batch_parser.add_argument("file", help="JSON file with array of task objects")
    batch_parser.add_argument("--parallel", type=int, default=3, help="Max parallel dispatches")
    
    # status command
    status_parser = subparsers.add_parser("status", help="Check task status")
    status_parser.add_argument("task_id", help="Task ID to check")
    
    # list-workers command
    subparsers.add_parser("list-workers", help="List available worker profiles")
    
    # register-repo command
    register_parser = subparsers.add_parser("register-repo", help="Register a repository")
    register_parser.add_argument("repository", help="Repository (owner/name)")
    register_parser.add_argument("--visibility", required=True, choices=["public", "private"])
    register_parser.add_argument("--branch", default="main")
    register_parser.add_argument("--workers", nargs="*", default=["opencode", "codex", "gemini", "claude"])
    register_parser.add_argument("--notes", default="")
    
    args = parser.parse_args()
    
    hq = CloudAgentHQ()
    
    try:
        if args.command == "dispatch":
            env_vars = {}
            for e in args.env:
                if "=" in e:
                    k, v = e.split("=", 1)
                    env_vars[k] = v
            
            task = hq.build_task_contract(
                repo=args.repository,
                instructions=args.instructions,
                worker=args.worker,
                base_branch=args.branch,
                reviewer=args.reviewer,
                timeout_minutes=args.timeout,
                verification_commands=args.verify,
                environment_vars=env_vars,
                priority=args.priority,
                labels=args.label
            )
            
            result = hq.dispatch_task(task, dry_run=args.dry_run)
            if result.get("success"):
                print(f"✅ Task dispatched: {result['task_id']}")
                if not args.dry_run:
                    print(f"   Track at: https://github.com/{hq.hq_repo}/issues")
            else:
                print(f"❌ Dispatch failed: {result.get('error')}")
                sys.exit(1)
        
        elif args.command == "batch":
            with open(args.file) as f:
                tasks = json.load(f)
            
            if not isinstance(tasks, list):
                print("Batch file must contain a JSON array")
                sys.exit(1)
            
            print(f"Dispatching {len(tasks)} tasks (max {args.parallel} parallel)...")
            for i, task_data in enumerate(tasks):
                task = hq.build_task_contract(**task_data)
                result = hq.dispatch_task(task)
                if result.get("success"):
                    print(f"  [{i+1}/{len(tasks)}] ✅ {task['task_id']}")
                else:
                    print(f"  [{i+1}/{len(tasks)}] ❌ {task['task_id']}: {result.get('error')}")
                
                if i < len(tasks) - 1:
                    time.sleep(2)  # Rate limiting
        
        elif args.command == "status":
            status = hq.check_task_status(args.task_id)
            if status.get("found", True) and "issue_number" in status:
                print(f"Task: {status['task_id']}")
                print(f"Issue: #{status['issue_number']} - {status['title']}")
                print(f"State: {status['state']}")
                print(f"Labels: {', '.join(status['labels'])}")
                print(f"Updated: {status['updated_at']}")
            else:
                print(f"Task {args.task_id} not found")
        
        elif args.command == "list-workers":
            workers = hq.list_workers()
            print("Available Worker Profiles:")
            print("=" * 60)
            for w in workers:
                print(f"\n{w['name']} ({w['display_name']})")
                print(f"  CLI: {w['cli']} {w['version']}")
                print(f"  Description: {w['description']}")
                print(f"  Max Concurrent: {w['max_concurrent']}")
                print(f"  Capabilities: {', '.join(w['capabilities'])}")
                print(f"  Supported Repos: {', '.join(w['supported_repos'])}")
        
        elif args.command == "register-repo":
            hq.register_repository(
                repo=args.repository,
                visibility=args.visibility,
                default_branch=args.branch,
                worker_profiles=args.workers,
                notes=args.notes
            )
    
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()