#!/usr/bin/env bash
# Lists the authed user's open GitLab MRs across all projects (via
# `scope=created_by_me`, so whoever's logged into `glab` is the subject),
# decides rebase/warn/skip per MR, and (unless --dry-run) triggers server-side
# rebases for the unapproved-but-behind ones.
#
# Output:
#   - Stdout: human-readable summary table
#   - Stderr: per-MR action lines (rebase/warn/skip) as they happen
#   - For each warn item, a single line on stdout starting with `WARN_JSON:` followed by
#     a compact JSON object — so the calling skill can forward to Slack.
#   - State JSON written to $STATE_FILE (default ~/.cache/rebase-mrs/state.json) for
#     the rebase-mrs-review skill to consume. `first_seen` timestamps for warnings and
#     conflicts are preserved across runs so the review skill can compute "stale for N days".
#
# Exit codes:
#   0 — ran cleanly, regardless of how many MRs got rebased / warned / conflicted
#   1 — auth or network failure (couldn't list MRs at all)
#   2 — bad invocation

set -euo pipefail
DRY_RUN=0
WORKING_HOURS_ONLY=0
STALE_HOURS=24
REBASE_POLL_TIMEOUT=60   # seconds
REBASE_POLL_INTERVAL=3
STATE_FILE="${STATE_FILE:-$HOME/.cache/rebase-mrs/state.json}"
# Working-hours window is in *local* machine time. Override via env vars.
# Defaults to 9am-4pm local, weekdays.
START_HOUR="${START_HOUR:-9}"
END_HOUR="${END_HOUR:-16}"
# Don't re-emit WARN_JSON for the same URL more than once per N hours.
# Prevents hourly spam in /loop mode for persistent stale warnings.
NOTIFY_COOLDOWN_HOURS="${NOTIFY_COOLDOWN_HOURS:-24}"
NOW_ISO=$(date -u +%FT%TZ)

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --working-hours-only) WORKING_HOURS_ONLY=1; shift ;;
    --stale-hours) STALE_HOURS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: run.sh [--dry-run] [--working-hours-only] [--stale-hours N]"
      echo "Env: START_HOUR (default 9), END_HOUR (default 16) — local time, used with --working-hours-only"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$WORKING_HOURS_ONLY" = "1" ]; then
  dow=$(date +%u)   # 1=Mon ... 7=Sun
  hour=$(date +%H)
  hour=${hour#0}    # strip leading zero so arithmetic works on 08, 09
  hour=${hour:-0}
  if [ "$dow" -gt 5 ] || [ "$hour" -lt "$START_HOUR" ] || [ "$hour" -gt "$END_HOUR" ]; then
    echo "Outside working hours (Mon-Fri ${START_HOUR}-${END_HOUR} local). Skipping run." >&2
    exit 0
  fi
fi

now_epoch=$(date -u +%s)

# Load previous state (used both for notification cooldown checks during the run
# and for first_seen merging at the end).
prev_state='{}'
if [ -f "$STATE_FILE" ]; then
  prev_state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
fi

# 1. List all my open MRs across the instance.
mrs_json="$(glab api "merge_requests?scope=created_by_me&state=opened&per_page=100" 2>/dev/null)" || {
  echo "FATAL: glab api list failed" >&2
  exit 1
}

mr_count=$(jq 'length' <<<"$mrs_json")

rebased=0
warned=0
conflicts=0
skipped=0

# Accumulate rows for the summary table and JSON arrays for the state file.
declare -a rows
warnings_json='[]'
conflicts_json='[]'
rebased_json='[]'

append_json() {
  # $1 = var name (e.g. warnings_json), $2 = compact JSON object
  local var="$1" obj="$2"
  local cur="${!var}"
  printf -v "$var" '%s' "$(jq -c --argjson o "$obj" '. + [$o]' <<<"$cur")"
}

# Iterate using a stable JSON-per-line stream.
while IFS= read -r mr; do
  project_id=$(jq -r '.project_id' <<<"$mr")
  iid=$(jq -r '.iid' <<<"$mr")
  title=$(jq -r '.title' <<<"$mr")
  web_url=$(jq -r '.web_url' <<<"$mr")
  target_branch=$(jq -r '.target_branch' <<<"$mr")
  source_branch=$(jq -r '.source_branch' <<<"$mr")
  project_path=$(jq -r '.web_url | capture("gitlab.com/(?<p>.+)/-/merge_requests/").p' <<<"$mr")
  is_draft=$(jq -r '.draft // .work_in_progress // false' <<<"$mr")

  if [ "$is_draft" = "true" ]; then
    title=$(jq -r '.title' <<<"$mr")
    rows+=("$(printf '%s\t!%s\tskip\tdraft\t%s' "$project_path" "$iid" "$title")")
    echo "[skip] !$iid $project_path — draft" >&2
    skipped=$((skipped+1))
    continue
  fi

  # 2. Detail fetch (for diverged_commits_count + updated_at).
  detail=$(glab api "projects/$project_id/merge_requests/$iid?include_diverged_commits_count=true" 2>/dev/null) || {
    echo "[skip] !$iid in $project_path: detail fetch failed" >&2
    rows+=("$(printf '%s\t!%s\t-\t-\tdetail-fetch-failed' "$project_path" "$iid")")
    skipped=$((skipped+1))
    continue
  }

  diverged=$(jq -r '.diverged_commits_count // 0' <<<"$detail")
  updated_at=$(jq -r '.updated_at' <<<"$detail")
  has_conflicts=$(jq -r '.has_conflicts // false' <<<"$detail")

  # 3. Approvals.
  approvals=$(glab api "projects/$project_id/merge_requests/$iid/approvals" 2>/dev/null) || approvals='{"approved_by":[]}'
  approver_count=$(jq -r '(.approved_by // []) | length' <<<"$approvals")

  # Convert updated_at to epoch (portable: try gnu date then BSD).
  updated_epoch=$(date -u -d "$updated_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "${updated_at%.*}" +%s 2>/dev/null || echo 0)
  age_hours=0
  if [ "$updated_epoch" -gt 0 ]; then
    age_hours=$(( (now_epoch - updated_epoch) / 3600 ))
  fi

  # 4. Decide.
  reason=""
  action=""
  if [ "$diverged" = "0" ]; then
    action="skip"; reason="up-to-date"
    skipped=$((skipped+1))
  elif [ "$approver_count" -gt 0 ]; then
    if [ "$age_hours" -ge "$STALE_HOURS" ]; then
      action="warn"; reason="approved+stale (${age_hours}h)"
      warned=$((warned+1))

      # Check cooldown: when did we last notify about this URL?
      prev_notified=$(jq -r --arg url "$web_url" '.warnings_by_url[$url].last_notified_at // empty' <<<"$prev_state")
      should_notify=1
      if [ -n "$prev_notified" ]; then
        prev_epoch=$(date -u -d "$prev_notified" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$prev_notified" +%s 2>/dev/null || echo 0)
        if [ "$prev_epoch" -gt 0 ]; then
          notify_age=$(( (now_epoch - prev_epoch) / 3600 ))
          if [ "$notify_age" -lt "$NOTIFY_COOLDOWN_HOURS" ]; then
            should_notify=0
          fi
        fi
      fi

      # If we're notifying, last_notified_at = now. Otherwise preserve the prior value.
      if [ "$should_notify" = "1" ]; then
        notified_at="$NOW_ISO"
      else
        notified_at="$prev_notified"
      fi

      warn_obj=$(jq -nc \
        --arg url "$web_url" \
        --arg title "$title" \
        --arg target "$target_branch" \
        --arg project "$project_path" \
        --arg notified "$notified_at" \
        --argjson iid "$iid" \
        --argjson diverged "$diverged" \
        --argjson age "$age_hours" \
        --argjson approvers "$approver_count" \
        '{url:$url,title:$title,target:$target,project:$project,iid:$iid,diverged:$diverged,age_hours:$age,approvers:$approvers,last_notified_at:$notified}')

      if [ "$should_notify" = "1" ]; then
        # Emit WARN_JSON only when actually notifying — keeps the loop quiet for
        # persistent warnings within the cooldown window.
        echo "WARN_JSON: $warn_obj"
      fi
      append_json warnings_json "$warn_obj"
    else
      action="skip"; reason="approved (fresh)"
      skipped=$((skipped+1))
    fi
  else
    # Unapproved + behind → rebase (or pretend to).
    if [ "$DRY_RUN" = "1" ]; then
      action="would-rebase"; reason="dry-run"
      rebased=$((rebased+1))
    else
      # Trigger rebase.
      if ! glab api -X PUT "projects/$project_id/merge_requests/$iid/rebase" >/dev/null 2>&1; then
        action="conflict"; reason="rebase trigger failed"
        conflicts=$((conflicts+1))
        append_json conflicts_json "$(jq -nc --arg url "$web_url" --arg title "$title" --arg target "$target_branch" --arg project "$project_path" --argjson iid "$iid" --argjson diverged "$diverged" --arg merge_error "trigger failed" '{url:$url,title:$title,target:$target,project:$project,iid:$iid,diverged:$diverged,merge_error:$merge_error}')"
      else
        # Poll.
        elapsed=0
        merge_error=""
        in_progress=true
        while [ "$elapsed" -lt "$REBASE_POLL_TIMEOUT" ]; do
          sleep "$REBASE_POLL_INTERVAL"
          elapsed=$((elapsed + REBASE_POLL_INTERVAL))
          poll=$(glab api "projects/$project_id/merge_requests/$iid?include_rebase_in_progress=true" 2>/dev/null) || break
          in_progress=$(jq -r '.rebase_in_progress // false' <<<"$poll")
          if [ "$in_progress" = "false" ]; then
            merge_error=$(jq -r '.merge_error // ""' <<<"$poll")
            break
          fi
        done
        if [ "$in_progress" = "true" ]; then
          action="conflict"; reason="rebase timeout (${REBASE_POLL_TIMEOUT}s)"
          conflicts=$((conflicts+1))
          append_json conflicts_json "$(jq -nc --arg url "$web_url" --arg title "$title" --arg target "$target_branch" --arg project "$project_path" --argjson iid "$iid" --argjson diverged "$diverged" --arg merge_error "$reason" '{url:$url,title:$title,target:$target,project:$project,iid:$iid,diverged:$diverged,merge_error:$merge_error}')"
        elif [ -n "$merge_error" ] && [ "$merge_error" != "null" ]; then
          action="conflict"; reason="$merge_error"
          conflicts=$((conflicts+1))
          append_json conflicts_json "$(jq -nc --arg url "$web_url" --arg title "$title" --arg target "$target_branch" --arg project "$project_path" --argjson iid "$iid" --argjson diverged "$diverged" --arg merge_error "$merge_error" '{url:$url,title:$title,target:$target,project:$project,iid:$iid,diverged:$diverged,merge_error:$merge_error}')"
        else
          action="rebased"; reason="behind by $diverged"
          rebased=$((rebased+1))
          append_json rebased_json "$(jq -nc --arg url "$web_url" --arg title "$title" --arg target "$target_branch" --arg project "$project_path" --arg at "$NOW_ISO" --argjson iid "$iid" --argjson diverged "$diverged" '{url:$url,title:$title,target:$target,project:$project,iid:$iid,diverged_was:$diverged,at:$at}')"
        fi
      fi
    fi
  fi

  rows+=("$(printf '%s\t!%s\t%s\tbehind:%s\t%s — %s' "$project_path" "$iid" "$action" "$diverged" "$reason" "$title")")
  echo "[$action] !$iid $project_path — $reason" >&2

done < <(jq -c '.[]' <<<"$mrs_json")

# 5. Print summary.
echo
echo "MR auto-rebase summary ($(date -u +%FT%TZ))"
echo "Total open MRs scanned: $mr_count"
printf "Rebased: %d  Warned: %d  Conflicts: %d  Skipped: %d\n" "$rebased" "$warned" "$conflicts" "$skipped"
[ "$DRY_RUN" = "1" ] && echo "(dry-run — no rebases were actually triggered)"
echo
if [ "${#rows[@]}" -gt 0 ]; then
  printf '%s\n' "${rows[@]}" | column -t -s $'\t'
fi

# 6. Write state file (skipped on dry-run).
if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$(dirname "$STATE_FILE")"

  # Merge: preserve first_seen for warnings/conflicts that already existed by URL.
  # Append new rebases to a rolling list capped at 50 entries.
  jq -n \
    --argjson prev "$prev_state" \
    --argjson warnings "$warnings_json" \
    --argjson conflicts "$conflicts_json" \
    --argjson rebased "$rebased_json" \
    --argjson summary "$(jq -n --argjson s "$mr_count" --argjson r "$rebased" --argjson w "$warned" --argjson c "$conflicts" --argjson sk "$skipped" '{scanned:$s,rebased:$r,warned:$w,conflicts:$c,skipped:$sk}')" \
    --arg now "$NOW_ISO" \
    '
    def merge_first_seen(items; prev_map):
      items | map(. + {first_seen: (prev_map[.url].first_seen // $now)});

    ($prev.warnings_by_url // {}) as $prev_warns
    | ($prev.conflicts_by_url // {}) as $prev_conflicts
    | ($prev.recent_rebases // []) as $prev_rebases
    | {
        last_run: $now,
        last_run_status: "ok",
        summary: $summary,
        warnings_by_url: (
          merge_first_seen($warnings; $prev_warns)
          | map({key:.url, value:.}) | from_entries
        ),
        conflicts_by_url: (
          merge_first_seen($conflicts; $prev_conflicts)
          | map({key:.url, value:.}) | from_entries
        ),
        recent_rebases: ($rebased + $prev_rebases | .[0:50])
      }
    ' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
fi
