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
  `<class>` is `homeManager` | `nixos` | `darwin` | `generic`. Hosts are
  `modules/hosts/<name>.nix`; the assembly folds `nixos.*` + `generic.*` per
  host and `homeManager.*` + `generic.*` into every host.
- **Discriminators** (declared in `modules/options.nix`) select which class
  rules apply to this machine: `my.is_nixos`, `my.gui.enable`, `my.host`.

## The live map (never a frozen inventory)

- `ls modules/home/ modules/nixos/` **is** the aspect index — it regenerates as
  files are added, so prefer it over any hardcoded directory list.
- `modules/hosts/<name>.nix` **is the manifest** — the authoritative list of
  which `nixos.*` aspects this host imports. "Is impermanence / Secure Boot /
  disko active on this host?" is answered by reading that file, never from
  memory.
- GUI aspects (`modules/home/desktop.nix`, `modules/home/kanshi.nix`) self-gate
  on `config.my.gui.enable`, so a headless host genuinely omits them.

## Discovery funnel

1. **Orient** — `ls` the aspect dirs; read `modules/hosts/<host>.nix`.
2. **Locate** by domain:
   - shared home concern → `modules/home/<name>.nix`
   - system concern (boot, disks, power, services, network) → `modules/nixos/<name>.nix`
   - this machine only → `modules/hosts/<name>.nix`
3. **Read** the aspect (`module_report` / `read_symbol` / plain read).
4. **Verify** every option and package name with the `nix-search` skill — never
   guess (the repo `AGENTS.md` "Looking up options & packages" mandates this).
5. **Check the discriminator** — is the setting gated by `my.gui.enable` /
   `my.is_nixos`, or specific to one host?
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

- **The lid does not suspend** (`modules/nixos/power.nix`): logind ignores the
  lid switch; a `lid-grace-watch` timer schedules `suspend-then-hibernate` only
  on **battery + lid closed, after a 5-minute grace** (and then hibernates
  after a further 15 min suspended). On AC, closing the lid is clamshell mode —
  nothing happens. The default "lid → sleep" assumption is wrong here.
- **Battery is capped at 80%** (charge to 80%, resume recharging at 75%) — a
  battery that "stops at 80%" is by design, not a fault.
- ThinkPad T14s Gen 1, Intel Comet Lake — Intel-only GPU, no NVIDIA
  considerations.

## Sibling skills

- `nix-search` — option/package lookup; **always first** for any option or package.
- `pi-config` — changes under `modules/home/pi/` (pi packages/skills/policies).
- `bundle-module` — wrap an aspect as a standalone `nix run .#name` package.
- `edit-private-skill` — sops-encrypted skills/policy sections.
- `worktrunk` — branch/worktree lifecycle when a change is experimental.
