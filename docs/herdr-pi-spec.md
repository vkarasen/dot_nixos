# Herdr + Pi integration spec

Phase 1 (Herdr) is **implemented** — commits `8cb0070`, `7c3edd0`.
This document now tracks Phase 2.

---

## Goals

- **Goal 1 — Visibility** ✅ closed by Phase 1: Herdr workspaces replace ad-hoc
  tmux windows; all pi sessions visible in one sidebar with authoritative
  `idle / working / blocked / done` state.
- **Goal 2 — Cost/model routing**: decompose long tasks into subtasks routed
  to models matched to their difficulty, without owning a scheduler.

---

## Design principles

- Generic behaviour is maintained by others (packages, skills, Herdr). Code
  you own is: Nix wiring, prompt templates (markdown), agent definitions
  (markdown). No custom TypeScript extensions.
- Corporate flake reuses the same module machinery from the private flake via
  `lib.mkDefault` / `lib.mkForce`. No duplication.

---

## Layer map

```
┌──────────────────────────────────────────────────────────────────┐
│  Herdr  ✅ Phase 1 done                                          │
│  workspace / pane / tab layout    ← you organise per session    │
│  agent state sidebar              ← automatic (integration live)│
│  session restore after restart    ← automatic (integration live)│
├──────────────────────────────────────────────────────────────────┤
│  Pi (per pane)                                                   │
│  packages    ← npm/git, maintained externally                   │
│  skills      ← herdr SKILL.md + domain skills  ✅               │
│  templates   ← /reviewer /investigator /planner ✅              │
│  agents      ← sub-agent definitions with model routing         │
│               (Phase 2, @gotgenes/pi-subagents)                 │
├──────────────────────────────────────────────────────────────────┤
│  Nix / Home Manager  ✅ Phase 1 done                             │
│  pkgs.herdr via overlay                                         │
│  programs.herdr.{enable,settings} → xdg.configFile              │
│  home.activation runs herdr integration install pi              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Phase 2 — pi-subagents

Closes Goal 2. Needs a dedicated research pass before implementation.

### Package

`@gotgenes/pi-subagents` — focused in-process sub-agent core.

- Agent definitions as `.md` files with YAML frontmatter
- `model:` frontmatter per agent = the model map, no scheduler to own
- Discovery: `.pi/agents/<name>.md` (project) overrides
  `~/.pi/agent/agents/<name>.md` (global, Nix-managed)
- Sub-agents are **in-process**, not separate Herdr panes — Herdr visibility
  (Phase 1) operates at the session level; Phase 2 operates within a session
  for task decomposition. They do not conflict.

### Key agent frontmatter

```markdown
---
description: Mechanical implementation given a clear spec
model: openai/gpt-4o-mini
tools: read, bash, edit, write
max_turns: 20
---
You are a coder. Implement exactly what the spec says. …
```

### Research questions before implementing

- [ ] Which built-in agent types does `@gotgenes/pi-subagents` ship? Are any
      redundant with the prompt templates defined in Phase 1 (reviewer,
      investigator, planner)?
- [ ] What is the full list of "additional recommended packages"? Which are
      optional vs. expected for basic use?
- [ ] `@gotgenes/pi-subagents-worktrees`: does the worktree isolation model
      align with the worktrunk workflow already in this config? Any conflict?
- [ ] How are global agent definition files managed in Nix? Likely
      `home.file."pi/agent/agents/<name>.md".source = ./agents/<name>.md`
      or a new option added to `_module.nix` (mirrors the skills/templates
      pattern).
- [ ] Corporate flake: are agent definitions per-repo (`.pi/agents/`) or
      shared globally? Both valid — decide convention.
- [ ] Model map: declare centrally in Nix (one place, override per-flake) or
      directly in agent frontmatter (self-contained)? Nix gives you the
      `lib.mkDefault` / `lib.mkForce` override story; frontmatter is simpler.

### Proposed implementation shape (post-research)

```nix
# In programs.pi-coding-agent.settings.packages — add:
"npm:@gotgenes/pi-subagents"

# Global agent definitions managed as Nix store files, e.g.:
home.file.".pi/agent/agents/coder.md".source = ./agents/coder.md;
home.file.".pi/agent/agents/reviewer.md".source = ./agents/reviewer.md;
# … or via a new agents option in _module.nix (TBD after research)
```

---

## Open questions (ongoing)

- [ ] `pkgs.formats.toml` and `[[keys.command]]` (array-of-tables) — verify
      a Nix list of attrsets serialises correctly before adding any
      `[[keys.command]]` entries to herdr settings.
- [ ] `attrsOf anything` applies `mkDefault`/`mkForce` at the whole-attrset
      level. If per-key herdr setting overrides are needed in the corporate
      flake, typed submodule options with per-field `mkDefault` are the fix.
