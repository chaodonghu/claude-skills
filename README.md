# claude-toolkit

Personal collection of Claude Code skills and workflows.

- **Skills** live in `skills/<name>/SKILL.md` and symlink into `~/.claude/skills/<name>/`.
- **Workflows** live in `workflows/<name>.js` and symlink into `~/.claude/workflows/<name>.js`.

Both get picked up by Claude Code in every project once installed.

## Install

```bash
./bin/install.sh
```

Symlinks every skill and workflow into `~/.claude/`. Re-run after adding or pulling new ones.

## Skills

- **coordinator**: orchestrate multiple worktree agents (spawn, monitor, communicate, merge) via `workmux`.
- **create-skill**: interactively author a new Claude Code skill.
- **merge**: commit, rebase, and merge the current branch.
- **open-pr**: write a PR description from conversation context and open PR creation in the browser.
- **rebase**: rebase the current branch with smart conflict resolution.
- **rebase-mrs**: scans my open GitLab MRs across all projects, server-side rebases the unapproved-but-behind ones, and flags approved-but-stale ones. Schedule via `/loop 1h /rebase-mrs --working-hours-only` (inside Claude Code) or launchd (`skills/rebase-mrs/launchd/install.sh`, true set-and-forget). Trigger manually: `/rebase-mrs` (add `--dry-run` to preview).
- **rebase-mrs-review**: reads the rebase-mrs state file and gives a triage briefing: what's been rebased, which approved MRs are stale, conflicts, proposed next actions, optional Slack draft. Read-only. Trigger: `/rebase-mrs-review`.
- **rebase-stale-mrs**: rebase your open, non-draft, unapproved GitLab MRs via the server-side rebase API.
- **rephrase**: paste text, get it rephrased clearer and more empathetic in your voice. Trigger: `/rephrase <text>` (or `/rephrase` then paste in the next message).
- **teach**: teacher mode, make sure you deeply understand the current session before moving on.
- **worktree**: launch one or more tasks in new git worktrees via `workmux`.

## Workflows

Deterministic, multi-agent orchestration scripts for the Claude Code `Workflow` tool. Invoke with `Workflow({ name: "<name>", args: ... })`.

- **ticket-fanout**: autonomously implement N tickets/tasks in parallel, in any git repo. Per item, an isolated-worktree agent installs, implements to a green project check, and opens a draft MR/PR, then a reviewer agent reviews the diff. Repo conventions (check/install command, MR-vs-PR tool, branch naming) are detected from the repo or passed via `args`. Best for batches of small, independent tickets you review after the fact; not for work needing live QA or tickets that touch the same files.

  ```
  Workflow({ name: "ticket-fanout", args: ["ENG-1", "ENG-2"] })
  Workflow({ name: "ticket-fanout", args: {
    tickets: [{ key: "ENG-1", spec: "narrow the pagination" }],
    check: "pnpm check",
    bootstrapFiles: [".env.development.local"],
    contextCommand: "acli jira workitem view {key}",
  }})
  ```

## Adding a new skill

1. Create `skills/<name>/SKILL.md` with frontmatter:
   ```
   ---
   name: <name>
   description: <when to use this skill>
   ---
   ```
2. Write the body: instructions Claude follows when the skill runs.
3. Run `./bin/install.sh` to symlink it.
4. Commit and push.

## Adding a new workflow

1. Create `workflows/<name>.js`. It must `export const meta = { name, description, phases }` (a pure literal) followed by the script body using `agent()` / `pipeline()` / `parallel()`.
2. Run `./bin/install.sh` to symlink it into `~/.claude/workflows/`.
3. Invoke with `Workflow({ name: "<name>", args: ... })`.
4. Commit and push.
