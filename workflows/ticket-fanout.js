export const meta = {
  name: 'ticket-fanout',
  description:
    'Autonomously implement N tickets/tasks in parallel, any git repo. Per item, an isolated-worktree agent implements to a green project check and a draft MR/PR, then a reviewer agent reviews the diff. Repo conventions (check/install/MR tool/branch naming) are detected from the repo or passed via args.',
  whenToUse:
    'Batches of small, independent tickets you will review after the fact (hands-off). NOT for work needing live QA/dev-server steering, and not for tickets that touch the same files (they collide at merge).',
  phases: [
    { title: 'Implement', detail: 'isolated worktree per item: install, implement, project check, push, draft MR/PR' },
    { title: 'Review', detail: 'one reviewer agent per diff (origin/main...branch), report-only' },
  ],
}

// Everything repo-specific is either passed in args or DETECTED by the agent.
// args forms:
//   ["ENG-1","ENG-2"]                          -> tickets, all defaults
//   [{key:"ENG-1", spec:"what to build"}, ...] -> tickets with inline specs
//   { tickets:[...], repoPath, install, check, bootstrapFiles, contextCommand, mrTool, baseBranch }
function parseArgs(a) {
  if (!a) {
    throw new Error(
      'Pass args: a list of tickets, or {tickets, ...config}. A ticket is a key string or {key, spec}. Config (all optional): repoPath, install, check, bootstrapFiles[], contextCommand ("{key}" substituted), mrTool ("glab"|"gh"|"auto"), baseBranch (default "main").',
    )
  }
  const cfg = Array.isArray(a) ? { tickets: a } : a
  const rawTickets = cfg.tickets || []
  const tickets = rawTickets.map((t) =>
    typeof t === 'string' ? { key: t, spec: '' } : { key: t.key, spec: t.spec || '' },
  )
  if (tickets.length === 0) throw new Error('No tickets provided in args.')
  return {
    tickets,
    repoPath: cfg.repoPath || '',
    install: cfg.install || '',
    check: cfg.check || '',
    bootstrapFiles: cfg.bootstrapFiles || [],
    contextCommand: cfg.contextCommand || '',
    mrTool: cfg.mrTool || 'auto',
    baseBranch: cfg.baseBranch || 'main',
  }
}

const MR_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['ticket', 'status'],
  properties: {
    ticket: { type: 'string' },
    status: { type: 'string', enum: ['done', 'blocked'] },
    branch: { type: 'string' },
    mrUrl: { type: 'string' },
    checkPassed: { type: 'boolean' },
    summary: { type: 'string' },
    blockedReason: { type: 'string' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['ticket', 'verdict'],
  properties: {
    ticket: { type: 'string' },
    verdict: { type: 'string', enum: ['approve', 'request_changes', 'skipped'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'note'],
        properties: {
          severity: { type: 'string' },
          file: { type: 'string' },
          note: { type: 'string' },
        },
      },
    },
  },
}

