---
name: obsidian-vault-maintenance
description: Create, edit, capture, curate, or maintain Obsidian vault notes. Use when the user explicitly asks for vault writes, memory capture, daily notes, note promotion, link checks, health reports, or vault organization.
---

# Obsidian Vault Maintenance Workflow

Use this skill for Obsidian vault writes, capture, curation, and maintenance.
For read-only context retrieval, use `obsidian-vault-read` first.

## Ownership boundaries

There are two vault classes:

1. **Environment-global vault** — private durable context for the current
   user/profile/privilege domain. It is the default place for personal or
   environment-specific memory, preferences, decisions, and cross-project
   context.
2. **Project-local vaults** — shared project documentation owned by the repo,
   team, or contributor community.

Do not copy or summarize environment-global vault content into project-local
shared state unless the user explicitly asks and the content is appropriate for
that audience. Do not promote project-local learnings into the global vault
without approval; suggest capture when something appears worth preserving.

## Global vault location

Prefer Home Manager's session variables:

```bash
$OBSIDIAN_GLOBAL_VAULT_NAME
$OBSIDIAN_GLOBAL_VAULT_DIR
```

If `$OBSIDIAN_GLOBAL_VAULT_DIR` is unset, ask the user or inspect the configured
`my.obsidian.globalVault` option. Do not hardcode machine-specific paths.

The global vault is mutable user state. Home Manager configures tooling and the
canonical path, but does not own the note contents or vault-local `.obsidian/`
settings.

## Standard global-vault layout

The standard environment-global vault shape is:

```text
<global-vault>/
  _meta/
  daily/
  inbox/
  working/
  memory/
  outputs/
  templates/
  attachments/
```

Folder semantics:

- `_meta/` — vault-level navigation, conventions, maintenance notes, and health
  reports. Start discovery at `_meta/index.md` when it exists.
- `daily/` — dated scratchpad / capture ledger. Useful for timeline context,
  but not accepted durable memory by itself.
- `inbox/` — unintegrated candidate material. Existence here does not imply
  endorsement or durable truth.
- `working/` — project/task-scoped context. Useful but provisional and
  lower-confidence than `memory/`.
- `memory/` — curated durable knowledge. High-signal and slow-changing, but not
  immutable.
- `outputs/` — generated artifacts such as plans, reports, comparisons, and
  summaries. Durable insights can later be distilled into `memory/`.
- `templates/` — vault-managed Obsidian templates. Home Manager configures the
  directory, but does not own template content.
- `attachments/` — screenshots, pasted images, PDFs, diagrams, and other assets;
  not the primary semantic note graph.

Avoid topical folders in the global vault by default. Prefer links, aliases,
tags, and map/index notes for semantic grouping.

Project-local vaults may use different conventions. Follow repo-local guidance
for project-local writes.

## Bootstrap and starter templates

For new vault initialization, missing starter templates, or skeleton repair, use
the `obsidian-vault-bootstrap` skill. It contains the canonical starter vault
skeleton and a guarded bootstrap script.

Do not manually recreate starter files from memory. Do not run bootstrap tooling
against an existing vault directory unless the user has expressly approved
bootstrapping or repairing that existing vault. Existing vault files are
user-owned and must not be overwritten without explicit approval.

## Write boundaries

Vaults are persistent memory. Default to read-only unless the user request
clearly asks for a write/capture/maintenance task.

Without additional confirmation, an agent may only create new notes under
`inbox/`, and only when the current user request clearly asks for capture,
notes, memory, vault work, or future incorporation.

After creating an `inbox/` note during the current session, the agent may keep
editing that same note as draft/scratch space for the current task. This
permission does not extend to:

- inbox notes from prior sessions;
- notes created by the user;
- `memory/`;
- `working/`;
- `outputs/`;
- `_meta/`;
- `templates/`;
- project-local shared vaults;
- or any other existing vault note.

For all other writes, first describe the intended change and ask for approval.
This includes creating, modifying, moving, deleting, archiving, or linking notes
outside the current-session `inbox/` draft.

Direct `memory/` edits are appropriate only when the user explicitly requests or
approves the specific durable contribution.

## Integration boundary

`inbox/` notes are unintegrated. They may link outward to existing notes for
context, but agents must not add links from durable notes back to `inbox/`
without explicit integration approval.

Promotion from `inbox/` to `memory/`, or any update to the accepted memory graph,
requires confirmation.

## Working notes and concurrent agents

`working/` is read-eager but write-controlled. It may contain active project
plans, provisional assumptions, investigation state, or task context. Treat it
as useful but unstable.

Do not use `working/` as autonomous scratch space. Do not create, modify,
delete, or archive `working/` notes without explicit user approval.

When multiple agents or subagents may be involved, avoid shared-note write
collisions. Subagents should produce proposals or current-session `inbox/`
captures instead of editing the same `working/` note. Consolidation into
`working/` or `memory/` requires user approval.

## Daily notes

Daily notes are timed scratchpads, not durable memory. They can hold dated
thoughts, decisions, follow-ups, and breadcrumbs. Agents may read relevant daily
notes during scoped discovery, but should not append to daily notes unless the
user explicitly asks for daily capture.

Daily-note content can later be reviewed and extracted into `inbox/`, `working/`,
`outputs/`, or `memory/` with approval.

## Tool preference

Use the richest safe tool available:

1. A configured Obsidian MCP or vault-aware tool, if present and scoped
   appropriately.
2. Obsidian CLI, only when it is already safe to use. The `obsidian` binary may
   launch or focus the desktop GUI when the app/IPC is not already running; do
   not invoke it blindly in an agent session.
3. Direct filesystem edits under the resolved vault root, when no safer
   vault-aware tool is available and the write is approved.

For operations that move notes or alter links, prefer vault-aware tools when
available so backlinks and metadata stay coherent.

## Naming and frontmatter

Prefer human-readable filenames for durable notes. Timestamp prefixes are useful
for `inbox/` captures when they avoid naming friction.

Suggested frontmatter fields, adapted case-by-case:

```yaml
---
title:
type: inbox | daily | working | memory | output | meta
status: inbox | draft | active | stable | archived
scope: transient | project | durable
confidence: low | medium | high
reviewed: false
created:
updated:
tags: []
aliases: []
sources: []
---
```

Do not let frontmatter bureaucracy block useful capture. Prefer small,
reviewable notes and preserve user-authored content.

## Link and health checks

After writing vault content, run a scoped sanity check before reporting success:

- verify edited files exist and are in the intended folder;
- verify newly added wikilinks point to existing notes, or explicitly call out
  intentional unresolved links;
- if an Obsidian-aware tool is available, use it for unresolved-link/backlink
  checks;
- otherwise use scoped Markdown search/read operations;
- do not run broad expensive audits unless requested.

For project-local vaults, also run any repo-specific documentation or link
validation required by local instructions.
