# `programs.tridactyl` — declarative Tridactyl config for home-manager

A standalone home-manager module that renders a Tridactyl rc file from Nix,
installs the Tridactyl extension into a Firefox profile, and (optionally) wires
the `tridactyl-native` messaging host. It has no dependency on this repo's
dendritic aspect store or on any `my.*` option — import it and go.

## Quick start

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    dot_nixos.url = "github:vkarasen/dot_nixos";
    # Tridactyl is not in nixpkgs — source the .xpi from somewhere.
    firefox-addons = {
      url = "git+https://gitlab.com/rycee/nur-expressions.git?ref=master&dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    dot_nixos,
    firefox-addons,
    ...
  }: {
    homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        dot_nixos.homeModules.tridactyl-module
        {
          # The profile must be declared by you; this module only appends the
          # extension to it.
          programs.firefox.profiles.default = {};

          programs.tridactyl = {
            enable = true;
            firefoxProfile = "default";
            extensionPackage =
              firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.tridactyl;

            settings = {
              hintfiltermode = "vimperator-reflow";
              hinthideobscured = true;
              editorcmd = "neovide";
            };

            binds = {
              j = "scrollline 20";
              k = "scrollline -20";
              "<BS>" = "back";
            };
          };
        }
      ];
    };
  };
}
```

## Options

| option | type | default | required | description |
|---|---|---|---|---|
| `enable` | bool | `false` | no | Enable the Tridactyl extension module. |
| `firefoxProfile` | non-empty string | `"default"` | no | Firefox profile name to attach Tridactyl to. Must match an existing `programs.firefox.profiles.<name>` key — the profile must be declared by the consumer (it cannot be derived from the profile set, since this module itself contributes to it). |
| `extensionPackage` | package | — | **REQUIRED** | The Tridactyl WebExtension package; appended to the profile's `extensions.packages` (its .xpi is installed declaratively). Tridactyl is not packaged in nixpkgs, so you must supply an .xpi derivation. |
| `nativeMessengerPackage` | null or package | `pkgs.tridactyl-native` | no | The Tridactyl native-messaging host, appended to `programs.firefox.nativeMessagingHosts`. This lets native commands such as `:editor` hand a page's text field to a GUI editor. Set to `null` to install no native-messaging host. |
| `settings` | attrs of (bool \| int \| string) | `{}` | no | Tridactyl `:set` settings, rendered one per line as `set <key> <value>`. Keys are literal rc names and may be dotted (e.g. `update.nag`). Values must be scalars — nested objects/arrays have no `set`-line rendering; put those in `extraConfig`. |
| `binds` | attrs of string | `{}` | no | Tridactyl keybindings, rendered one per line as `bind <key> <command>`. Keys are literal Tridactyl key notation (e.g. `j`, `<BS>`, `<S-BS>`). |
| `extraConfig` | lines | `""` | no | Raw tridactylrc lines appended verbatim after the generated settings and binds. Use for anything `settings`/`binds` cannot express (nested set structures, hooks, source lines, …). |

`programs.tridactyl.extensionPackage` is the only **REQUIRED** option — it has
no default. `nativeMessengerPackage` defaults to the consumer's own
`pkgs.tridactyl-native`, so it is version-correct with zero extra inputs (set it
to `null` if you don't want the host).

## What it writes

When `enable = true`:

- **`~/.config/tridactyl/tridactylrc`** — the generated rc file:
  - a one-line header comment,
  - one `set <key> <value>` line per `settings` entry,
  - one `bind <key> <command>` line per `binds` entry,
  - then `extraConfig` appended verbatim.
- **`programs.firefox.profiles.<firefoxProfile>.extensions.packages`** —
  `extensionPackage` is appended (via `mkAfter`) so the extension is installed
  into the selected profile declaratively.
- **`programs.firefox.nativeMessagingHosts`** — `nativeMessengerPackage` is
  appended (via `mkAfter`) unless it is `null`.

## You must supply the .xpi

Tridactyl is **not packaged in nixpkgs**, and there is no default for
`extensionPackage`. Source the .xpi from an add-on flake or build it yourself —
for example, [rycee's firefox-addons] exposes it as `tridactyl`:

```nix
programs.tridactyl.extensionPackage =
  inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.tridactyl;
```

Any derivation that exposes `addonId` in its `passthru` works — that is the
contract home-manager's `extensions.packages` reads (it is on the derivation,
not on the `.xpi` output).

[rycee's firefox-addons]: https://gitlab.com/rycee/nur-expressions/-/tree/master/pkgs/firefox-addons
