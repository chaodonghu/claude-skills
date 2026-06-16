---
name: create-skill
description: Create a new Claude Code skill interactively. Use when the user wants to create a skill, custom command, or extend Claude's capabilities.
metadata:
  tags:
    - meta-authoring
  status: recommended
argument-hint: "[personal|project] [skill-name]"
disable-model-invocation: true
---

# Create a Claude Code Skill

Help the user create a new skill following the Claude Code skills system.

## Documentation Reference

Full documentation: https://code.claude.com/docs/en/skills

## Your Task

### 1. Gather Requirements

If not already provided, ask the user:

1. **What should the skill do?** Get a clear description of the purpose
2. **Example usage** - How would they invoke it? What would they say?
3. **Location preference:**
   - `personal` (~/.claude/skills/) - Available across all projects
   - `project` (.claude/skills/) - This project only, shared with team

### 2. Choose Tags

Every skill **must** have at least one tag under `metadata.tags`. Read `allowed-tags.yaml` in the repo root for the current list of allowed tags and their descriptions. To add a new tag, open a PR to update that file.

### 3. Determine Configuration

Based on the user's description, determine the appropriate frontmatter:

**Invocation Control:**
- If the skill has side effects (deploy, commit, send messages) → `disable-model-invocation: true`
- If it's background knowledge Claude should use automatically → `user-invocable: false`
- If both you and Claude should be able to invoke it → use defaults

**Execution Context:**
- If the skill is a self-contained task that doesn't need conversation history → `context: fork`
- If using `context: fork`, suggest an appropriate `agent`:
  - `Explore` - Read-only codebase exploration
  - `Plan` - Architecture and planning tasks
  - `general-purpose` - Full capabilities (default)

**Tools:**
- If the skill should have restricted capabilities → specify `allowed-tools`
- Common patterns:
  - Read-only: `Read, Grep, Glob`
  - Git operations: `Bash(git:*)`
  - Python scripts: `Bash(python:*)`

### 4. Create the Skill

**Directory structure:**
```
<skill-name>/
├── SKILL.md           # Main instructions (required)
├── templates/         # Optional templates
├── examples/          # Optional examples
└── scripts/           # Optional helper scripts
```

**Frontmatter reference:**
```yaml
---
name: skill-name                    # Lowercase, hyphens only (max 64 chars)
description: What it does           # Claude uses this to decide when to load
metadata:
  tags:                             # Required — at least one tag from allowed-tags.yaml
    - workflow
argument-hint: "[arg1] [arg2]"       # Shown in autocomplete
disable-model-invocation: true      # Only user can invoke (for side effects)
user-invocable: false               # Only Claude can invoke (background knowledge)
allowed-tools: Read, Grep, Glob     # Restrict tool access
model: sonnet                       # Optional model override
context: fork                       # Run in isolated subagent
agent: Explore                      # Subagent type when context: fork
---
```

**String substitutions:**
- `$ARGUMENTS` - All arguments passed when invoking
- `${CLAUDE_SESSION_ID}` - Current session ID

**Dynamic context injection:**
- Syntax: exclamation mark + backtick + command + backtick (e.g., `! + \`git status\``)
- Runs shell command before skill loads, output replaces the placeholder
- See documentation for examples: https://code.claude.com/docs/en/skills#inject-dynamic-context

### 5. Write the Skill Content

The markdown content should include:
1. Clear instructions for what Claude should do
2. Step-by-step process if it's a task
3. Guidelines and constraints
4. Examples of expected output (if helpful)
5. References to supporting files (if any)

### 6. Create Supporting Files (Optional)

For complex skills, offer to create:
- `reference.md` - Detailed API docs or specifications
- `examples.md` - Usage examples
- `templates/` - Templates for Claude to fill in
- `scripts/` - Helper scripts Claude can execute

Reference supporting files from SKILL.md:
```markdown
## Additional resources
- For complete API details, see [reference.md](reference.md)
- For usage examples, see [examples.md](examples.md)
```

## Example Transformations

### Example 1: Task Skill (User-Invoked)

**User request:** "Create a skill to deploy to staging"

**Generated skill** (`~/.claude/skills/deploy-staging/SKILL.md`):
```yaml
---
name: deploy-staging
description: Deploy the application to staging environment
disable-model-invocation: true
allowed-tools: Bash(git:*), Bash(npm:*), Bash(ssh:*)
---

Deploy the application to staging:

1. Ensure all tests pass: `npm test`
2. Build the application: `npm run build`
3. Deploy to staging server
4. Verify deployment succeeded
5. Report the deployment URL
```

### Example 2: Reference Skill (Claude-Invoked)

**User request:** "Create a skill with our API conventions"

**Generated skill** (`.claude/skills/api-conventions/SKILL.md`):
```yaml
---
name: api-conventions
description: API design patterns and conventions for this codebase. Use when writing API endpoints, reviewing API code, or discussing API design.
user-invocable: false
---

When working with APIs in this codebase:

## Naming Conventions
- Use RESTful resource naming: `/users`, `/users/{id}`
- Use kebab-case for multi-word resources: `/user-settings`

## Response Format
All responses follow this structure:
```json
{
  "data": { ... },
  "meta": { "timestamp": "...", "requestId": "..." }
}
```

## Error Handling
Return appropriate HTTP status codes with error details:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable message",
    "details": { ... }
  }
}
```
```

### Example 3: Subagent Skill (Forked Context)

**User request:** "Create a skill to analyze dependencies"

**Generated skill** (`~/.claude/skills/analyze-deps/SKILL.md`):
```yaml
---
name: analyze-deps
description: Analyze project dependencies for security issues, outdated packages, and optimization opportunities
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(npm:*), Bash(yarn:*)
---

Analyze the project's dependencies:

1. **Find dependency files**: Look for package.json, requirements.txt, go.mod, Cargo.toml, etc.

2. **Check for issues**:
   - Outdated packages (major versions behind)
   - Known security vulnerabilities
   - Unused dependencies
   - Duplicate/overlapping packages

3. **Generate report** with:
   - Summary of findings
   - Priority recommendations
   - Commands to fix issues

$ARGUMENTS
```

## Output

After creating the skill:
1. Show the full SKILL.md content
2. Confirm the file location
3. Explain how to use it (invoke with `/skill-name` or let Claude use it automatically)
4. Offer to create supporting files if the skill is complex
