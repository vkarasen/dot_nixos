---
name: bundle-module
description: How to wrap a home-manager aspect into a standalone package (nix run .#name) in this repo. Use when asked to bundle, wrap, or expose a module as a standalone package.
---

# Bundling a home-manager aspect as a standalone package

Uses [hm-wrapper-modules](https://github.com/sini/hm-wrapper-modules) to
evaluate an HM aspect in isolation, extract its packages and config files, and
produce a `packages.<name>` derivation. On Linux, bubblewrap presents
`xdg.configFile` entries at their expected `$XDG_CONFIG_HOME` paths without
touching `$HOME`.

---

## All bundles live in one file

`modules/flake/wrapped-packages.nix` — already exists with the pi bundle. Add
new entries there. Do not create a new file per bundle.

---

## Adding a bundle

```nix
perSystem = { pkgs, ... }: {
  hmWrappers.programs.<name> = {
    mainPackage = pkgs.<package-name>;        # explicit beats auto-discovery
    homeModules = [ config.flake.modules.homeManager.<name> ];
  };
};
```

That's the common case. `nix run .#<name>` works immediately after
`git add -A && nix flake check --no-build`.

---

## When to add baseModules

Only needed if the aspect references `config.my.*` options. Check with:

```bash
grep -n 'config\.my\.' modules/home/<name>.nix
```

If it does, add to the top-level `hmWrappers` block:

```nix
hmWrappers.baseModules = [
  config.flake.modules.generic.my-options
];
```

If the aspect also gates config behind `lib.mkIf config.my.is_private`, pass
an unlock module in `homeModules`:

```nix
homeModules = [
  config.flake.modules.homeManager.<name>
  { my.is_private = true; }
];
```

The pi aspect was refactored to remove this gate — check the aspect source
before assuming it's needed.

---

## mainPackage: explicit vs auto-discovery

Always pass `mainPackage` explicitly when the aspect installs more than one
package (e.g. a runtime alongside the main binary). Auto-discovery picks the
first user-added package alphabetically, which may be wrong.

If the package isn't in nixpkgs by name, check with the nix-search skill first:

```bash
nix-search-tv print --indexes nixpkgs | grep -i '<name>'
```

---

## What gets wrapped automatically

| HM output | In the wrapper |
|---|---|
| `home.packages` | available in `$PATH` |
| `xdg.configFile` | bwrapped at `$XDG_CONFIG_HOME/<path>` |
| `home.file` | bwrapped at `$HOME/<path>` |
| `home.sessionVariables` | exported into the process env |
| `home.activation` | available via `passthru` only (not run by default) |

`systemd.user.services` and other machine-level side effects are silently
ignored — the wrapper is process-scoped, not system-scoped.

---

## Composing multiple aspects

To produce a bundle that combines several aspects (e.g. neovim + pi):

```nix
hmWrappers.programs.neovim-pi = {
  mainPackage = pkgs.neovim;
  homeModules = [
    config.flake.modules.homeManager.neovim
    config.flake.modules.homeManager.pi
  ];
};
```

The bwrap will cover the union of all `xdg.configFile` entries. Only do this
when the combination makes sense as a single runnable tool.

---

## Pitfalls

- **Untracked files are invisible to Nix.** `git add -A` before evaluating.
- **`autoWrap = true` is off.** It would try to wrap every `homeManager.*`
  entry including non-program aspects (base, git, ssh…). Stay on manual.
- **External HM modules.** If the aspect `imports` a module from an external
  input (e.g. catppuccin, sops-nix), that module must be reachable from the
  evaluation context. The `external` aspect closes over its inputs at
  flake-parts time, so including it in `homeModules` is safe — but it pulls in
  catppuccin, nixvim, nix-index, and sops modules. Only do this if the wrapped
  program actually needs them.
- **Hardcoded system in `_skills.nix`.** The ast-bro skill builder references
  `"x86_64-linux"` directly. Harmless on x86_64 but will fail on aarch64 if
  that's ever a target.

---

## Verify

```bash
git add -A
nix flake check --no-build          # confirms derivation evaluates
nix run .#<name> -- --version       # smoke test on the actual binary
```
