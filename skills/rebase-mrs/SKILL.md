---
name: rebase-mrs
description: Scans the user's open GitLab MRs across all projects, rebases the unapproved-but-behind ones onto their target branch, and Slack-DMs warnings about approved-but-stale MRs. Use when the user types `/rebase-mrs`, when scheduled to run via the `/schedule` skill, or when the user asks to "rebase my MRs", "check my open MRs", or "see which MRs are out of date".
---

# Rebase My MRs

Runs one pass of GitLab MR auto-rebase logic for whoever is authed in `glab`:

- **Draft** → skip entirely (drafts aren't ready for review yet).
- **Behind & no approvals** → server-side rebase via GitLab API.
- **Behind & approved & last updated ≥24h ago** → Slack DM warning. No rebase (so we don't invalidate approvals).
- **Up to date, or approved but fresh** → skip.

## Setup (one-time)

Before first use, the user needs:

1. `glab` installed and authed: `glab auth status` should show the right user.
2. `jq` installed (`brew install jq`).
3. (Optional) `SLACK_DM_HANDLE` env var set to the Slack username/handle that should receive warnings. If unset, warnings print to chat instead of going to Slack. Example in `~/.zshrc`:
   ```bash
   export SLACK_DM_HANDLE="your-slack-username"
   ```

## Step 1 — Run the script

```bash
~/.claude/skills/rebase-mrs/run.sh
```

Add `--dry-run` for the first invocation in any new context, when troubleshooting, or when the user explicitly asks for a preview:

```bash
~/.claude/skills/rebase-mrs/run.sh --dry-run
```

The script writes:
- A summary table to stdout.
- One `WARN_JSON: {...}` line per approved-but-stale MR, also on stdout.
- Per-MR action lines to stderr.

If the script exits non-zero, surface the error and stop. Don't try to recover by hand.

## Step 2 — Slack DM warnings

After the script finishes, parse every `WARN_JSON: {...}` line from its stdout. **The script already de-duplicates within a 24h cooldown window, so any WARN_JSON line you see is meant to be sent.** Don't add your own dedup logic on top.

For each WARN_JSON line, you MUST send a Slack DM to the user identified by `$SLACK_DM_HANDLE` with this exact template (substitute the JSON fields):

```
:warning: MR out of date and not yet rebased (has approvals): <{url}|{title}>
Target: `{target}`  ·  behind by {diverged} commits  ·  last updated {age_hours}h ago  ·  {approvers} approver(s)
Skipping rebase to avoid invalidating approvals. Rebase manually when ready.
```

Procedure:
1. Read `$SLACK_DM_HANDLE`. If unset, print the warnings to chat instead and tell the user "SLACK_DM_HANDLE not set, skipping Slack DM." Do NOT try to send without a configured handle.
2. Call `mcp__claude_ai_Slack__slack_search_users` with the handle. Take the first matching user's identifier.
3. Call `mcp__claude_ai_Slack__slack_send_message` with that user as the destination and the templated message as the body. Use `mrkdwn` formatting so the `<{url}|{title}>` link renders.
4. If the Slack MCP tool is not available in the current run (e.g. you're being invoked outside a Claude Code session that has it loaded), fall back to printing to chat and explicitly say "Slack MCP unavailable, printed warnings to chat instead."

If there are zero `WARN_JSON:` lines, do not send any Slack message and do not say anything about Slack. Silence is the success state.

Failure handling: if `slack_search_users` returns nothing or `slack_send_message` errors, surface the error in chat and print the warning text. Do not retry silently.

## Step 3 — Report

Print the script's stdout summary back to the user (or to the run log). One short sentence on top: e.g. `Rebased 2, warned 1, 0 conflicts, 4 skipped.` Then the table.

If there were any conflicts, list them with their URLs at the bottom so the user can resolve them by hand. Do NOT try to resolve conflicts locally — the script intentionally only triggers server-side rebase.

## Scheduling

Two supported scheduling paths. Pick one based on whether you want it tied to your Claude Code session.

### Option A — `/loop` inside Claude Code (recommended for this user)

In an active Claude Code session, run:

```
/loop 1h /rebase-mrs --working-hours-only
```

This fires `/rebase-mrs --working-hours-only` once per hour while the session stays open. The `--working-hours-only` flag makes off-hours fires no-op fast (no GitLab calls, no token waste) so you can leave the loop running overnight or on weekends without it doing anything.

By default working hours are weekdays 9am–4pm in your **machine's local timezone**. Override with env vars before launching Claude Code:

```bash
# 9am-4pm Eastern on a Pacific machine:
export START_HOUR=6 END_HOUR=13
```

Tradeoffs:
- Requires Claude Code to be open. Loop dies when you close the session — re-invoke it the next morning.
- Each fire costs Claude tokens to wrap a deterministic bash script.

### Option B — launchd (true set-and-forget)

The launchd plist + install script live in `launchd/`. Runs whether or not Claude Code is open, survives reboots, no token cost per fire.

```bash
# 9am-4pm Eastern on a Pacific machine:
START_HOUR=6 END_HOUR=13 ~/.claude/skills/rebase-mrs/launchd/install.sh
```

Uninstall: `~/.claude/skills/rebase-mrs/launchd/uninstall.sh`. Logs at `~/Library/Logs/rebase-mrs.log`.

### Why not `/schedule` (remote routines)?

Remote agents run in Anthropic's cloud and don't have your `glab` auth. The only way to make them work is to put a GitLab personal access token in the routine prompt, which stores it in cloud config — not worth the leak risk for personal automation.

## State file

Both scheduling options write `~/.cache/rebase-mrs/state.json`. The `/rebase-mrs-review` skill reads that file for triage briefings.

## Notes / guardrails

- **Never force-push.** The script only uses GitLab's server-side rebase API, which is safe.
- **Never rebase an approved MR.** If the script logic ever changes, this rule must hold — some GitLab configurations invalidate approvals on rebase, so an approved MR getting silently rebased loses review state.
- **Never bypass conflicts.** If GitLab returns `merge_error`, that's a conflict — surface it and stop. The user resolves manually.
- **No commits posted to MRs, no comments left on GitLab.** Communication goes to Slack, not the MR threads.
