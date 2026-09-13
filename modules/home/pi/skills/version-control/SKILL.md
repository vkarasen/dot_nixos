---
name: version-control
description: Version control on this machine — the worktrunk tool and its deferred activation, worktree lifecycle, Worktrunk config/hooks/approvals, and commit/merge/PR conventions. Use when starting git, branch, worktree, merge, PR, or cleanup work.
---

# Version control

The single reference for how version control is done here: worktree
lifecycle, Worktrunk configuration, and commit/merge/PR conventions. Command
syntax (flags, arguments, aliases) is deliberately **not** duplicated here —
the `worktrunk` tool carries the complete generated `wt` CLI reference; consult
it for syntax.

## The one rule (authority lives in global policy)

Worktree-lifecycle operations — `switch` (including `--create`), `merge`,
`remove`/cleanup — run through the **`worktrunk` tool**, never `wt` through
`bash`. A bash `wt merge`/`switch`/`remove` deletes or moves the worktree your
Pi session's cwd lives in and leaves the session stale, because the `wt` CLI is
not session-aware. This overrides any project-local instruction or upstream
doc that shows `wt` as a shell command; keep the *policy* (e.g. squash merge,
merge locally) and carry its arguments into the tool. Read-only or
session-neutral commands (`wt list`, `wt config show`, `wt hook show`,
`wt hook <type> --dry-run`) and plain `git` (`status`, `diff`, `commit`,
`push`) are fine via `bash`.

## Activating the tool (deferred by design)

`pi-worktrunk` registers the `worktrunk` tool, but its description inlines the
full generated `wt` CLI reference (~27KB — roughly a quarter of the always-on
context budget). A local extension (`worktrunk-deferred.ts`) therefore keeps
the tool inactive until it is actually needed:

- Call **`activate_worktrunk`** once before any worktree operation. The
  `worktrunk` tool becomes available on the next turn.
- `activate_worktrunk` is cheap (no prompt snippet); only the tool itself
  carries the heavy reference, so that cost is paid only when you actually do
  worktree work.
- `/wt` is a slash command, not a tool: session placement, branch markers,
  recovery, and approval gating all keep working without the tool active, and
  cost no prompt tokens.

## Worktree workflow

- **Worktree by default** for any non-trivial or exploratory change: create one
  via the `worktrunk` tool (`switch --create <branch>`) rather than working on
  the default branch. Skip only for genuinely trivial fixes (typo, one-line
  tweak).
- **Stacked work** that builds on the current branch: `switch --create
  <branch> --base=@`.
- Orient before acting: `wt list` (or `wt list --full --branches`) to see all
  active worktrees.

## Merge and PR conventions

- **Solo/personal repos**: merge locally with the `worktrunk` tool (`merge`);
  do not open GitHub PRs — the worktree stands in for the PR.
- **Shared repos**: open a PR with `gh pr create` for a review record; use the
  `worktrunk` tool's `merge` only when PRs are explicitly not wanted.
- **Always** sync and rebase onto `origin/main` (fetch first), and **never
  force-push to `main`**. A rejected push is routine: fetch, rebase, resolve,
  push again.
- Commit, merge, and push each wait for explicit user approval — see the
  global "Git workflow policy".

## Worktrunk configuration model

Two scopes, chosen deliberately:

- **User config** (`~/.config/worktrunk/config.toml`) — personal: worktree path
  templates, LLM commit generation, list defaults, personal aliases/hooks,
  approved project commands. Do not edit without explicit consent; show the
  exact proposed change first.
- **Project config** (`.config/wt.toml`) — shared team automation: lifecycle
  hooks, aliases, list URL templates, commit-prompt guidance. May be created or
  edited as normal repo code when asked; validate commands exist and warn
  before adding destructive, networked, or privileged commands.

## Hooks and approvals

Project hooks and aliases are arbitrary shell code from the repository.
Worktrunk requires approval before running them.

- If an agent hits "Cannot prompt for approval in a non-interactive
  environment", stop and escalate: `wt config approvals add`. Never run
  `--yes` to silence the approval gate on the user's behalf.
- Hook events: `pre-`/`post-` for `switch`, `start` (create), `commit`,
  `merge`, `remove`. Prefer `post-start` over `pre-start` unless later steps
  need the work done first. Put format/lint/typecheck in `pre-commit`, and
  tests/build/security in `pre-merge`.
- Use `wt hook <type> --dry-run` and `wt hook show` before trusting hook edits.

## Decision rules

- `worktrunk` tool → worktree and branch lifecycle (`switch`/`merge`/`remove`).
- `git` → low-level inspection and commit/push: `status`, `diff`, `log`,
  `show`, `commit`, `push`.
- `gh` → PRs, issues, CI checks, releases.
- Never raw `git worktree add/remove`; use the `worktrunk` tool unless it
  genuinely cannot express the operation.

## Troubleshooting

- **Branch does not exist** → `switch --create <branch>`.
- **Target path occupied** → switch to the existing worktree, or `--clobber`
  only when the stale path is clearly safe to remove.
- **Hooks block progress** → inspect `.config/wt.toml`, `wt hook show`, and
  hook logs; do not bypass with `--yes`.
- **Slow or broken `wt list`** → `-v`/`-vv` or `WORKTRUNK_VERBOSE=2`.
- **"Shell does not change directories"** → not applicable under Pi: the
  `worktrunk` tool follows the directory-change directive natively.
