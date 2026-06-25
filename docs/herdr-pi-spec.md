# Herdr + Pi integration spec

Two-phase implementation. Phase 1 (Herdr) closes Goal 1 and is ready to
implement. Phase 2 (pi-subagents) closes Goal 2 and needs a dedicated
research pass before implementation.

---

## Goals

- **Goal 1 — Visibility**: replace ad-hoc tmux windows with Herdr workspaces;
  see all pi sessions (state, project, role) in one sidebar.
- **Goal 2 — Cost/model routing**: decompose long tasks into subtasks routed
  to models matched to their difficulty, without owning a scheduler.

---

## Design principles

- Generic behaviour is maintained by others (packages, skills, Herdr). Code
  you own is: Nix wiring, prompt templates (markdown), agent definitions
  (markdown). No custom TypeScript extensions.
- Corporate flake reuses the same module machinery from the private flake via
  `lib.mkDefault` / `lib.mkForce`. No duplication.
- Each phase is independently deployable and leaves the other unblocked.

---

## Layer map

```
┌──────────────────────────────────────────────────────────────────┐
│  Herdr  (Phase 1)                                                │
│  workspace / pane / tab layout    ← you organise per session    │
│  agent state sidebar              ← automatic once integrated   │
│  session restore after restart    ← automatic once integrated   │
├──────────────────────────────────────────────────────────────────┤
│  Pi (per pane)                                                   │
│  packages    ← npm/git, maintained externally                   │
│  skills      ← Herdr SKILL.md + domain skills (Phase 1)        │
│  templates   ← role prompts you own (Phase 1)                  │
│  agents      ← sub-agent definitions with model routing         │
│               (Phase 2, @gotgenes/pi-subagents)                 │
├──────────────────────────────────────────────────────────────────┤
│  Nix / Home Manager                                              │
│  installs herdr binary                                          │
│  configures pi (packages, skills, templates, settings)          │
│  does NOT own herdr-agent-state.ts (Herdr manages that)         │
└──────────────────────────────────────────────────────────────────┘
```

---

## Phase 1 — Herdr

### What we do not own

| Concern | Who maintains it |
|---|---|
| Pi lifecycle hooks for Herdr | `herdr integration install pi` → `~/.pi/agent/extensions/herdr-agent-state.ts` |
| Pane/workspace orchestration | Herdr CLI (`herdr pane split/run`, `wait agent-status`, …) |
| Pi's knowledge of the Herdr CLI | Herdr's own SKILL.md, loaded from `inputs.herdr` source tree |
| Generic pi extensions | npm packages already in the pi config (context-mode, pi-lens, …) |

### 1.1 — Flake input

```nix
# flake.nix inputs — add after existing entries
herdr.url = "github:ogulcancelik/herdr";
```

### 1.2 — Overlay (`modules/flake/parts.nix`)

Makes `pkgs.herdr` available in every home-manager module:

```nix
overlays = [
  (final: prev: { stable = import inputs.nixpkgs-stable { inherit system; }; })
  inputs.herdr.overlays.default    # ← add
];
```

### 1.3 — Herdr options module (`modules/home/herdr/_module.nix`)

Standalone HM module — no flake inputs needed. Uses `pkgs.formats.toml`
(nixpkgs-native) so it is self-contained and importable by the corporate
flake without extra wiring.

```nix
# Library module: declares programs.herdr.{enable, settings} options
# and wires them into xdg.configFile."herdr/config.toml".
# Import via homeModules.herdr-module in any consumer flake.
{ pkgs, lib, config, ... }:
let
  cfg = config.programs.herdr;
  fmt = pkgs.formats.toml {};
in {
  options.programs.herdr = {
    enable = lib.mkEnableOption "herdr terminal workspace manager";

    settings = lib.mkOption {
      type    = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        Herdr configuration written to ~/.config/herdr/config.toml.
        Nested sections map to nested attrsets.
        Run `herdr --default-config` for the full reference.

        Note: [[keys.command]] (array-of-tables sections) is a known
        limitation of pkgs.formats.toml — verify serialisation before use.
      '';
      example = lib.literalExpression ''
        {
          onboarding = false;
          terminal.default_shell = "nu";
          theme.name = "catppuccin";
          ui.sidebar_width = 32;
          ui.agent_panel_scope = "all";
          ui.toast.delivery = "herdr";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."herdr/config.toml" = lib.mkIf (cfg.settings != {}) {
      source = fmt.generate "herdr-config.toml" cfg.settings;
    };
  };
}
```

