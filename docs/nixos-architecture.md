# NixOS host `troy` — architecture & recovery

The authoritative map of how this machine is built, where its secrets live, and
how to recover it when something breaks. Read alongside `docs/nixos-install.md`
(install runbook) and `docs/nixos-debugging.md` (live, no-network debugging).

## Boot chain (power-on → login)

`my.boot.mode` selects one of two chains (see `docs/boot-modes.md`). The steps
below are the **uefi** branch (`my.boot.mode == "uefi"`, troy):

1. UEFI firmware loads **systemd-boot**, signed by Lanzaboote (Secure Boot).
2. systemd-boot loads a signed **UKI** (kernel + initrd + cmdline) from the ESP.
3. The initrd (systemd) **TPM2-unlocks** the LUKS root bound to **PCR 7**
   (Secure Boot state). If the PCR state doesn't match, it falls back to the
   **LUKS passphrase** prompt.
4. The **rollback** service re-snapshots the ephemeral root from `root-blank`
   (skipped on a resume-from-hibernate boot).
5. Boot continues: dbus → NetworkManager → sshd → home-manager.

**Legacy branch** (`my.boot.mode == "legacy"`, sarasti): BIOS/CSM firmware loads
**GRUB** from the disk's 1 MiB EF02 `bios_grub` partition; GRUB reads kernel +
initrd from the unencrypted ext4 `/boot`, and the **initrd** unlocks LUKS —
identical from step 3 onward. GRUB also chainloads Windows via os-prober.
There is no Secure Boot and no UKI in this branch.

## Storage (btrfs inside LUKS)

**Single-disk** hosts (`my.disks.persistDevice = null` — troy):

- LUKS: the partition on **the device named by `my.disks.mainDevice`** (`p2`
  on troy's `/dev/nvme0n1`) → `/dev/mapper/cryptroot` (argon2id,
  `allowDiscards`).
- Subvolumes: `root` (ephemeral), `home` (persistent), `nix`, `persist`, `log`,
  `swap` (32G hibernation swapfile), `games` (Steam library), `root-blank`
  (read-only pristine snapshot).
- Impermanence: only `root` is erased each boot; `/home`, `/nix`, `/persist`,
  `/var/log`, `/swap`, `/games` survive. `/persist` holds the opt-in state (SSH
  host keys, sops, Secure Boot keys, machine-id, …).

**Two-disk** hosts (`my.disks.persistDevice` set — sarasti): the same system
side, plus a **second** LUKS2 container for the data that must outlive a
reinstall.

- `/dev/mapper/cryptroot` — on the **2 TB WD_BLACK SN770** (sarasti's
  `my.disks.mainDevice`): `root` (ephemeral), `nix`, `log`, `swap`, `games`,
  `root-blank`. This disk is disposable: reinstalling it costs only re-download
  time.
- `/dev/mapper/cryptpersist` — on the **256 GB WD SN730** (sarasti's
  `my.disks.persistDevice`): its own btrfs pool with just `persist` and `home`.
  This is the disk that matters.
