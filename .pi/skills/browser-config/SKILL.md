---
name: browser-config
description: How to find, change, and understand Firefox and Tridactyl configuration in
  this repo. Tridactyl is the Vim-like keybinding extension for Firefox. Use it for
  Tridactyl `:set` settings and ex commands (`:restart`, `:bind`, `:editor`), hint
  keys and labels, search keywords (searchurls), editorcmd / edit-in-$EDITOR, vim or
  vimperator-style keys and a leader key in the browser, the Firefox profile
  (profiledir, profiles.ini), Firefox home-manager options (programs.firefox.*),
  add-ons and extensions, and about:config prefs — including the generated Firefox
  preference index at ~/.config/ffprefs/index.json, served by the `tv ffpref`
  channel, to look up a Firefox preference (what does pref X do, its type, default
  and description; "ffpref", "about:config pref index"). Also for "how do I change
  X in Firefox" and "what does this browser setting, command, or key do".
---

# Browser / Tridactyl config

Tridactyl is Vim-style Firefox keybindings, wired by the `tridactyl` aspect
(`modules/home/tridactyl/default.nix`, GUI-gated on `my.gui.enable`). Firefox
itself and its add-ons live in `modules/home/browser/default.nix`. Do not guess at
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
| A raw `about:config` pref (`media.*`, `browser.*`, …)? | the generated `ffpref` index (see below), then searchfox/MDN for undocumented prefs | `jq '."<pref>"' ~/.config/ffprefs/index.json` |
| Browse / list every Firefox pref and its default? | the `tv` `ffpref` channel | `tv ffpref` |
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

This repo attaches add-ons in `modules/home/browser/default.nix`
(`programs.firefox.profiles."vkarasen".extensions.packages`, sourced from
`inputs.firefox-addons`) and the Tridactyl extension + native messenger +
`profiledir` setting, all wired through the `programs.tridactyl` home-manager
module (`modules/home/tridactyl/default.nix` supplies the starter
`settings`/`binds`; `_module.nix` renders the tridactylrc).

## Firefox preference index (`ffpref`)

Every Firefox pref (`name → {type, default, description, source, sources}`) is
indexed at build time into `~/.config/ffprefs/index.json` — a flat JSON map
generated from the pinned `firefox-unwrapped` by
`modules/home/browser/_parse-ffprefs.cjs` (the
`ffprefs-index` derivation in `modules/home/browser/default.nix`). Nothing is
committed; the `~/.config` copy is the source of truth.

- **Names / values** come from `StaticPrefList.yaml` (`type:` + `value:`, and
the `#` doc-comment as the description) merged with the RESOLVED default-pref
JS inside the `gre` / `browser` `omni.ja` archives (`greprefs.js`,
`PdfJsDefaultPrefs.js`, `firefox.js`, `firefox-branding.js`, `debugger.js`)
plus the two unpacked distro files (`channel-prefs.js`,
`nixos-default-prefs.js`). The resolved JS is the **effective on-system
default** (all `#ifdef`s already applied by the build), so it overrides the
C++ static value where both define a pref.
- **Descriptions** for JS-only prefs come from the `//` blocks in the source
`all.js` / `firefox.js` (the resolved copies have their comments stripped).
Priority: StaticPrefList doc-comment → source-JS `//` block → `""`.
- `default` is **always a string** — `type` disambiguates. `source` is the
`file:line` that supplied the default; `sources` lists every occurrence.

```bash
# one pref (the whole pref name is the JSON key)
jq '."browser.tabs.unloadOnLowMemory"' ~/.config/ffprefs/index.json

# just the names
jq -r 'keys[]' ~/.config/ffprefs/index.json

# only the description
jq -r '."media.rdd-ffmpeg.enabled".description' ~/.config/ffprefs/index.json
```

Interactive browser: `tv ffpref` (channel from
`modules/home/television/default.nix`; preview shows Description / Type /
Default / Source).

### Record → `profiles.<name>.settings`

`programs.firefox.profiles."<name>".settings` is the pref name → value, so map
by the record's `type`:

| `type` | Nix value |
| --- | --- |
| `bool` | `true` / `false` |
| `int` | the integer, e.g. `2` |
| `string` | a quoted string, e.g. `"Ask Every Time"` |
| `float` | a JSON **string**, e.g. `"1.5"` |
| `other` | inspect `source` (a `@TOKEN@` build value or an exotic C++ type) |

### Refresh / fallback

The index is regenerated every build from your nixpkgs Firefox, so there is no
snapshot to refresh by hand. To move to a newer Firefox, bump the nixpkgs pin
and rebuild:

```bash
nix flake lock --update-input nixpkgs
nh home switch
```

If a pref has an empty `description`, open its `source` `file:line` on
searchfox (e.g. `https://searchfox.org/mozilla-central/source/<path>#<line>`),
or consult arkenfox's `user.js` for hardening prefs.

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
`about:config` prefs **are** indexed — see the “Firefox preference index
(`ffpref`)” section above; fall back to searchfox.org / MDN only for a pref the
index leaves with an empty `description`.

## Sibling skills

- `nix-search` — Firefox/`programs.*` option lookup; **always first** for an option.
- `config-change` — how the dendritic aspects fit together when editing the config.
- `pi-config` — changes under `modules/home/pi/`.