### 1.4 — Herdr aspect (`modules/home/herdr/default.nix`)

```nix
# Dendritic aspect: herdr (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.herdr = { pkgs, lib, config, ... }: {
    imports = [ ./_module.nix ];

    programs.herdr = {
      enable = true;

      settings = {
        onboarding = lib.mkDefault false;

        terminal.default_shell  = lib.mkDefault "$SHELL";

        theme.name              = lib.mkDefault "catppuccin";

        # Show agents across ALL workspaces, not just the active one.
        # This is the key setting for the multi-project visibility goal.
        ui.agent_panel_scope              = lib.mkDefault "all";
        ui.show_agent_labels_on_pane_borders = lib.mkDefault true;
        ui.sidebar_width                  = lib.mkDefault 32;
        ui.toast.delivery                 = lib.mkDefault "herdr";
        ui.toast.herdr.position           = lib.mkDefault "bottom-right";
        ui.sound.enabled                  = lib.mkDefault true;
      };
    };

    home.packages = [ pkgs.herdr ];

    # Run herdr integration install pi on every activation.
    # Herdr handles idempotency. We ensure the target directory exists first
    # because herdr requires it to be present before writing the extension file.
    # Respects PI_CODING_AGENT_DIR if set.
    home.activation.herdrPiIntegration =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _pi_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
        $DRY_RUN_CMD mkdir -p "$_pi_dir/extensions"
        if command -v herdr >/dev/null 2>&1; then
          $DRY_RUN_CMD herdr integration install pi
        fi
      '';
  };
}
```

### 1.5 — Export for cross-flake consumption (`modules/flake/home-modules.nix`)

```nix
flake.homeModules.herdr-module = ../home/herdr/_module.nix;
```

### 1.6 — Pi aspect changes (`modules/home/pi/default.nix`)

Two additions: Herdr SKILL.md as a skill, and shared role prompt templates.

```nix
# In the outer let — add alongside astBroInput / agentStuffSrc:
herdrSrc = inputs.herdr;   # source tree; gives us SKILL.md pinned to flake.lock

# In the inner let — add alongside astBroSkill / nixSearchSkill:
herdrSkill = pkgs.writeTextDir "herdr/SKILL.md"
               (builtins.readFile (herdrSrc + "/SKILL.md"));

# In programs.pi-coding-agent.skills — add:
"herdr" = herdrSkill;

# In programs.pi-coding-agent — add:
promptTemplates = {
  "reviewer"      = lib.mkDefault ./prompts/reviewer.md;
  "investigator"  = lib.mkDefault ./prompts/investigator.md;
  "planner"       = lib.mkDefault ./prompts/planner.md;
};
```

### 1.7 — Prompt templates (`modules/home/pi/prompts/`)

**`reviewer.md`**

```markdown
---
description: Code review — bugs, security issues, missed edge cases
---
Review the changes in context. Focus on:
- correctness and edge cases
- security issues (injection, auth gaps, secret exposure)
- missing error handling
- unclear naming or logic that will confuse future readers

Be specific: file and line, what is wrong, what to do instead.
```

**`investigator.md`**

```markdown
---
description: Open-ended investigation — explore a codebase, trace a bug, map dependencies
---
Your job is to investigate, not to fix. Explore the codebase, trace the
call graph, map the data flow, and report what you find. Prefer read,
grep, and bash over edits. End with a clear summary of findings and open
questions.
```

**`planner.md`**

