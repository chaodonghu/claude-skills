#!/usr/bin/env bash
# Symlinks every skill in ./skills/ into ~/.claude/skills/.
# Re-run after adding a new skill or pulling new ones.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
SKILLS_DEST="$HOME/.claude/skills"

mkdir -p "$SKILLS_DEST"

for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  link_path="$SKILLS_DEST/$skill_name"

  if [ -L "$link_path" ]; then
    current_target="$(readlink "$link_path")"
    if [ "$current_target" = "${skill_dir%/}" ]; then
      echo "ok    $skill_name (already linked)"
      continue
    fi
    echo "relink $skill_name (was -> $current_target)"
    rm "$link_path"
  elif [ -e "$link_path" ]; then
    echo "skip  $skill_name (real file/dir exists at $link_path, not overwriting)"
    continue
  else
    echo "link  $skill_name"
  fi

  ln -s "${skill_dir%/}" "$link_path"
done

echo
echo "Done. Skills installed to $SKILLS_DEST"
