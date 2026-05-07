#!/usr/bin/env bash
# Unloads and removes the rebase-mrs launchd agent.

set -euo pipefail

LABEL="com.claude-skills.rebase-mrs"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$DEST"

echo "Removed: $DEST"
echo "Logs left at $HOME/Library/Logs/rebase-mrs.log (delete by hand if you want)."
