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

Use the direct `wlib` API (not the `hmWrappers.programs` flake-parts interface —
that was removed from `wrapped-packages.nix` when we needed composition hooks).
Add a new entry inside the existing `let` block in `wrapped-packages.nix`:

```nix
perSystem = { pkgs, lib, ... }: let
  wlib = inputs.hm-wrapper-modules.lib;

  base = wlib.wrapHomeModule {
    inherit pkgs;
    mainPackage = pkgs.<package-name>;   # explicit beats auto-discovery
    homeModules = [ config.flake.modules.homeManager.<name> ];
    home-manager = inputs.home-manager;
  };

  binds = wlib.mkBinds base.passthru.hmAdapter;

  bwrapped = base.wrap ({ config, lib, ... }: {
    imports = [ wlib.modules.bwrapConfig ];
    bwrapConfig.binds.ro = binds;
    env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
    # Add any packages the program needs at runtime that aren't in home.packages
    # (see pitfall: programs.<name>.extraPackages is not captured by hm-adapter)
    # extraPackages = [ pkgs.nodejs ];
  });

  precreate = lib.concatMapStringsSep "\n" (dest: ''
    mkdir -p "$HOME/$(dirname "${dest}")"
    touch "$HOME/${dest}" 2>/dev/null || true
  '') (builtins.attrValues binds);
in {
  packages.<name> = pkgs.writeShellScriptBin "<name>" ''
    ${precreate}
    exec ${bwrapped}/bin/<name> "$@"
  '';
}
```

`nix run .#<name>` works immediately after `git add -A && nix flake check --no-build`.

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

## Foreign machine pitfalls (learned in production)

**bwrap bind destinations must exist before bwrap runs.**
bwrap cannot create bind targets — it can only mount over existing paths. On a
machine where HM has never activated, `~/.pi/agent/settings.json` and
`~/.config/rpiv-web-tools/config.json` don't exist. bwrap fails immediately
with `Can't create file at --ro-bind: Permission denied`.

Fix: pre-create every bind destination with `mkdir -p` + `touch` before the
bwrap invocation. Use `builtins.attrValues binds` (the values from `wlib.mkBinds`)
as the single source of truth — it covers both `home.file` and `xdg.configFile`
entries. Pre-creating only `xdgConfigFiles` misses `home.file` destinations and
produces the same error.

**Do not replace bwrap with `XDG_CONFIG_HOME` redirect.**
Pointing `XDG_CONFIG_HOME` at a store path seems simpler, but the store is
read-only. Any program that writes mutable state under `$XDG_CONFIG_HOME`
(npm package cache, session state, downloaded plugins) will crash immediately.
bwrap is correct because it leaves `$HOME/.config/` writable and only
shadow-mounts specific files on top.

**`programs.<name>.extraPackages` is invisible to the hm-adapter.**
The hm-adapter captures `home.packages` → `extraPackages` in the wrapper PATH.
Packages declared via `programs.<name>.extraPackages` are wired into the
program's `makeWrapper` script by the HM module, but that does NOT add them to
`home.packages`. On a foreign machine they won't be in PATH.

Fix: declare them explicitly in the `base.wrap` call:

```nix
extraPackages = [ pkgs.nodejs pkgs.bun ];
```

**Do not read `hmConfig.programs.*` to recover extraPackages.**
Accessing any attribute under `hmConfig.programs` forces full evaluation of
the entire HM programs module tree, which can hit `mkRemovedOptionModule`
assertions from unrelated removed options (e.g. `programs.octant`). Declare
extraPackages explicitly in `wrapped-packages.nix` instead.

**The wrapped `mainPackage` may itself already be a bwrap wrapper.**
When an HM module generates a `makeWrapper`-wrapped binary (as pi's HM module
does), the package you get from `wlib.wrapHomeModule` is a shell script that
sets PATH and invokes bwrap — not the raw binary. This is normal and correct;
just be aware when reading the generated wrapper script that there are two
layers of wrapping.

**OAuth token scope failures look like network errors.**
If a wrapped program auto-discovers credentials (e.g. a `gh` CLI token from
`~/.config/gh/hosts.yml`) and uses them for a provider that requires additional
scopes, the provider returns `400` — not `401`. Programs that handle expired
tokens (401) correctly may not handle misscoped tokens (400) correctly: they
show an error and re-prompt, but re-login still fails because they reuse the
discovered token. The fix is clearing or upgrading the existing credential,
not retrying the login flow.

---

## Verify

```bash
git add -A
nix flake check --no-build          # confirms derivation evaluates
nix run .#<name> -- --version       # smoke test on the actual binary
```
