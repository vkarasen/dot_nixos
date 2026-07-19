---
name: obsidian-vault-read
description: Retrieve context from environment-global or project-local Obsidian vaults. Use when a project-local vault is visible, repo instructions mention Obsidian, or additional user/environment context from the global vault might materially help the task.
---

# Obsidian Vault Read Workflow

Use this skill for **read-only** progressive discovery from Obsidian vaults.
Retrieval is the default, low-friction operation; writes, capture, curation, and
maintenance belong in `obsidian-vault-maintenance`.

## Vault ownership model

There are two relevant vault classes:

1. **Project-local vaults** — shared project documentation owned by the repo,
   team, or contributor community. Prefer these for repo facts, decisions,
   runbooks, onboarding, architecture notes, and project-specific learnings.
2. **Environment-global vault** — private durable context for the current
   user/profile/privilege domain. Use it for user preferences, prior decisions,
   cross-project context, active work memory, and other environment-specific
   background.

Do not copy or summarize environment-global vault content into project-local
shared state unless the user explicitly asks and the content is appropriate for
that audience.

## When to retrieve

At the start of a non-trivial task, load this skill and do scoped retrieval when
any of these are true:

- you can see a project-local Obsidian vault;
- repo-local instructions mention a vault, notes corpus, or Obsidian workflow;
- additional user/environment context from the global vault might materially
  improve the task;
- the user asks about notes, memory, prior decisions, preferences, daily notes,
  project documentation, or Obsidian.

Keep retrieval purposeful and bounded. Do not browse vaults out of curiosity.

## Locate vaults

### Project-local vaults

Prefer explicit repo-local instructions first:

- `AGENTS.md` or equivalent agent policy;
- `.pi/skills/` or other local skills;
- README/docs that mention Obsidian, notes, vaults, knowledge bases, or docs.

If no instructions exist, look only for obvious vault roots in or near the
current project, such as directories containing `.obsidian/`. Common locations
include the repository root, `docs/`, `notes/`, `vault/`, and `knowledge/`.
Do not perform broad home-directory scans.

### Environment-global vault

Use Home Manager's session variable:

```bash
$OBSIDIAN_GLOBAL_VAULT_DIR
```

The vault name, when needed for tools that address vaults by name, is:

```bash
$OBSIDIAN_GLOBAL_VAULT_NAME
```

If the global vault variable is unset, ask the user or inspect the local config
for `my.obsidian.globalVault`; do not hardcode machine-specific paths.

## Retrieval order

1. Read the project's instructions and any project-local vault guidance.
2. If a project-local vault is relevant, start there for project-owned context.
3. If global context may help, inspect the environment-global vault.
4. In each vault, start with `_meta/index.md` when it exists.
5. Search filenames, frontmatter, tags, headings, and body text for task terms.
6. Read a small number of high-signal notes.
7. Follow useful outlinks/backlinks selectively.
8. Prefer curated/stable notes over scratch content when confidence matters.

Within the standard global-vault layout, treat folders as follows:

- `_meta/` — navigation, conventions, maintenance, health; start here.
- `memory/` — curated durable knowledge; usually highest confidence.
- `working/` — active/provisional task context; useful but lower confidence.
- `outputs/` — plans, reports, summaries; inspect when related to the task.
- `daily/` — dated scratchpad/timeline context; useful but not durable truth.
- `inbox/` — unintegrated candidate material; lowest confidence.
- `templates/`, `attachments/` — supporting material, not primary context.

Project-local vaults may use different folder conventions; follow their local
instructions over the global-vault defaults.

## Tool preference

Use the richest safe tool available for the current environment:

1. A configured Obsidian MCP or vault-aware retrieval tool, if present and
   scoped appropriately.
2. Obsidian CLI, **only when it is already safe to use**. The `obsidian` binary
   may launch or focus the desktop GUI when the app/IPC is not already running;
   do not invoke it blindly in an agent session.
3. Scoped filesystem search/read under the resolved vault root.

For filesystem retrieval, keep searches narrow. Prefer `rg` over broad reads,
then read only the relevant Markdown files or sections.

Useful filesystem patterns:

```bash
# Start with navigation if present
ls "$OBSIDIAN_GLOBAL_VAULT_DIR/_meta"

# Search note names and bodies for task-relevant terms
rg -n --glob '*.md' 'search terms' "$OBSIDIAN_GLOBAL_VAULT_DIR"

# Find tags/frontmatter/links around a topic
rg -n --glob '*.md' '(^tags:|#[[:alnum:]_/-]+|\[\[.*topic.*\]\])' "$OBSIDIAN_GLOBAL_VAULT_DIR"
```

## Templates and conventions

`templates/` is not primary retrieval context, but it is useful for
understanding how notes in a vault are expected to look. Inspect it when the
user asks about note shape, daily notes, capture conventions, or why an
Obsidian/Neovim workflow produced a sparse note.

In this Home Manager configuration, `obsidian.nvim` expects the daily-note
template at `templates/daily.md`. If an otherwise bootstrapped vault lacks that
file, load `obsidian-vault-bootstrap` and follow its guarded bootstrap/repair
workflow before creating or editing templates.

## Read-only boundary

This skill does not grant write permission.

Do not create, modify, move, delete, archive, or link vault notes while using
this skill. If the task requires capture, curation, health checks, or edits,
load `obsidian-vault-maintenance`, describe the intended change, and follow its
approval rules.
