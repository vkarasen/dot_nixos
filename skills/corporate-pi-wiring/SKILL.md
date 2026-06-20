---
name: corporate-pi-wiring
description: >
  Wire the corporate flake to consume pi config machinery (options, skill
  builders) from the private dot_nixos flake. Use this skill when setting up
  or modifying the corporate home-manager configuration to add pi support,
  import skills, or sync settings with the private config.
user-invocable: true
---

# Corporate pi wiring

Both flakes are under your control. This guide describes the agreed "special
sauce" protocol between them — a deliberately tight coupling that avoids the
boilerplate of a fully generic cross-flake API.

---

## What the private flake exposes

After the refactor these outputs are available on `inputs.private`:

| Output | Type | What it is |
|---|---|---|
| `flake.homeModules.pi-module` | HM module (path) | Declares `programs.pi-coding-agent.{skills, promptTemplates}` options and wires them into `settings.skills` / `settings.prompts`. Import this to use the structured option API instead of writing to `settings` directly. |
| `flake.lib.pi.mkSkills` | Function `{ pkgs, ast-bro } → attrset` | Returns `{ mkAstBroSkill, mkSourceSkill }` — the same derivation builders used by the private config. |
| `flake.modules.homeManager.*` | Attrset of HM modules | Full dendritic aspect store. Individual aspects can be cherry-picked or the whole set folded in. |
| `flake.modules.generic.*` | Attrset of HM modules | Class-agnostic modules, notably `my-options` which declares `my.is_private`, `my.git.email`, `my.portable.*`, `my.homeConfigurationName`. |

**Key invariant:** `my.is_private` defaults to `false`. All private-only
behaviour (personal pi settings, ssh-agent, private sops secrets, etc.) is
gated behind `lib.mkIf config.my.is_private`. The corporate flake never needs
to set this flag — silence means corporate.

---

## Step 1 — Add the private flake as an input

In the corporate `flake.nix`:

```nix
inputs = {
  # ... existing inputs ...

  private = {
    url = "github:vkarasen/dot_nixos";   # or path:/path/to/local/clone
    # inputs.nixpkgs should follow the corporate flake's nixpkgs to avoid
    # two different nixpkgs closures in the same build.
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Follow ast-bro from the private flake so skill derivations use the same
  # version the private config was tested against.
  ast-bro.follows = "private/ast-bro";
};
```

No other `follows` are required for pi specifically. `agent-stuff` is closed
over inside the private flake's aspect at flake-parts eval time and never
surfaces as an `extraSpecialArgs` requirement.

---

## Step 2 — Home configuration assembly

The corporate flake's home-manager assembly (wherever it calls
`inputs.home-manager.lib.homeManagerConfiguration`) needs two additions:

### 2a. extraSpecialArgs

After the stage-2 refactor, **no private aspect requires any custom
`extraSpecialArgs`**. Every aspect that previously needed `std`, `ast-bro`, or
`nixvimOptions` now closes over those values from `inputs.*` at flake-parts
evaluation time — before the HM module function is ever called.

The only thing worth passing is `inputs` itself (as a convenience for any
future corporate aspects you write):

```nix
extraSpecialArgs = { inherit inputs; };
```

### 2b. modules list

```nix
modules =
  # Your own corporate aspects:
  builtins.attrValues config.flake.modules.homeManager

  # The pi option machinery from private (gives you the skills/promptTemplates options):
  ++ [ inputs.private.flake.homeModules.pi-module ]

  # The generic option declarations from private (my.is_private etc.):
  ++ builtins.attrValues (inputs.private.flake.modules.generic or {})

  # Corporate identity:
  ++ [{ my.is_private = false; }];   # default, but explicit is cleaner
```

**Cherry-picking instead of the full store:**
If you want specific private aspects (e.g. just `tmux`, `git`, `neovim`) without
pulling in everything:

```nix
++ (with inputs.private.flake.modules.homeManager; [ tmux git neovim ])
```

Aspects that have no `inputs.*` or non-standard `extraSpecialArgs` dependencies
are safe to import this way with no further setup. Check the inventory below.

---

## Step 3 — Corporate pi aspect

