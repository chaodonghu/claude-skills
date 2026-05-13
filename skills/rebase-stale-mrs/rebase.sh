#!/bin/bash
# Rebase all of my open, non-draft, unapproved MRs across ALL GitLab projects
# via GitLab's server-side rebase API. No local clones required.
#
# Each MR is rebased onto its own target branch (which for the user's workflow
# is typically staging — falling back to main/master per repo by virtue of how
# the MR was opened).

set -u

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*"; }

command -v glab >/dev/null 2>&1 || { log "glab not on PATH"; exit 1; }
command -v jq   >/dev/null 2>&1 || { log "jq not on PATH"; exit 1; }

log "Fetching my open, non-draft MRs across all projects..."
mrs=$(glab api 'merge_requests?scope=created_by_me&state=opened&wip=no&per_page=100' 2>/dev/null)

if [ -z "$mrs" ] || [ "$mrs" = "[]" ] || [ "$mrs" = "null" ]; then
  log "No open non-draft MRs found."
  exit 0
fi

total=$(echo "$mrs" | jq 'length')
log "Found $total open non-draft MR(s)."

rebased=0; skipped_approved=0; skipped_uptodate=0; failed=0

echo "$mrs" | jq -r '.[] | [.project_id, .iid, .source_branch, .target_branch, .references.full, .title] | @tsv' \
| while IFS=$'\t' read -r pid iid source target ref title; do
  echo ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "$ref — $title"
  log "  $source → $target"

  # Skip if any approvals
  approvals=$(glab api "projects/$pid/merge_requests/$iid/approvals" 2>/dev/null)
  approved_count=$(echo "$approvals" | jq -r '(.approved_by // []) | length' 2>/dev/null)
  if [ "${approved_count:-0}" -gt 0 ]; then
    log "  ⏭  Skipping — has $approved_count approval(s)"
    continue
  fi

  # Skip if already up to date
  diverged=$(echo "$approvals" | jq -r '.merge_status // empty' 2>/dev/null)
  detail=$(glab api "projects/$pid/merge_requests/$iid?include_diverged_commits_count=true" 2>/dev/null)
  behind=$(echo "$detail" | jq -r '.diverged_commits_count // 0' 2>/dev/null)
  if [ "${behind:-0}" -eq 0 ]; then
    log "  ✓ Already up to date with $target"
    continue
  fi
  log "  Behind $target by $behind commit(s)"

  # Trigger server-side rebase
  resp=$(glab api --method PUT "projects/$pid/merge_requests/$iid/rebase" 2>&1)
  if echo "$resp" | jq -e '.rebase_in_progress == true' >/dev/null 2>&1; then
    log "  ✓ Rebase queued"
  else
    log "  ✗ Rebase request failed: $(echo "$resp" | head -c 200)"
  fi
done

echo ""
log "✓ Done. View results: glab mr list --author=@me"
