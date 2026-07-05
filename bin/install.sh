#!/usr/bin/env bash
# Symlinks skills (skills/<name>/) into ~/.claude/skills/ and workflows
# (workflows/<name>.js) into ~/.claude/workflows/, so Claude Code picks them up
# in every project. Re-run after adding or pulling new skills/workflows.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# link_one <source-path> <dest-path>: idempotent symlink with clear logging.
link_one() {
  local src="$1" dest="$2" name
  name="$(basename "$dest")"
  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then
      echo "ok     $name (already linked)"
      return
    fi
    echo "relink $name (was -> $(readlink "$dest"))"
    rm "$dest"
  elif [ -e "$dest" ]; then
    echo "skip   $name (real file/dir exists at $dest, not overwriting)"
    return
  else
    echo "link   $name"
  fi
  ln -s "$src" "$dest"
}

# Skills: one symlink per directory under skills/.
SKILLS_SRC="$REPO_ROOT/skills"
SKILLS_DEST="$HOME/.claude/skills"
if [ -d "$SKILLS_SRC" ]; then
  mkdir -p "$SKILLS_DEST"
  echo "Skills -> $SKILLS_DEST"
  for skill_dir in "$SKILLS_SRC"/*/; do
    [ -d "$skill_dir" ] || continue
    link_one "${skill_dir%/}" "$SKILLS_DEST/$(basename "$skill_dir")"
  done
  echo
fi

# Workflows: one symlink per file under workflows/ (e.g. *.js).
WORKFLOWS_SRC="$REPO_ROOT/workflows"
WORKFLOWS_DEST="$HOME/.claude/workflows"
if [ -d "$WORKFLOWS_SRC" ]; then
  mkdir -p "$WORKFLOWS_DEST"
  echo "Workflows -> $WORKFLOWS_DEST"
  for wf in "$WORKFLOWS_SRC"/*; do
    [ -f "$wf" ] || continue
    link_one "$wf" "$WORKFLOWS_DEST/$(basename "$wf")"
  done
  echo
fi

echo "Done."
