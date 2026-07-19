# Vault Conventions

## Folder semantics

- `_meta/` contains vault navigation, conventions, and maintenance notes.
- `daily/` is a dated scratchpad. It is useful timeline context, not durable
  truth by itself.
- `inbox/` contains unintegrated candidate material. It may be stale or wrong.
- `working/` contains active project/task context. Treat it as provisional.
- `memory/` contains curated durable knowledge. Prefer it when confidence
  matters.
- `outputs/` contains generated artifacts that may later be distilled.
- `templates/` contains vault-managed note templates.
- `attachments/` contains supporting assets.

## Organization

Avoid topical folders by default. Prefer links, aliases, tags, and map/index
notes for semantic grouping.

## Agent write boundary

Agents should default to read-only. Writes outside a current-session `inbox/`
draft require explicit approval.