```markdown
---
description: Break a task into a concrete ordered plan before writing any code
---
Before writing any code, produce a concrete plan:
1. Restate the goal in one sentence.
2. List the files or components that need to change.
3. List the steps in dependency order.
4. Flag any ambiguities or missing information.

Output the plan as a numbered list. Do not start coding until the plan is
confirmed.
```

### 1.8 — Workspace convention

One Herdr workspace per repository or active worktree. Name workspaces and
sessions descriptively so the sidebar is useful:

```bash
# start a session in a project
herdr workspace create --label "auth-service" --cwd ~/projects/auth-service

# when spawning a role session, always name it
pi --name "feat/auth · investigator"
```

### 1.9 — Corporate flake additions

```nix
# In the assembly modules list:
++ [ inputs.private.flake.homeModules.herdr-module ]   # ← add

# In the corporate pi aspect, add the herdr skill (same pattern):
herdrSrc = inputs.herdr;   # close over in outer let
# ...
"herdr" = pkgs.writeTextDir "herdr/SKILL.md"
            (builtins.readFile (herdrSrc + "/SKILL.md"));

# Override prompt templates with lib.mkForce where corp focus differs:
# promptTemplates."reviewer" = lib.mkForce ./prompts/corp-reviewer.md;

# Override herdr settings for corp machines if needed:
# programs.herdr.settings.terminal.default_shell = lib.mkForce "bash";
```

### 1.10 — What Phase 1 owns

| Artifact | Size |
|---|---|
| `flake.nix` patch | 1 line |
| `modules/flake/parts.nix` patch | 1 line |
| `modules/home/herdr/_module.nix` | ~35 lines |
| `modules/home/herdr/default.nix` | ~30 lines |
| `modules/flake/home-modules.nix` patch | 1 line |
| `modules/home/pi/default.nix` patch | ~8 lines |
| `modules/home/pi/prompts/reviewer.md` | ~10 lines |
| `modules/home/pi/prompts/investigator.md` | ~10 lines |
| `modules/home/pi/prompts/planner.md` | ~10 lines |

---

## Phase 2 — pi-subagents

> **Status: research pass needed before implementation.**

### What Phase 2 adds

- `npm:@gotgenes/pi-subagents` added to pi packages
- Agent definition files (`~/.pi/agent/agents/` globally, `.pi/agents/` per
  project) with per-agent `model:` frontmatter — the model map
- Optional companion: `@gotgenes/pi-subagents-worktrees` for git worktree
  isolation (evaluate separately)

### Research questions before implementing

- [ ] Which built-in agent types does `@gotgenes/pi-subagents` ship? Are any
      redundant with the prompt templates defined in Phase 1?
- [ ] What is the full list of "additional recommended packages" referenced in
      the README? Which are optional vs. expected?
- [ ] `@gotgenes/pi-subagents-worktrees`: does the worktree isolation model
      align with the worktrunk workflow already in this config? Conflict risk?
- [ ] How are agent definition files managed in Nix? Plain files in
      `home.file` or a new option added to `_module.nix`?
- [ ] Corporate flake: are agent definitions per-repo (`.pi/agents/`) or
      shared globally? Both are valid; decide convention.
- [ ] Model map: declare in Nix (e.g. `programs.pi-coding-agent.agentModels`)
      or directly in agent frontmatter? Nix gives you central override;
      frontmatter is self-contained.

### Relationship to Phase 1

Phase 2 sub-agents are **in-process** (spawned within the parent pi session).
They do not get their own Herdr pane. Herdr visibility (Phase 1) operates at
the session level — you see which pi sessions are working across projects.
Phase 2 operates within a single session for task decomposition. The two
do not conflict.

---

## Open questions (both phases)

- [ ] `pkgs.formats.toml` and `[[keys.command]]` (array-of-tables) — verify
      a Nix list of attrsets serialises to valid TOML before adding any
      `[[keys.command]]` entries to herdr settings.
- [ ] `lib.mkDefault` on `attrsOf anything` applies to the whole attrset, not
      per-key. If per-key herdr setting overrides are needed in the corporate
      flake, switch individual keys to typed submodule options with `mkDefault`.
