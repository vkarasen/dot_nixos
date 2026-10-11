---
name: browser-config
description: How to find, change, and understand Firefox and Tridactyl configuration in
  this repo. Tridactyl is the Vim-like keybinding extension for Firefox. Use it for
  Tridactyl `:set` settings and ex commands (`:restart`, `:bind`, `:editor`), hint
  keys and labels, search keywords (searchurls), editorcmd / edit-in-$EDITOR, vim or
  vimperator-style keys and a leader key in the browser, the Firefox profile
  (profiledir, profiles.ini), Firefox home-manager options (programs.firefox.*),
  add-ons and extensions, and about:config prefs. Also for "how do I change X in
  Firefox" and "what does this browser setting, command, or key do".
---

# Browser / Tridactyl config

Tridactyl is Vim-style Firefox keybindings, wired by the `tridactyl` aspect
(`modules/home/tridactyl/default.nix`, GUI-gated on `my.gui.enable`). Firefox
itself and its add-ons live in `modules/home/browser.nix`. Do not guess at
setting names or Firefox prefs — route by kind of question first.

## When to use

Load this for (non-exhaustive):

- Tridactyl — `:set` / `:bind` / `:restart` / `:editor` ex commands, hints,
  search keywords (searchurls), editorcmd, "vim keys / leader key in the browser",
  "edit a textarea in $EDITOR".
- Firefox — the profile / profiledir / profiles.ini, `programs.firefox.*`
  home-manager options, add-ons and extensions, `about:config` prefs.
- Indirect phrasings — "how do I change X in Firefox", "what does this key /
  command / setting do", "make hint labels single letters", "add a search
  keyword", "why doesn't `/` search work here".

## Routing table (question → where to look → command)

| Question | Where to look | Command |
| --- | --- | --- |
| What does a Tridactyl `:set` setting do / its type / default? | build-time index (`~/.config/tridactyl/index.json`, key `set.<key>`, generated from the pinned `tridactyl` flake input) | `jq '."set.<key>"' ~/.config/tridactyl/index.json` |
| What `:set` settings exist at all? | same index, `set.*` keys | `jq -r 'keys[]' ~/.config/tridactyl/index.json` |
| What does an ex command (`:restart`, `:bind`, …) do? | same index, `excmd.<command>` (generated from `src/excmds.ts`) | `jq '."excmd.restart"' ~/.config/tridactyl/index.json` |
| Which Tridactyl keybindings are set here? | `programs.tridactyl.binds`, not the index | `read modules/home/tridactyl/default.nix` (+ `_module.nix`) |
| Firefox home-manager option (`programs.firefox.*`)? | the `nix-search` skill | `nix-search-tv print --indexes home-manager \| grep -i '<opt>'` |
| A raw `about:config` pref (`media.*`, `browser.*`, …)? | searchfox.org / MDN — not indexed here | delegate to a `researcher` |
| Browses settings interactively? | `tv` `tridactyl` channel | `tv tridactyl` (`modules/home/television/default.nix`) |

## Querying the settings index

The index is a flat JSON map, namespaced by kind: `set.<key> →
{description, type, default, source, kind: "set"}` and `excmd.<command> →
{description, params, source, mode, kind: "excmd"}`. The `set.` / `excmd.`
prefix is a **namespace marker**, not part of the literal name: the rc for
`set.update.nag` is written `:set update.nag`, and the command for
`excmd.restart` is `:restart`.
It is generated at build time from the pinned `tridactyl` flake input (by
`_parse-config.cjs`/`_parse-excmds.cjs` in the `tridactyl-index` derivation)
and materialized by home-manager at `~/.config/tridactyl/index.json`
(`xdg.configFile."tridactyl/index.json"`, gated on `my.gui.enable`). Nothing
is committed; the `~/.config` copy is the source of truth.

```bash
# one setting (note the dotted `set.profiledir` key)
jq '."set.profiledir"' ~/.config/tridactyl/index.json

# one ex command
jq '."excmd.restart"' ~/.config/tridactyl/index.json

# just the names
jq -r 'keys[]' ~/.config/tridactyl/index.json

# description only, when the blob is noisy
jq -r '."set.<key>".description' ~/.config/tridactyl/index.json
```

Query with `nix run nixpkgs#jq -- …` if `jq` is not on PATH. For an interactive
browse of every key + its description, use the `tv tridactyl` channel.

## Regenerating the index

The index is generated at build time from the pinned `tridactyl` flake input,
so there is no snapshot file to refresh by hand. To pick up newer upstream
settings, bump the pin and rebuild:

```bash
nix flake lock --update-input tridactyl
nh home switch
```

The parser `modules/home/tridactyl/_parse-config.cjs` (and `_parse-excmds.cjs`)
runs inside the `tridactyl-index` derivation (built by
`modules/home/tridactyl/default.nix`)
using `pkgs.typescript_5` — **not** `pkgs.typescript`, which is the Go-native
7.x compiler with no JS API.

## Firefox home-manager options

For anything under `programs.firefox.*` (profiles, `profilesPath`,
`extensions.packages`, `nativeMessagingHosts`, prefs), load the **`nix-search`
skill** and look it up — never guess the attribute path or type:

```bash
nix-search-tv print --indexes home-manager | grep -i 'firefox'
nix-search-tv preview --indexes home-manager --json 'programs.firefox.profiles'
```

This repo attaches add-ons in `modules/home/browser.nix`
(`programs.firefox.profiles."vkarasen".extensions.packages`, sourced from
`inputs.firefox-addons`) and the Tridactyl extension + native messenger +
`profiledir` setting, all wired through the `programs.tridactyl` home-manager
module (`modules/home/tridactyl/default.nix` supplies the starter
`settings`/`binds`; `_module.nix` renders the tridactylrc).

