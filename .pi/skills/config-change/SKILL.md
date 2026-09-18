---
name: config-change
description: How to find, change, add, remove, or understand this NixOS/home-manager
  config — which aspect holds a setting, host vs shared vs class-gated changes, and
  navigating the config from code instead of a frozen inventory. Use whenever asked
  to change, add, remove, investigate, or rebuild anything in this dotfiles repo.
---

# Changing this config

The operational funnel for working in this repo. The repo `AGENTS.md` is the
canonical reference for the dendritic pattern, the aspect-authoring recipes,
and the pitfalls — read it for the full spec. This skill is the decision tree
on top of it, plus the facts that are *not* discoverable from the file tree
alone.

## The model (three lines)

- **Dendritic flake-parts**: every `.nix` under `modules/` is a flake-parts
  module (an "aspect"), auto-imported by `import-tree`. Add a file and it
  works — there is no central import list to edit.
- **Classes**: each aspect declares `flake.modules.<class>.<name>` where
  `<class>` is `homeManager` | `nixos` | `darwin` | `generic`. `import-tree`
  auto-*registers* every aspect; *selection* is explicit per host
  (`modules/hosts/<name>.nix` lists `nixos.*` in `modules` and `homeManager.*`
  in `homeModules`), and the standalone portable config opts into the universal
  `homeManager.core` bundle.
- **Discriminators** (declared in `modules/options.nix`) describe the
  deployment context many aspects react to: `my.is_nixos`, `my.host`,
  `my.is_private`. Two more — `my.gui.enable` and `my.laptop.enable` — are
  *derived*: set true by the `desktop` / `laptop` aspect when it is imported,
  not hand-set at the top level.

## The live map (never a frozen inventory)

- `ls modules/home/ modules/nixos/` **is** the aspect index — it regenerates as
  files are added, so prefer it over any hardcoded directory list.
- `modules/hosts/<name>.nix` **is the manifest** — the authoritative list of
  which `nixos.*` aspects this host imports. "Is impermanence / Secure Boot /
  disko active on this host?" is answered by reading that file, never from
  memory.
- Machine-specific home aspects (`desktop`, `kanshi`, `laptop`) are selected
  per host in `modules/hosts/<name>.nix`'s `homeModules` list — a headless or
  foreign host simply does not list them. The universal `modules/home/core.nix`
  bundle imports everything else.

## Discovery funnel

1. **Orient** — `ls` the aspect dirs; read `modules/hosts/<host>.nix`.
2. **Locate** by domain:
   - shared home concern → `modules/home/<name>.nix`
   - system concern (boot, disks, power, services, network) → `modules/nixos/<name>.nix`
   - this machine only → `modules/hosts/<name>.nix`
3. **Read** the aspect (`module_report` / `read_symbol` / plain read).
4. **Verify** every option and package name with the `nix-search` skill — never
   guess (the repo `AGENTS.md` "Looking up options & packages" mandates this).
5. **Check the discriminator / selection** — is the setting in a
   machine-specific aspect (`desktop`, `kanshi`, `laptop`, selected per host),
   or gated by an environment discriminator (`my.is_private`, `my.is_nixos`)?
