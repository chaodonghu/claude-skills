# claude-skills

Personal collection of custom skills for Claude Code.

Each skill lives in `skills/<name>/SKILL.md` and gets symlinked into `~/.claude/skills/<name>/` so Claude Code picks it up.

## Install

```bash
./bin/install.sh
```

Re-run after adding a new skill.

## Skills

- **coordinator** — orchestrate multiple worktree agents (spawn, monitor, communicate, merge) via `workmux`.
- **create-skill** — interactively author a new Claude Code skill.
- **merge** — commit, rebase, and merge the current branch.
- **open-pr** — write a PR description from conversation context and open PR creation in the browser.
- **rebase** — rebase the current branch with smart conflict resolution.
- **rebase-stale-mrs** — rebase your open, non-draft, unapproved GitLab MRs via the server-side rebase API.
- **rephrase** — paste text, get it rephrased clearer and more empathetic in your voice. Trigger: `/rephrase <text>` (or `/rephrase` then paste in the next message).
- **teach** — teacher mode: make sure you deeply understand the current session before moving on.
- **worktree** — launch one or more tasks in new git worktrees via `workmux`.

## Adding a new skill

1. Create `skills/<name>/SKILL.md` with frontmatter:
   ```
   ---
   name: <name>
   description: <when to use this skill>
   ---
   ```
2. Write the body — instructions Claude follows when the skill runs.
3. Run `./bin/install.sh` to symlink it.
4. Commit and push.
