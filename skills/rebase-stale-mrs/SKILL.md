---
name: "Rebase Stale MRs"
description: "Rebase all of my open, non-draft, unapproved GitLab MRs across all projects via GitLab's server-side rebase API. Use when asked to '/rebase-stale-mrs', 'rebase my stale MRs', 'catch my MRs up', or when running a periodic background sweep during work hours."
---

# Rebase stale MRs

Runs `~/.claude/skills/rebase-stale-mrs/rebase.sh`. The script:

1. Queries `GET /merge_requests?scope=created_by_me&state=opened&wip=no` — returns my open non-draft MRs across every project I can see on the authenticated GitLab host.
2. For each MR, fetches `/projects/:id/merge_requests/:iid/approvals` and skips if `approved_by` is non-empty.
3. Skips if the MR is not behind its target branch (`diverged_commits_count == 0`).
4. Triggers `PUT /projects/:id/merge_requests/:iid/rebase` — GitLab performs the rebase server-side. No local clones, no force-push from this machine.

Each MR is rebased onto its own target branch (in Dong's workflow this is typically `staging`, with `main`/`master` as the per-repo fallback by virtue of how the MR was opened).

## How to invoke

Run via Bash:

```bash
~/.claude/skills/rebase-stale-mrs/rebase.sh
```

After it finishes, summarize: how many MRs were processed, how many rebases were queued, how many were skipped (approved / up to date), and how many failed.

## Requirements

- `glab` and `jq` on PATH
- `glab auth status` shows an authenticated host

## Running on a loop during work hours

To keep MRs caught up automatically while you're at your desk, pair this skill with Claude Code's `/loop`. The loop runs inside the current Claude session — it stops when you close Claude.

**Hourly during work hours (9am–5pm America/Toronto, weekdays):**

```
/loop 1h /rebase-stale-mrs
```

This fires once immediately and then every hour after. It does not gate on workday boundaries on its own — close the session at EOD or it will keep running overnight.

**For a true 9–5 weekday cron**, ask Claude to set it up directly via `CronCreate` (also session-only):

```
cron: 7 9-17 * * 1-5    (every weekday at :07 past the hour, 9am–5pm local)
prompt: /rebase-stale-mrs
```

The off-minute (`:07` vs `:00`) is intentional — it avoids hitting the API on the same instant as every other hourly cron on the planet.

**Cancel** with `CronDelete <job-id>` (the ID is returned when you create it).

## Notes

- Server-side rebase is async. The script reports "rebase queued" — actual completion is visible in GitLab a few seconds later.
- If the source branch is protected or the user lacks push rights, GitLab returns 403 and the script logs the failure.