function implementPrompt(t, c) {
  const primary = c.repoPath
    ? `The primary checkout is ${c.repoPath}.`
    : `Find the primary checkout: run \`git rev-parse --git-common-dir\` in this worktree; its parent directory is the primary checkout.`
  const bootstrap = c.bootstrapFiles.length
    ? `2. Bootstrap: copy these gitignored files from the primary checkout into THIS worktree if missing (copies, not symlinks): ${c.bootstrapFiles.join(', ')}.`
    : `2. Bootstrap: this repo needs no extra gitignored files (none specified).`
  const install = c.install
    ? `Run: ${c.install} (with dangerouslyDisableSandbox) and wait for it.`
    : `Detect the package manager from the lockfile (pnpm-lock.yaml -> pnpm, package-lock.json -> npm, yarn.lock -> yarn) and run its install (with dangerouslyDisableSandbox); wait for it.`
  const check = c.check
    ? `Run: ${c.check} (with dangerouslyDisableSandbox) until it is GREEN.`
    : `Detect and run the repo's full pre-merge check (typecheck + lint + tests). Prefer a "check" script in package.json; otherwise read AGENTS.md / CONTRIBUTING / README for the gate. Run it with dangerouslyDisableSandbox until GREEN.`
  const context = c.contextCommand
    ? `3. Read the ticket context: run \`${c.contextCommand.replace('{key}', t.key)}\`.${t.spec ? ' Operator scope hint: ' + t.spec : ''}`
    : `3. The work to do${t.spec ? ' is: ' + t.spec : ' is described by the ticket key ' + t.key + '; if that is not enough context, STOP and report blocked (do not guess).'}`
  const mr =
    c.mrTool === 'glab'
      ? `push and open a DRAFT merge request into ${c.baseBranch} via glab.`
      : c.mrTool === 'gh'
        ? `push and open a DRAFT pull request into ${c.baseBranch} via gh.`
        : `push and open a DRAFT MR/PR into ${c.baseBranch}. Detect the host from the origin remote URL: gitlab.com -> use glab (draft MR), github.com -> use gh (draft PR).`

  return `You are implementing ticket ${t.key} end to end, UNATTENDED, in your own isolated git worktree (already created; you are in it). ${primary}

Do exactly this:
1. git fetch origin ${c.baseBranch}. Create branch ${t.key}-<short-slug> off origin/${c.baseBranch}.
${bootstrap}
   Then install dependencies: ${install}
${context}
4. Implement incrementally, matching the repo's conventions (read AGENTS.md / CONTRIBUTING / CLAUDE.md and mirror nearby code). If the ticket changes UI and the repo has a design-system pointer rule (.cursor/rules or .claude/rules), follow it before editing UI.
5. ${check} Never bypass pre-commit hooks (no --no-verify / HUSKY=0).
6. Commit using the repo's convention (detect from recent git log and AGENTS.md/CONTRIBUTING). Default subject style: "${t.key}: Capitalized description".
7. Then ${mr} Put "Refs: ${t.key}" (or the repo's linking convention) in the body and title it "${t.key}: <description>".
8. If the work is ambiguous, needs a product/design decision, or the check cannot be made green without out-of-scope changes: STOP, set status "blocked" with a clear blockedReason, do NOT guess and do NOT open an MR/PR.

Your final message IS the structured result (ticket, status done|blocked, branch, mrUrl, checkPassed, one-line summary, blockedReason if blocked). No prose outside it.`
}

function reviewPrompt(mr, t, c) {
  const root = c.repoPath || '.'
  return `Report-only review of ${t.key} on branch ${mr.branch} (${mr.mrUrl || 'no MR url'}). Do NOT modify code or post comments.

Get the diff (git refs are shared across worktrees):
  git -C ${root} fetch origin ${mr.branch} --quiet
  git -C ${root} diff origin/${c.baseBranch}...origin/${mr.branch}

Review across correctness, tests/coverage, security, and the repo's own conventions (AGENTS.md / CONTRIBUTING). Be concrete and cite files. Judge whether the project check would pass from the diff; do not re-run it.

Return: ticket "${t.key}", verdict (approve | request_changes), findings as [{severity, file, note}] (empty = clean).`
}

// ---- run ----

const c = parseArgs(args)
log(`Fanning out ${String(c.tickets.length)} ticket(s): ${c.tickets.map((t) => t.key).join(', ')} -> base ${c.baseBranch}`)

const results = await pipeline(
  c.tickets,
  (t) =>
    agent(implementPrompt(t, c), {
      label: `impl:${t.key}`,
      phase: 'Implement',
      isolation: 'worktree',
      schema: MR_SCHEMA,
    }),
  (mr, t) => {
    if (!mr || mr.status !== 'done' || !mr.branch) {
      return { mr, review: { ticket: t.key, verdict: 'skipped', findings: [] } }
    }
    return agent(reviewPrompt(mr, t, c), {
      label: `review:${t.key}`,
      phase: 'Review',
      schema: REVIEW_SCHEMA,
    }).then((review) => ({ mr, review }))
  },
)

const rows = results.filter(Boolean)
const done = rows.filter((r) => r.mr && r.mr.status === 'done')
log(`Done: ${String(done.length)} implemented, ${String(rows.length - done.length)} blocked/failed.`)

return {
  summary: rows.map((r) => ({
    ticket: r.mr ? r.mr.ticket : r.review && r.review.ticket,
    status: r.mr ? r.mr.status : 'failed',
    mrUrl: r.mr ? r.mr.mrUrl : undefined,
    checkPassed: r.mr ? r.mr.checkPassed : undefined,
    verdict: r.review ? r.review.verdict : undefined,
    findings: r.review ? r.review.findings : undefined,
    blockedReason: r.mr ? r.mr.blockedReason : undefined,
  })),
}