Create `modules/home/pi.nix` (or `modules/home/pi/default.nix`) in the
corporate flake. This is the aspect that owns your corporate pi settings:

```nix
# Dendritic aspect: pi (home-manager class) — corporate variant.
{ inputs, ... }: {
  flake.modules.homeManager.pi = let
    # Use the same skill builders as the private config, against corporate pkgs.
    # mkSkills returns { mkAstBroSkill, mkSourceSkill }.
    buildSkills = pkgs: inputs.private.lib.pi.mkSkills {
      inherit pkgs;
      ast-bro = inputs.ast-bro;   # follows private/ast-bro — same derivation
    };
  in {
    pkgs,
    lib,
    config,
    ...
  }: let
    skills = buildSkills pkgs;
  in {
    # _module.nix is already imported via homeModules.pi-module in the assembly;
    # no need to import it again here.

    config = {
      programs.pi-coding-agent = {
        enable = true;
        extraPackages = [ pkgs.nodejs pkgs.bun ];

        skills = {
          "ast-bro" = skills.mkAstBroSkill;
          # Add corporate-specific skills here, e.g.:
          # "my-corp-skill" = ./skills/my-corp-skill;   # dir with SKILL.md
          # "wiring" = skills.mkSourceSkill "corporate-pi-wiring"
          #              (inputs.private + "/skills/corporate-pi-wiring");
        };

        settings = {
          # Match the private theme for consistency, or override:
          theme = "catppuccin-mocha";
          quietStartup = true;
          defaultProvider = "github-copilot";
          defaultModel = "claude-haiku-4.5";

          packages = [
            # Start with the private baseline and prune / extend:
            "npm:pi-mcp-adapter"
            "npm:context-mode"
            "npm:pi-lens"
            "npm:@barlevalon/worktrunk-skill"
            # ... add corporate-specific packages ...
          ];
        };
      };
    };
  };
}
```

**Tip — importing the wiring skill itself into the corporate pi config:**

The skill you are reading right now lives at
`skills/corporate-pi-wiring/SKILL.md` inside the private repo. You can wire
it into the corporate pi agent so it is always available there:

```nix
skills."corporate-pi-wiring" = skills.mkSourceSkill "corporate-pi-wiring"
  (inputs.private + "/skills/corporate-pi-wiring");
```

---

## Step 4 — external.nix: already pre-closed, nothing to do

`external.nix` imports HM modules from private-flake inputs (`catppuccin`,
`nix-index-database`, `nixvim`, `sops-nix`) and installs `ast-bro`. All of
those references live in the **outer** `{inputs, ...}:` flake-parts function
body, not inside the HM module function. By the time the corporate flake
accesses `inputs.private.flake.modules.homeManager.external`, the outer
function has already been applied with the private flake's inputs — the
module is a closed value.

No `follows`, no `extraSpecialArgs`, no action required. The catppuccin
theming, nix-index/comma, nixvim HM module, sops-nix module, and ast-bro
package all just work when you include `external` in the modules list.

The one `follows` worth adding is `nixpkgs` (to avoid two nixpkgs closures):

```nix
private.inputs.nixpkgs.follows = "nixpkgs";
```

---

## Aspect dependency inventory

Reference when deciding which private aspects to import:

| Aspect | extraSpecialArgs needed | Notes | is_private guarded |
|---|---|---|---|
| `git` | none | clean | partial (email) |
| `bash` | none | clean | ✓ (ssh-agent eval) |
| `ssh` | none | clean | ✓ (agent, private hosts) |
| `tmux` | none | clean | — |
| `lf` | none | clean | — |
| `worktrunk` | none | `std` closed at definition time | — |
| `television` | none | `nixvimOptions` closed at definition time | — |
| `neovim` | none | clean; needs nixvim HM module → include `external` | — |
| `sops` | none | clean; needs sops-nix HM module → include `external`; for corporate secrets setup see `modules/home/sops/README-corporate.md` in the private repo | ✓ (secrets file, secret decls) |
| `external` | none | all inputs pre-closed at flake-parts level | — |
| `pi` | none | inputs pre-closed; personal config guarded | ✓ (entire config block) |

---

## Verification

```bash
git add -A
nix flake check --no-build
nix build .#homeConfigurations.<name>.activationPackage --no-link
```
