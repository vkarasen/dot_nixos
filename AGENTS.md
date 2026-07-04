# AGENTS.md

NixOS / home-manager configuration using the **dendritic pattern**. Read this
before editing anything under `modules/`.

## What this repo is

A flake-parts flake where **every `.nix` file under `modules/` is a flake-parts
module**, auto-imported by [`import-tree`](https://github.com/vic/import-tree).
`flake.nix` is a thin entry point and should stay that way:

```nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
```

Functionality is grouped into **aspects**: each file declares modules into the
flake-parts module store under `flake.modules.<class>.<name>`, where `<class>`
is `homeManager`, `nixos`, `darwin`, or `generic` (class-agnostic, reusable
anywhere). Configurations are then assembled by folding the store — adding a
file adds functionality, with no central import list to edit.

## Layout

```
flake.nix                         # thin: inputs + mkFlake (import-tree ./modules)
modules/
  flake/                          # flake-level wiring (NOT aspects)
    parts.nix                     # opt into flake.modules.<class>; systems; shared allowUnfree pkgs + `stable` overlay; formatter
    home-configurations.nix       # folds flake.modules.homeManager.* + generic.* -> homeConfigurations.vkarasen
    home-modules.nix              # flake.homeModules.* — standalone HM modules for cross-flake import
    lib.nix                       # flake.lib.pi — skill derivation builders exposed as a library
    packages.nix                  # perSystem packages.nvim (built from modules/_nixvim)
    templates.nix                 # flake.templates
  options.nix                     # custom my.* options, class `generic` (reusable by home/nixos/darwin)
  home/                           # one aspect per file/dir: flake.modules.homeManager.<name>
    base.nix                      # identity, stateVersion, xdg, catppuccin
    external.nix                  # external input modules (nix-index, catppuccin, nixvim, sops) + ast-bro + registry
    git.nix bash.nix ssh.nix ...
    pi/ sops/ lf/ ...             # multi-file aspects (dir with default.nix)
  _nixvim/                        # shared nixvim module tree (NOT a flake-parts module — see pitfalls)
skills/
  corporate-pi-wiring/            # agent-ingestible wiring guide for the corporate flake (NOT under .pi/ — intentional)
```

Only `inputs` is threaded to home modules via `extraSpecialArgs` in
`modules/flake/home-configurations.nix`. Aspects that need a specific input
value (e.g. `nix-std.lib`, `ast-bro`) close over it at flake-parts evaluation
time in the outer `{inputs, ...}:` function — not as HM module function args.
This keeps every aspect self-contained and importable by other flakes without
extra wiring.

## Persistent storage for new aspects

Before reaching for gdrive, apply this preference order:

1. **Home-manager derivation** — if the data can be expressed as immutable
   Nix config, do that. It is reproducible, version-controlled, and always
   available at activation time.
2. **SOPS** — for secrets or credentials that must be injected at runtime.
3. **gdrive** — only for genuinely mutable post-bootstrap data that cannot
   be expressed as either of the above: user-generated content, app vaults,
   runtime caches, downloaded artifacts.

When gdrive is the right choice, point the aspect at
`config.my.gdrive.mountPoint` rather than inventing a new path under
`$HOME`.

Conventions:

- one top-level directory per app or domain
- keep unrelated apps in separate subtrees
- separate hand-managed content from generated/runtime content
- prefer `app-name/data/`, `app-name/cache/`, `app-name/vault/` as
  sub-layouts — not `settings/`, which should live in Nix config

This mount is **private** (gated by `my.is_private`), **post-bootstrap**
only — Home Manager must be able to evaluate and activate without it
being available — and **externally mutable**: treat writes as potentially
visible outside this machine and hard to undo.

See `modules/home/rclone.nix` for how the mount is wired and
`modules/options.nix` for the canonical `my.gdrive.mountPoint` option.

## Looking up options & packages (do this FIRST)

Before you add or change **any** home-manager / NixOS / nix-darwin / nixvim
option or package in this repo, look it up to confirm the attribute path, type,
default, and that it exists in the pinned nixpkgs — do not guess option names.

Use the **`nix-search` skill** for this: it wraps `nix-search-tv`, which is
installed and configured in this repo (`modules/home/television/default.nix`).
Load that skill whenever a task involves finding or verifying a NixOS / Home
Manager / nixvim option or a nixpkgs package. Available indexes:

| Index | Use it to look up |
|-------|-------------------|
| `nixpkgs` | packages (for `home.packages`, `extraPackages`, etc.) |
| `home-manager` | `programs.*` / `services.*` home-manager options |
| `nixos` | NixOS module options (future native host) |
| `darwin` | nix-darwin options (future macOS host) |
| `nixvim` | nixvim plugin/option lookups (custom index wired in this repo) |

Quick check without the skill loaded:

```bash
nix-search-tv print --indexes home-manager | grep -i '<option>'
nix-search-tv preview --indexes home-manager --json '<option.path>'
```

## How to add things

### A home-manager aspect

First confirm the option names with the **`nix-search` skill** (index
`home-manager`; see [Looking up options & packages](#looking-up-options--packages-do-this-first)).
Then create `modules/home/<name>.nix`:

```nix
# Dendritic aspect: <name> (home-manager class).
{...}: {
  flake.modules.homeManager.<name> = {pkgs, config, lib, ...}: {
    # normal home-manager config here
  };
}
```

It is picked up automatically and folded into `homeConfigurations.vkarasen`.
Need a value from a flake input (e.g. `nix-std.lib`, `ast-bro`)? Close over
it at flake-parts level — change the outer function from `{...}:` to
`{ inputs, ... }:` and bind the value in a `let` before the HM module
function:

```nix
{ inputs, ... }: {
  flake.modules.homeManager.<name> = let
    myLib = inputs.some-input.lib;
  in {pkgs, config, lib, ...}: {
    # use myLib here
  };
}
```

Do **not** add new values to `extraSpecialArgs` in `home-configurations.nix`
— that breaks cross-flake portability. The closure approach keeps every
aspect self-contained.

### Same concern across classes (the point of aspects)

Declare the variants **in the same file**, grouped together:

```nix
{...}: {
  flake.modules.homeManager.foo = { ... };
  flake.modules.nixos.foo       = { ... };   # when you add a NixOS host
  flake.modules.generic.foo     = { ... };   # class-agnostic (e.g. shared options)
}
```

### A custom option

Add to `modules/options.nix` under `flake.modules.generic.my-options` so it is
reusable by future nixos/darwin configs, not just home.

### pi packages / skills / prompt templates

See the **`pi-config` skill** (`.pi/skills/pi-config/SKILL.md`) — it is the
authoritative guide for everything under `modules/home/pi/`.

### Global always-on agent instructions

Pi loads `~/.pi/agent/AGENTS.md` at startup as **global standing instructions**
— always injected, not opt-in like a skill. This file is generated by
home-manager from the `my.pi.globalAgentPolicies` option (declared in
`modules/options.nix`, generic class).

Each key in the attrset becomes a named section; keys are sorted alphabetically
before concatenation, so use numeric prefixes to control order:

```
"00-nix-workspace"  — Nix exploration policy (defined in modules/home/pi/default.nix)
"10-scripting"      — scripting runtime preference (defined in modules/home/pi/default.nix)
"90-corporate"      — add in the corporate flake for site-specific rules
```

To add a section from any aspect:

```nix
my.pi.globalAgentPolicies."90-corporate" = ''
  # Corporate policy
  Always use the internal Artifactory mirror.
'';
```

The corporate flake can add keys freely (additive) or use `lib.mkForce` to
replace a base section. See the **`pi-config` skill** for full details.

### A future NixOS or nix-darwin host

The home assembly in `modules/flake/home-configurations.nix` is the template:
add `modules/flake/nixos-configurations.nix` that folds
`config.flake.modules.nixos.*` (and `generic.*`) the same way. Per-host files go
in a new `modules/hosts/<name>.nix`. Keep shared logic in `generic` aspects to
avoid repetition across classes.

## Pitfalls (these will bite you)

1. **Nix ignores untracked files.** This is a git flake; the fetcher only sees
   git-tracked files. After creating a new file you MUST `git add` it before
   `nix build`/`nix flake check` — otherwise it silently does not exist and you
   will chase a ghost. Symptom: a new output/aspect "isn't taking effect".

2. **`import-tree` ignores any path containing `/_`.** That is why
   `modules/_nixvim/` and `modules/home/pi/_module.nix` / `_skills.nix` are
   underscore-prefixed: they are consumed *by reference* (`import ../_nixvim`,
   `imports = [./_module.nix]`), not as standalone flake-parts modules. Helper
   files, libraries, and nixvim/neovim-class modules that are NOT flake-parts
   modules must live behind a `/_` path or they will be imported as top-level
   modules and break evaluation.

3. **`modules/flake/` files are flake-parts modules, `modules/home/` files are
   aspects.** Don't put `perSystem` / `flake.homeConfigurations` /
   `systems` inside a `home/` aspect, and don't put home-manager config directly
   in a `flake/` file (wrap it in `flake.modules.homeManager.<name>`).

4. **`nvim` is single-source.** `modules/_nixvim/` is imported by BOTH the
   standalone `packages.nvim` and the `neovim` home aspect. Edit nixvim config
   there once; both update.

5. **`unknown flake output 'modules'` from `nix flake check` is harmless** — it
   is the dendritic aspect store surfaced as a freeform flake output, not an
   error.

## Google Drive bootstrap boundary

This repo is the only place where the private Google Drive mount is wired
up. Keep that mount strictly post-bootstrap:

- Home Manager must be able to evaluate, activate, and load secrets without
  the mount being available
- anything needed to bring the config online must live in the repo, the Nix
  store, or SOPS
- use gdrive only for data that is read or written after Home Manager is
  already online
- do not make activation or secret loading depend on the mount

## Git workflow for this repo

This is a **personal, solo config repo** — no collaborators, no review process.

- Work directly on `main` for routine changes (adding an aspect, tweaking
  options, bumping an input).  No feature branch needed.
- Create a worktree (`wt switch --create <name>`) only when a change is
  genuinely experimental — e.g. a large refactor you might want to discard,
  or two independent lines of work you want to keep separate.
- **Do not open GitHub PRs.**  When a worktree task is done and you're
  satisfied, merge locally with `wt merge` and push directly to `main`.
- Plain `git commit` + `git push` is fine for incremental work on `main`.

## Testing

```bash
git add -A                                                  # pitfall #1
nix flake check                                             # full eval + templates
nix build .#nvim --no-link                                  # standalone neovim
nix build .#homeConfigurations.vkarasen.activationPackage --no-link
```

Format before committing: `nix run nixpkgs#alejandra -- modules flake.nix`
