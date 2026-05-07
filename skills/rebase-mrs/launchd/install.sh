#!/usr/bin/env bash
# Installs the rebase-mrs launchd agent.
#
# Defaults: weekdays, 9am-4pm in the *local* timezone of this machine.
# Override with env vars:
#   START_HOUR=6 END_HOUR=13   (= 9am-4pm Eastern on a Pacific machine)
#   MINUTE=7                    (default 7 to avoid herd on the hour)
#
# Re-run any time to re-generate the plist with new hours.

set -euo pipefail

LABEL="com.claude-skills.rebase-mrs"
THIS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$THIS_DIR/$LABEL.plist.template"
SOURCE_SCRIPT="$(cd -P "$THIS_DIR/.." && pwd)/run.sh"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

# macOS TCC blocks background launchd jobs from accessing files under ~/Desktop,
# ~/Documents, ~/Downloads, etc. — even if the user's interactive shell can read them.
# To dodge this, we stage a copy of run.sh into ~/Library/Application Support/ and
# point launchd at the staged copy. Re-running install.sh refreshes it.
STAGE_DIR="$HOME/Library/Application Support/$LABEL"
SCRIPT_PATH="$STAGE_DIR/run.sh"

if [ ! -x "$SOURCE_SCRIPT" ]; then
  echo "FATAL: run.sh not found or not executable at $SOURCE_SCRIPT" >&2
  exit 1
fi

mkdir -p "$STAGE_DIR"
cp "$SOURCE_SCRIPT" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

START_HOUR="${START_HOUR:-9}"
END_HOUR="${END_HOUR:-16}"
MINUTE="${MINUTE:-7}"

if [ ! -f "$TEMPLATE" ]; then
  echo "FATAL: template not found at $TEMPLATE" >&2
  exit 1
fi

# Generate the StartCalendarInterval entries: weekdays (1-5), hours start..end.
intervals=""
for d in 1 2 3 4 5; do
  for ((h=START_HOUR; h<=END_HOUR; h++)); do
    intervals+="    <dict><key>Weekday</key><integer>$d</integer><key>Hour</key><integer>$h</integer><key>Minute</key><integer>$MINUTE</integer></dict>"$'\n'
  done
done
intervals="${intervals%$'\n'}"   # trim trailing newline

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# Substitute placeholders using bash parameter expansion (handles multiline cleanly).
content=$(<"$TEMPLATE")
content="${content//__HOME__/$HOME}"
content="${content//__SCRIPT_PATH__/$SCRIPT_PATH}"
content="${content//__INTERVALS__/$intervals}"
printf '%s' "$content" > "$DEST"

# Reload (bootout if already loaded; bootstrap fresh).
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$DEST"

echo "Installed: $DEST"
echo "Label:     $LABEL"
echo "Schedule:  Mon-Fri ${START_HOUR}:$(printf %02d "$MINUTE") through ${END_HOUR}:$(printf %02d "$MINUTE") (machine-local time)"
echo "Logs:      $HOME/Library/Logs/rebase-mrs.log"
echo
echo "Next runs (launchctl):"
launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E '(state|next run)' || true