## Declarative Firefox config (`programs.firefox.profiles."<name>"`)

The interesting config is the profile submodule: `settings`, `bookmarks`, and
`search`.

### `settings` — `about:config` prefs

`profiles."<name>".settings` maps `about:config` pref names to values
(`int`/`bool`/`str`, plus attrs/lists/floats as JSON strings). Home-manager
writes these to the profile's **`user.js`**, which Firefox re-reads at **every
launch** and which **overrides `prefs.js`** (Firefox's own runtime store). So a
value here is a *declared default*: it can be overridden at runtime, but a
runtime override of a declared key **reverts on restart**. Make changes stick by
declaring them here.

```nix
programs.firefox.profiles."<name>".settings = {
  "browser.startup.homepage" = "https://nixos.org";
  "browser.search.region" = "GB";
  "media.av1.enabled" = false;
};
```

### `bookmarks` — declarative bookmarks

`profiles."<name>".bookmarks.settings` is a list of bookmarks, directories, and
`"separator"` strings. A bookmark is `{ name, url, tags?, keyword? }`; a
directory is `{ name, toolbar?, bookmarks = [ … ]; }`. Home-manager generates a
`bookmarks.html` and sets `browser.bookmarks.file` +
`browser.places.importBookmarksHTML = true`, so Firefox imports it into
`places.sqlite` at startup; `bookmarks.force` (default `false`) toggles
replace-vs-merge.

```nix
programs.firefox.profiles."<name>".bookmarks.settings = [
  { name = "wikipedia"; tags = [ "wiki" ]; keyword = "wiki";
    url = "https://en.wikipedia.org/wiki/Special:Search?search=%s&go=Go"; }
  "separator"
  { name = "Nix sites"; toolbar = true; bookmarks = [
      { name = "homepage"; url = "https://nixos.org/"; }
      { name = "wiki"; tags = [ "wiki" "nix" ]; url = "https://wiki.nixos.org/"; }
    ]; }
];
```

### `search` — search engines

`profiles."<name>".search = { default, privateDefault, order, engines }`.
Home-manager writes `search.json.mozlz4`. A custom engine (`engines.<id>`) has
`name`, `urls` (`{ template, params }`), `icon`, `definedAliases`; for a builtin
engine set only `metaData` (e.g. `google.metaData.alias = "@g"`).

```nix
programs.firefox.profiles."<name>".search = {
  default = "ddg";
  order = [ "ddg" "google" ];
  engines = {
    nix-packages = {
      name = "Nix Packages";
      urls = [{ template = "https://search.nixos.org/packages";
                params = [ { name = "type"; value = "packages"; }
                           { name = "query"; value = "{searchTerms}"; } ]; }];
      definedAliases = [ "@np" ];
    };
    google.metaData.alias = "@g";
  };
};
```

### Defaults vs runtime (`user.js` vs `prefs.js`)

- `~/.config/mozilla/firefox/<name>/user.js` — home-manager-declared (store
  symlink), re-applied every launch.
- `~/.config/mozilla/firefox/<name>/prefs.js` — Firefox's runtime store; holds
  every pref changed via `about:config`, rewritten by Firefox on exit.

### Factory reset

```bash
# quit Firefox, then:
rm -rf ~/.config/mozilla/firefox/<name>/
nh home switch     # recreates user.js, profiles.ini, .keep, extensions
# start Firefox   # recreates prefs.js, places.sqlite, cookies, etc. fresh
```

Declared bookmarks re-import from `bookmarks.html`, and declared search engines
re-apply from `search.json.mozlz4`, so both survive the reset.

### Reading runtime prefs (and promoting them to the flake)

```bash
cat ~/.config/mozilla/firefox/<name>/user.js            # declared (enforced)
grep 'user_pref' ~/.config/mozilla/firefox/<name>/prefs.js   # runtime
```

A pref in `prefs.js` but NOT in `user.js` is runtime-only — a candidate to
promote into `programs.firefox.profiles."<name>".settings` so the flake
enforces it everywhere.

## What is deliberately NOT in the index

The index covers **`:set` settings** (keys `set.*`) and **ex commands** (keys
`excmd.*`). The `set.*` records are generated from `src/lib/config.ts`; these
fields are mutated by other commands (the parser excludes them — see `EXCLUDE`
in `_parse-config.cjs`), so look them up in the relevant command's docs, not the
index:

| Field(s) | Changed with |
| --- | --- |
| `nmaps`, `exmaps`, `imaps`, `inputmaps`, `ignoremaps`, `vmaps`, `hintmaps`, `browsermaps` | `:bind` (keybinding maps) |
| `exaliases` | `:alias` |
| `subconfigs`, `modesubconfigs` | `:seturl` / `:unseturl`, `:setmode` / `:unsetmode` |
| `abbreviations` | `:abbreviate` |

Ex commands **are** indexed now (as `excmd.*`) — use
`jq '."excmd.<command>"'` rather than the upstream docs URL. What is still
**not** indexed: keybinding maps and aliases (`:bind` / `:alias`) — read the
starter rc in `modules/home/tridactyl/default.nix` for those. Offline, the
`.xpi` from `inputs.firefox-addons` contains `static/docs/`. Raw Firefox
`about:config` prefs are not indexed anywhere in this repo — look them up on
searchfox.org / MDN via a `researcher`.

## Sibling skills

- `nix-search` — Firefox/`programs.*` option lookup; **always first** for an option.
- `config-change` — how the dendritic aspects fit together when editing the config.
- `pi-config` — changes under `modules/home/pi/`.
