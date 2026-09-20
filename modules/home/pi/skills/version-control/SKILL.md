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
`remove`/cleanup, `step relocate`, `step prune` — run through the
**`worktrunk` tool**, never `wt` through `bash`. A bash `wt merge`/`switch`/`remove` deletes or moves the worktree your
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

**The `pi` launcher bootstraps automatically.** A shell function runs before
pi and, on a fresh task started from the main checkout (a git repo where
`.git` is a directory), creates a worktree on a placeholder branch and — under
herdr — relocates the pane into that worktree's workspace. By the time pi
starts you are already inside a fresh worktree with the correct cwd; there is
no `wt switch`/`relocate_herdr_tab` to perform on the first turn and no
prompt-cache break. On your first turn, name the task: `git branch -m
<task-name>` and `rename_herdr_context <label>`.

The launcher passes through to pi unchanged (no bootstrap) for: not-a-git-repo,
any fresh-task flag (`--resume`/`--continue`/`--session`/`--session-id`/
`--fork`/`--print`/`--mode`), help/version, the subcommands
(`install`/`update`/`list`/`config`/`auth`), and any checkout that is not the
main one (`.git` is a file — you are in a worktree, i.e. where you meant to
be). Worktrees are only ever created from main, never nested.

Every tab inside that sub-workspace belongs to the one session/topic it was
created for; do not accumulate unrelated work's tabs in the same sub-workspace
or in the repo's primary workspace. You may still create the sub-workspace
manually before starting pi (`<prefix>+shift+g` / `herdr worktree create`);
that leaves the worktree under herdr's root instead of worktrunk's, which is
fine. See "Renaming, pruning, and recovery" below for cleanup.

**Manual moves and stacked work** still go through the `worktrunk` tool and
`relocate_herdr_tab`: to move to a different worktree, `switch --create
<branch>` (add `--base=@` for stacked work on the current branch), then
`relocate_herdr_tab`. Orient first with `wt list` (or `wt list --full
--branches`).

A worktree never needs its final name up front, in either flow: rename the
branch later with `git branch -m <name>` (herdr's own sidebar label can be
changed separately with `herdr workspace rename`, cosmetic only). Do not
relocate a herdr-created worktree's directory to match worktrunk's path
template (`wt step relocate`) — herdr's own cleanup trusts the checkout path
it recorded at creation time and breaks permanently for that workspace once
the directory moves out from under it. `wt`, `wt list`, `wt merge`, and
`wt remove` all address worktrees by branch name, so a mismatched directory
name is harmless.

## Merge and PR conventions

- **Solo/personal repos**: merge locally with the `worktrunk` tool (`merge`);
  do not open GitHub PRs — the worktree stands in for the PR.
- **Shared repos**: open a PR with `gh pr create` for a review record; use the
  `worktrunk` tool's `merge` only when PRs are explicitly not wanted.
- **Inside a herdr worktree sub-workspace**: always `merge --no-remove`. The
  merge still lands on the default branch; it deliberately leaves the
  worktree in place so the herdr close-triggered plugin (below) does the
  actual removal once the user closes the sub-workspace — that close is the
  authoritative "done" signal, not the merge. Outside a herdr sub-workspace,
  use `merge`'s default (removes the worktree, relocates the session
  immediately) since there's no separate close signal to defer to.
- **Always** sync and rebase onto `origin/main` (fetch first), and **never
  force-push to `main`**. A rejected push is routine: fetch, rebase, resolve,
  push again.
- Commit, merge, and push each wait for explicit user approval — see the
  global "Git workflow policy".

## Renaming, pruning, and recovery

**Renaming.** Neither creation path needs a final name up front: rename the
branch later with `git branch -m <name>` (what `wt`/`wt list`/`wt merge`
address worktrees by); `herdr workspace rename` separately renames the
sidebar label, cosmetic only. Never `wt step relocate` a herdr-created
worktree's directory — herdr's own "delete worktree checkout" trusts the
checkout path it recorded at creation time and breaks permanently for that
workspace after an external move. A mismatched directory name is harmless
since nothing addresses a worktree by path.

**Cleanup — two mechanisms, not one:**

- **Primary: a herdr plugin on workspace close** (`worktrunk-close-prune`,
  installed locally via `modules/home/herdr/default.nix`). The moment a
  linked worktree sub-workspace closes, it asks Worktrunk whether that
  specific worktree is now identical to or merged into the default branch,
  and removes it only if so. No age guard — closing the workspace is itself
  the deliberate signal. A worktree with real uncommitted or unmerged work
  is left alone, untouched, for as long as it takes you to come back to it.
  This fires on the workspace-close action (`<prefix>+d`, or `herdr workspace
  close`) after its confirmation. It does NOT fire when you close the last
  tab of a sub-workspace — that gesture closes the workspace without emitting
  `workspace.closed` — so close the workspace, not just the tab, when you
  want the worktree removed.
- **Backstop: a systemd user timer** (`worktrunk-autoprune`, `my.worktrunk.
  autoPrune` in `modules/options.nix`, default daily). Discovers every repo
  with worktrees under either root (`my.worktrunk.worktreeRoot`'s
  `.worktrees`, and herdr's sibling `.herdr-worktrees`), and removes only
  what `wt step prune --dry-run` itself calls safe *and* that herdr does not
  currently show as open in any workspace (`herdr worktree list`). Default
  `minAge` is 7 days — long enough that a paused-but-live session is never
  at risk. This exists for what the plugin might miss (herdr not running,
  the plugin failing, herdr quitting uncleanly), not as the routine path.

Both mechanisms only ever act through `wt remove`/`wt step prune`, which are
structurally unable to touch a worktree with uncommitted changes (no
`--force` is ever passed) — the worst case of an unwanted removal is losing a
directory whose entire contents already exist on the default branch.

**Recovery.** Session transcripts are never touched by either mechanism —
they live independently under `~/.pi/agent/sessions/<encoded-cwd>/`. If a
sub-workspace with real work gets closed accidentally (nothing removes it,
see above) or a worktree needs to be picked back up later:

1. `herdr worktree open --path <path>` (or `--branch <name>`) re-attaches a
   fresh sub-workspace to the existing checkout — no new git worktree, no
   branch touched. Herdr ships this unbound by default; here it's bound to
   `<prefix>+shift+o`, which must be pressed from the repo's parent
   workspace (not from inside a worktree sub-workspace — same restriction
   as the `<prefix>+shift+g` new-worktree binding).
2. `pi --session <id|partial-path>` inside that reopened tab resumes the
   original conversation — pi does not restore or validate the session's
   recorded cwd, so this only works from inside the right directory.

`<prefix>+shift+e` deletes a worktree checkout outright (opens a
confirmation, never touches the branch) for the rare case of wanting instant
manual cleanup instead of waiting on the close-triggered plugin.

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

- `worktrunk` tool → worktree and branch lifecycle
  (`switch`/`merge`/`remove`/`step relocate`/`step prune`).
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
