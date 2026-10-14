# tv channels: Firefox prefs & Tridactyl settings

Two standalone home-manager modules that each build a generated JSON index and
wire it to a [`television`] (`tv`) channel:

- `programs.tridactyl-index` → `~/.config/tridactyl/index.json` + the `tridactyl` channel
- `programs.ffpref` → `~/.config/ffprefs/index.json` + the `ffpref` channel

The JSON is plain data and is usable on its own (any `jq`/script consumer); the
`tv` channel is just a browsing front-end on top of it. Neither module depends
on this repo's dendritic aspect store or on any `my.*` option. They are
independent of each other and of `programs.tridactyl`.

Both consume the consumer's own package set: `programs.tridactyl-index` builds
from a Tridactyl *source tree* you supply; `programs.ffpref` builds from your
own `pkgs.firefox-unwrapped`, so it is automatically version-correct with **zero
extra inputs**.

## `programs.tridactyl-index`

Generated Tridactyl index of `:set` settings (namespaced `set.*`, from
`src/lib/config.ts`) and ex commands (namespaced `excmd.*`, from
`src/excmds.ts`), built from the source tree you point it at.

| option | type | default | required | description |
|---|---|---|---|---|
| `enable` | bool | `false` | no | Enable the generated Tridactyl settings/ex-command index (and its `tv` channel). |
| `source` | path | — | **REQUIRED** | The Tridactyl source tree, e.g. a `github:tridactyl/tridactyl` flake input declared with `flake = false`. |

**Materializes:** `~/.config/tridactyl/index.json`.

**Channel:** `tv tridactyl` — lists every index key; the preview shows the
description, type/default (or params/mode for excmds), and source location.

The `source` input requirement — declare the Tridactyl tree as a source input:

```nix
{
  inputs.tridactyl = {
    url = "github:tridactyl/tridactyl";
    flake = false; # a source tree, not a flake
  };

  # ...
  modules = [
    dot_nixos.homeModules.tridactyl-index-module
    {
      programs.tridactyl-index = {
        enable = true;
        source = inputs.tridactyl;
      };
    }
  ];
}
```

## `programs.ffpref`

Generated Firefox-preference index: every pref name from the pinned
`firefox-unwrapped` mapped to type / default / description / source, built from
`StaticPrefList.yaml`, the resolved JS default-pref files, and the
description-only JS files shipped with that same Firefox.

| option | type | default | required | description |
|---|---|---|---|---|
| `enable` | bool | `false` | no | Enable the generated Firefox-preference index (and its `tv` channel). |

**Materializes:** `~/.config/ffprefs/index.json`.

**Channel:** `tv ffpref` — lists every pref name; the preview shows the
description, type/default, and source location.

**Zero extra inputs:** `programs.ffpref` needs nothing beyond your own
`pkgs.firefox-unwrapped` — no source input, no configuration. It derives the
index from the Firefox in *your* nixpkgs, so the prefs always match the browser
you run.

## Prerequisite: enable `television`

The generated JSON is usable without `tv`, but **interactive `tv` browsing
requires the `television` program**. The two index modules' channel commands
are self-contained shell scripts: `jq` and `fold` are bundled into the script
via `writeShellApplication` (`runtimeInputs`), so no `jq` on the consumer's own
PATH is needed. The *only* thing a consumer must enable themselves is the
home-manager module that provides `tv`:

```nix
programs.television.enable = true;
```

Both channels declare `source.command` and `preview.command` as `lib.mkDefault`
defaults, so a consumer can override either to supply their own lister or
viewer (e.g. `lib.mkForce` a different command).

This is home-manager's built-in `programs.television` module (it installs
`pkgs.television` by default; override `programs.television.package` if you
want a different build). The two index modules only *declare channels* under
`programs.television.channels.<name>` — they do not enable `tv` themselves, so a
consumer who enables `programs.tridactyl-index`/`programs.ffpref` without
`programs.television.enable = true` gets the index file but no interactive
browsing.

[`television`]: https://github.com/alexpasmantier/television
