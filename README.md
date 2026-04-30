# claude-skills

Personal collection of custom skills for Claude Code.

Each skill lives in `skills/<name>/SKILL.md` and gets symlinked into `~/.claude/skills/<name>/` so Claude Code picks it up.

## Install

```bash
./bin/install.sh
```

Re-run after adding a new skill.

## Skills

- **rephrase** — paste text, get it rephrased clearer and more empathetic in your voice. Trigger: `/rephrase <text>` (or `/rephrase` then paste in the next message).

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