- One LUKS passphrase covers both containers (the same
  `--disk-encryption-keys` file is disko's `passwordFile` for both), and both
  are unlocked from the initrd.
- Consequence: reinstalling the *system* disk leaves `/home` and `/persist`
  alone — the SSH host key, the sops age key derived from it, and the lanzaboote
  key bundle all survive, so there is no age-key rotation and no
  `secrets.yaml` re-encryption. See `docs/boot-modes.md` (migration section).

The `games` subvolume is created automatically by disko on a fresh install
(nixos-anywhere runs disko's create phase, which makes every declared
subvolume). On an *already-installed* host, adding it only regenerates the
mount via `nixos-rebuild switch`, so create it once manually (`btrfs
subvolume create` at the pool top level, `subvol=/`).

## Secrets & credentials — where they live

| secret | location | recovery |
|---|---|---|
| LUKS passphrase | KeePassXC entry in `~/sync/private/vkarasen.kdbx` (per host; paper copy of the kdbx master password offline) | typed at the prompt; the universal fallback |
| user password | sops `user-password` secret → `hashedPasswordFile` | sops decrypts at boot (host age key) |
| Secure Boot keys (PK/KEK/db) | `/persist/etc/secureboot/keys/` (on sarasti: disk 4) | **NOT in git** (db.key is a private signing key) |
| sops age key | derived from `/persist/etc/ssh/ssh_host_ed25519_key` (its private half is a kdbx attachment) | survives with the host keys |
| SSH authorized key | declarative in `modules/nixos/base.nix` | always present (key auth) |

The **LUKS passphrase is the root of all recovery**: it unlocks `cryptroot`
(and, on a two-disk host, `cryptpersist`), which together hold every other
persistent secret (`/persist`).

## Secure Boot (Lanzaboote)

**uefi only** (`my.boot.mode == "uefi"`); `legacy` hosts run GRUB with no
Secure Boot.

- Configured in `modules/nixos/boot.nix`: `boot.lanzaboote.enable`, `pkiBundle =
  /persist/etc/secureboot`, `autoGenerateKeys` + `autoEnrollKeys`; systemd-boot
  is disabled (Lanzaboote replaces its install with signed UKIs).
- Keys are auto-generated once and enrolled in the firmware (PK/KEK/db plus
  Microsoft keys for Option ROMs). `bootctl status` shows
  `Secure Boot: enabled (user)`.

### When do the boot keys change?

They **do not** change on kernel updates, NixOS updates, or day-to-day use — the
kernel/initrd are signed with the *same* `db` key, and PCR 7 only reflects the
Secure Boot *key set + configuration*, not the booted software. The keys change
only if you **regenerate them** (manually, or by deleting
`/persist/etc/secureboot/keys/` and letting `autoGenerateKeys` re-run), or if you
"Reset to Setup Mode" / "Restore Factory Keys" in the BIOS (which wipes the
enrolled keys and requires re-enrollment).

One exception changes PCR 7 *without* any key change: since systemd 261,
`systemd-pcrosseparator.service` measures a constant `os-separator` string into
PCRs 0-7/9/12-14 during early userspace (the initrd). It's a userspace
measurement layered on top of the Secure Boot measurement, so after a systemd
≥261 update the PCR 7 value shifts once even though the key set is untouched —
a passphrase prompt right after that update is expected, not a security event.
(It does not appear in the firmware event log; systemd logs userspace
measurements to `/run/log/systemd/tpm2-measure.log`.)

## Desktop (Hyprland)

- Stack: **Hyprland** (scrolling tiling by default, dwindle on workspace 1) +
  **ghostty** (terminal) + **waybar** (bar) + **mako** (notifications) +
  **fuzzel** (launcher) + **vesktop** (Discord client, bundled with Vencord); wl-clipboard for clipboard, **Flameshot** for
  interactive region capture, and `grim` only inside the fullscreen/window
  `screenshot` helper. `modules/nixos/desktop.nix` enables the
  compositor (and the screen-share portal); `modules/home/desktop.nix` holds the
  apps + their config.
- Launch: log in on **tty1** → `~/.bash_profile` runs `exec start-hyprland` (no
  display manager). Quitting Hyprland returns to the login prompt.
- Layout: `general.layout = "scrolling"` (niri-like columns) is the default,
  with `workspace_rule` pinning **workspace 1 to dwindle** so every other
  workspace scrolls.
- Keybinds: `SUPER+Return` ghostty, `SUPER+Space` fuzzel, `SUPER+Q` close,
  `SUPER+V` float, `SUPER+F` fullscreen, `SUPER+M` exit, `SUPER+ESC` lock,
  `SUPER+1..5` workspaces (`SUPER+SHIFT+1..5` sends the window); `SUPER+CTRL+Left/Right` steps to the previous/next workspace; `SUPER+A` toggles to the last workspace. Layout-aware
  vim focus `SUPER+h/j/k/l` and move `SUPER+SHIFT+h/j/k/l` (column verbs while
  scrolling, `focus`/`window.move` on dwindle); `SUPER+CTRL+h/j/k/l` swaps
  windows; scrolling-only `SUPER+p` promote, `SUPER+minus`/`SUPER+equal`
  colresize, `SUPER+SHIFT+f` fit expand, `SUPER+CTRL+SHIFT+h/l` move column;
  `SUPER+o` fuzzy window picker; `SUPER+ALT+h/l` focus monitor (`+SHIFT` moves
  the workspace there); PrtSc region capture (Flameshot), `SHIFT+PrtSc`
  fullscreen and `ALT+PrtSc` window (the `screenshot` helper).
- Gestures: a 3-finger horizontal swipe switches workspace (native `hl.gesture`), and bumping the outermost screen edge switches workspace (the `hypr-edge-switcher` systemd user service).
- The Hyprland config is **Lua** (`hl.*`: `hl.config`, `hl.bind`, `hl.dsp.*`) —
  the stateVersion 26.05 default `configType`; nothing pins `hyprlang`. The
  generated file is `hyprland.lua`, not `hyprland.conf`.
- catppuccin's **Hyprland** theming is disabled (`catppuccin.hyprland.enable =
  false` in `modules/home/external.nix`) because **Stylix owns the DE surface**
  and the two would fight over the same config files; the border colours are
  explicit rgba values in the Hyprland config instead.
- Gotcha: ghostty and ncurses both ship `share/terminfo/g/ghostty`, which
  collides in the shared home-manager buildEnv; the desktop aspect overrides
  ghostty to drop the duplicate entry and keep `x/xterm-ghostty`.

## TPM2 unlock

- LUKS **key slot 2** is bound to **PCR 7** (Secure Boot state).
- The TPM releases the key only to a boot chain in the same Secure Boot state —
  a live USB or a changed key set cannot unseal the disk.
- **This is a UEFI/Secure Boot property, not a property of having a TPM.**
  sarasti (legacy/CSM today) has a working AMD fTPM, but with Secure Boot off and
  an unencrypted `/boot` PCR 7 is *constant*: there the token only guards against
  the drives leaving the machine. The binding above starts to hold on sarasti
  only after the uefi flip (M4) — and both containers' tokens are re-enrolled
  then (see `docs/boot-modes.md`).
- The **passphrase** (key slot 0) is always the fallback. It is never removed.

## Recovery procedures

| symptom | fix |
|---|---|
| LUKS prompt appears (TPM refused) | type the passphrase; if it keeps happening, re-enroll (below) |
| TPM unlock broke after a Secure Boot key change | re-enroll the TPM (below) |
| TPM unlock broke right after a systemd ≥261 update (no key change) | expected once — the new `systemd-pcrosseparator.service` measured `os-separator` into PCR 7; re-enroll the TPM (below) |
| Secure Boot keys lost / firmware reset | regenerate keys (or re-enroll) + re-enroll the TPM |
| Boot entry broken / bad generation | pick an older generation in the systemd-boot (uefi) / GRUB (legacy) menu |
| SSH / networking down | see `docs/nixos-debugging.md` |

### Re-enroll the TPM (PCR 7)

```sh
printf '%s' '<LUKS passphrase>' > /tmp/k
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
  --unlock-key-file=/tmp/k <mainDevice>p2
rm /tmp/k
```

### Re-enroll Secure Boot keys (if the key set ever changes)

1. Boot with Secure Boot in **Setup Mode** (ThinkPad: Security → Secure Boot →
   enable → "Reset to Setup Mode").
2. Boot NixOS; the `autoEnrollKeys` flow (or `sudo sbctl enroll-keys --microsoft`)
   stages the keys and systemd-boot enrolls them on the next boot.
3. Reboot, confirm `bootctl status` shows `enabled (user)`, then re-run the TPM
   cryptenroll command above (PCR 7 changed).
