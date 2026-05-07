---
name: rebase-mrs-review
description: Reads the latest state from the rebase-mrs launchd agent and gives the user a triage briefing — what's been rebased, which approved MRs are stale, which had conflicts, and proposes next actions. Use when the user types `/rebase-mrs-review`, asks "what's the state of my MRs?", "any rebase warnings?", "what did the auto-rebase do this morning?", or wants a morning MR triage.
---

# Rebase MRs — Review

Sibling skill to `/rebase-mrs`. The deterministic auto-rebase work runs hourly via launchd and writes state to `~/.cache/rebase-mrs/state.json`. This skill reads that state and helps the user triage what's left.

## Step 1 — Read state

```bash
cat ~/.cache/rebase-mrs/state.json
```

If the file doesn't exist, tell the user the launchd agent hasn't run yet (or the manual `/rebase-mrs` was never invoked) and stop. Don't fabricate state.

If `last_run` is more than 2 hours old AND the current local time is within working hours (Mon–Fri, hours covered by the user's launchd schedule), flag this — the agent may have failed silently. Suggest checking `~/Library/Logs/rebase-mrs.log`.

## Step 2 — Briefing format

Present the state as a tight briefing, not a JSON dump. Use this structure:

```
🟢 Last run: <last_run> — <status>
   Scanned <scanned>, rebased <rebased>, warned <warned>, conflicts <conflicts>, skipped <skipped>.

⚠️  Approved + stale (manual rebase needed):
   1. <title> — <project>
      Behind <diverged> on `<target>`, last updated <age_hours>h ago, <approvers> approver(s)
      First flagged: <first_seen>  (stale for <X> days)
      <url>
   ...

🔴 Conflicts:
   1. <title> — <project>
      <merge_error>
      <url>
   ...

📈 Recently rebased (last 24h):
   • <title> (was behind <diverged_was>) — <at>
```

Skip any sections that have zero items. If everything is empty, say "All clear — nothing waiting on you."

## Step 3 — Next actions

After the briefing, propose specific next actions based on what's there:

- **For each approved+stale warning**: ask if the user wants to (a) draft a Slack nudge to a reviewer/maintainer, (b) manually trigger a rebase via `glab` (which would invalidate approvals — confirm before doing this), or (c) leave it.
- **For each conflict**: don't try to resolve. Open the MR URL in the user's response so they can click through. Offer to investigate the conflict by reading the MR's diff and target branch HEAD if they want help diagnosing.
- **If nothing actionable**: just say "all clear" and stop. Don't manufacture work.

## Step 4 — Slack drafts (optional)

If the user asks to draft a nudge, write it in their voice. Per their casual-but-professional style:
- No exclamation points
- No em dashes
- Short sentences
- Plainly state the situation

Example tone:
> hey, mind taking another look at <MR>? been sitting approved+stale for a few days, just want to make sure i'm not blocking on anything before i rebase

Don't actually send it via Slack MCP unless the user explicitly says "send it". Just produce the draft for them to copy.

## Notes / guardrails

- This skill is **read-only by default**. It does not trigger rebases, send Slack messages, or modify MRs unless the user explicitly asks.
- If the user wants to force a fresh deterministic run before reviewing, they can invoke `/rebase-mrs` first, then `/rebase-mrs-review`.
- Don't run `glab` calls from this skill. Trust the state file. If the state seems suspicious or stale, tell the user instead of going around it.
