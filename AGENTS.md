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
    packages.nix                  # perSystem packages.nvim (built from modules/_nixvim)
    templates.nix                 # flake.templates
  options.nix                     # custom my.* options, class `generic` (reusable by home/nixos/darwin)
  home/                           # one aspect per file/dir: flake.modules.homeManager.<name>
    base.nix                      # identity, stateVersion, xdg, catppuccin
    external.nix                  # external input modules (nix-index, catppuccin, nixvim, sops) + ast-bro + registry
    git.nix bash.nix ssh.nix ...
    pi/ sops/ lf/ ...             # multi-file aspects (dir with default.nix)
  _nixvim/                        # shared nixvim module tree (NOT a flake-parts module — see pitfalls)
```

`std`, `ast-bro`, `nixvimOptions` are threaded to home modules via
`extraSpecialArgs` in `modules/flake/home-configurations.nix`.

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
Need a specialArg (`std`/`ast-bro`/`nixvimOptions`)? It's already in scope.

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

## Testing

```bash
git add -A                                                  # pitfall #1
nix flake check                                             # full eval + templates
nix build .#nvim --no-link                                  # standalone neovim
nix build .#homeConfigurations.vkarasen.activationPackage --no-link
```

Format before committing: `nix run nixpkgs#alejandra -- modules flake.nix`