6. **Change**, then `git add -A && nix flake check` — never just `nix build`
   (pitfall #6: the two commands do not test the same thing).

## Class rules — apply only when the discriminator says so

Facts that are *not* in the file tree and that you would otherwise get
confidently wrong. Each names its source file so you re-verify rather than
trust this summary.

### NixOS host (`my.is_nixos`)

- **Apply changes with `nixos-rebuild switch --flake .#<host>`**; identify the
  current host via `readlink -f /run/current-system`. Services are systemd
  units (`systemctl` / `journalctl`).
- **Impermanence is live** (`modules/nixos/impermanence.nix`): root is
  erase-on-boot; `/persist` is the only path that survives a reboot. Never
  treat a non-`/persist` path as durable. Disks are disko-declared LUKS+btrfs
  (`modules/nixos/disks.nix`) — never hand-edit `/etc/fstab`.
- **Secure Boot via Lanzaboote** (`modules/nixos/boot.nix`): the boot chain is
  signed; key enrollment is manual (no surprise reboot — the user enters BIOS
  Setup Mode first). Any bootloader/TPM/enrollment change is a reviewer-gate
  change.
- **Heavy builds offload to a remote builder** (`modules/nixos/remote-builder.nix`):
  route `nixos-rebuild`, large `nix build`, and `nixos-test` there, not the
  laptop CPU.

### Host `troy` (`my.host == "troy"`)

- **The lid does not suspend** (`modules/nixos/laptop.nix`): logind ignores the
  lid switch; a `lid-grace-watch` timer schedules `suspend-then-hibernate` only
  on **battery + lid closed, after a 5-minute grace** (and then hibernates
  after a further 15 min suspended). On AC, closing the lid is clamshell mode —
  nothing happens. The default "lid → sleep" assumption is wrong here.
- **Idle suspend** (`modules/home/laptop.nix`): `hypridle` (a laptop-only
  aspect) suspends on **5 min idle on battery** via `suspend-then-hibernate`
  (same 15-min hibernate delay). It honours the Wayland idle-inhibit lock, so
  browsers/players pause the timer during playback. On AC, idle does nothing.
  Never auto-locks on idle — it locks via `before_sleep_cmd` right before
  suspending.
- **Battery is capped at 80%** (charge to 80%, resume recharging at 75%) — a
  battery that "stops at 80%" is by design, not a fault.
- **Battery exception mode** (Fn12): charges to **100/95** for one stretch —
  the phone-style "charge to full just this once". Toggles via Fn12
  (`battery-exception-toggle`); reverts on AC disconnect or a second press. The
  armed flag lives in `/run/user/1000/battery-exception` (tmpfs → never
  survives reboot). Thresholds are applied by the root `battery-exception-watch`
  timer in `modules/nixos/laptop.nix` (EC values are root-only; the user toggle
  only flips the flag — see the recipe below).
- **EC write-order gotcha**: the EC rejects any write that would leave
  `start >= end`, so write in order — **raise = end first, lower = start
  first**. `75/80` (default) and `95/100` (exception) are both valid.
- ThinkPad T14s Gen 1, Intel Comet Lake — Intel-only GPU, no NVIDIA
  considerations.

#### Fn (top-row special) keys

The Fn secondary functions on this T14s. **Fn1–Fn6** are bound in Hyprland via
XF86 keysyms (mute / vol- / vol+ / mic-mute / bright- / bright+) — generic media
keys, so they belong to the shared `modules/home/desktop.nix`. **Fn7–Fn12** are
ThinkPad-specific; they arrive as **raw evdev codes** from the
`thinkpad-extra-buttons` input device (not XF86 keysyms).

**Gotcha — Hyprland's `code:N` is the XKB keycode, i.e. `evdev + 8`**, not the
evdev code (verified empirically: Fn9’s evdev 444 binds as `code:452`; a
`code:444` bind registers but silently never fires). The `evdev` column is what
`evtest`/hwdb report; the `bind` column is the value to use:

| Fn key | evdev | Hyprland bind | intended action |
| --- | --- | --- | --- |
| Fn7 | 227 | `code:235` | external displays (KEY_SWITCHVIDEOMODE) |
| Fn8 | 238 | `code:246` | airplane mode (KEY_WLAN) — firmware rfkill, hard to reclaim |
| Fn9 | 444 | `code:452` | notifications / quick settings (KEY_NOTIFICATION_CENTER) |
| Fn10 | 445 | `code:453` | answer VoIP call (KEY_PICKUP_PHONE) |
| Fn11 | 446 | `code:454` | hang up VoIP call (KEY_HANGUP_PHONE) |
| Fn12 | 156 | `code:164` | battery exception toggle (`battery-exception-toggle`) — KEY_BOOKMARKS, verified |

Keyboard backlight is Fn+Space (evdev 228 → `code:236`, KEY_KBDILLUMTOGGLE).
Fn7 remains the cleanest unbound repurpose target; Fn9 (screen toggle) and
Fn12 (battery exception) are taken; Fn8 toggles radios in firmware, and
Fn10/Fn11 are VoIP-call keys with no natural desktop role.

Only Fn9 and Fn12 have been **verified empirically** (evtest + a working bind);
Fn7/Fn8/Fn10/Fn11 are from hwdb/thinkpad_acpi and untested — verify the evdev
code with `evtest` before trusting a bind (ladder below).

These binds are **hardware-specific to troy** — not generic laptop behaviour —
so they do NOT belong in `modules/home/laptop.nix` (which any laptop host
reuses). They live in the host's own home aspect,
`flake.modules.homeManager.troy` in `modules/hosts/troy.nix`, mirroring the
host-specific Intel driver in `flake.modules.nixos.troy`. (`settings.bind` is a
merged list, so binds there concatenate with desktop.nix's.) Fn9 toggles the
internal panel's DPMS state via the `laptop-screen-toggle` helper; the shape is:

```nix
wayland.windowManager.hyprland.settings.bind = [
  {_args = [
    "code:452" # Fn9 (evdev 444 → xkb 452) — internal panel DPMS on/off
    (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("laptop-screen-toggle")'')
  ];}
];
```

#### Keybinding verification ladder

When an Fn key (or any `code:` bind) doesn't fire, work top-down — each layer
narrows where the key is lost:

1. **`evtest`** (kernel) — does the key emit at all? Shows the evdev code
   (`code 156 (KEY_BOOKMARKS)`). `nix run nixpkgs#evtest`, pick the
   `ThinkPad Extra Buttons` device.
2. **`wev`** (compositor → client) — what Hyprland forwards. **A key bound in
   Hyprland is consumed and will NOT appear in `wev`; silence here usually
   means the bind is working, not broken.** An unbound key shows up as `key: N`
   — that `N` is the value `code:` needs.
3. **`hyprctl binds`** (compositor) — what Hyprland actually registered. From a
   non-GUI shell it needs `HYPRLAND_INSTANCE_SIGNATURE` set to the current
   `/run/user/1000/hypr/<sig>` directory name.

The evdev→xkb offset is **+8** (Fn9 444→`code:452`; Fn12 156→`code:164`).

## Reusable recipes

Patterns that recur when adding Fn-key buttons + status widgets on troy.

### User-toggle → root-apply (privileged action from an Fn key)

The Fn key runs as the user; the EC/battery sysfs is root-only. Bridge them
with a **user-writable flag file + a root systemd timer that polls it** — no
polkit/udev, and it mirrors the existing `lid-grace-watch` idiom:

- flag: `/run/user/1000/<name>` (tmpfs → clears on reboot), written by a
  `writeShellApplication` in `modules/home/laptop.nix`, exposed via
  `home.packages`.
- watcher: `systemd.timers.<name>` (`wantedBy = ["timers.target"]`,
  `OnUnitActiveSec = "2s"`) + a root `Type = "oneshot"` service that reads the
  flag, applies the effect, and reverts/clears it on the exit condition
  (here: AC disconnect).
- bind: `modules/hosts/troy.nix` → `hl.dsp.exec_cmd("<name>")`.

### waybar conditional indicator (glow / show-on-state)

`custom/<name>` with `exec` emitting JSON, hidden when empty:

```nix
"custom/battery-exception" = {
  exec = "battery-exception-status"; # emits JSON text+class, or empty text
  interval = 2;
  return-type = "json";
  hide-empty-text = true;            # empty text hides the module
};
```

Style via `#custom-<name>.<class>` in the `style` string. Two traps:
- the waybar `style` is **CSS inside a Nix `''` string** — comments are
  `/* ... */`, never `#` (`#` is an ID selector and breaks parsing).
- the `exec` script must be on PATH (add it to `home.packages`).

### Shell-script gotchas (bite every `script=` / `writeShellApplication`)

- NixOS `systemd.services.*.script` **and** `writeShellApplication` both run
  under `set -e`; `writeShellScriptBin` does not.
- `read -r x < file` returns **1 on an empty file** (immediate EOF), which
  under `set -e` silently aborts. Always `read ... || true` (and guard a
  possibly-missing file with `[ -r file ]`).
- Redirections apply left-to-right: `cmd < file 2>/dev/null` does **not**
  suppress "file not found" — `< file` fails before `2>/dev/null` takes effect.
  Guard with `[ -r file ]` instead of relying on `2>/dev/null`.

## Sibling skills

- `nix-search` — option/package lookup; **always first** for any option or package.
- `pi-config` — changes under `modules/home/pi/` (pi packages/skills/policies).
- `bundle-module` — wrap an aspect as a standalone `nix run .#name` package.
- `edit-private-skill` — sops-encrypted skills/policy sections.
- `version-control` — branch/worktree lifecycle when a change is experimental.
