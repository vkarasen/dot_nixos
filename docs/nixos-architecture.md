# NixOS host `troy` — architecture & recovery

The authoritative map of how this machine is built, where its secrets live, and
how to recover it when something breaks. Read alongside `docs/nixos-install.md`
(install runbook) and `docs/nixos-debugging.md` (live, no-network debugging).

## Boot chain (power-on → login)

1. UEFI firmware loads **systemd-boot**, signed by Lanzaboote (Secure Boot).
2. systemd-boot loads a signed **UKI** (kernel + initrd + cmdline) from the ESP.
3. The initrd (systemd) **TPM2-unlocks** the LUKS root bound to **PCR 7**
   (Secure Boot state). If the PCR state doesn't match, it falls back to the
   **LUKS passphrase** prompt.
4. The **rollback** service re-snapshots the ephemeral root from `root-blank`
   (skipped on a resume-from-hibernate boot).
5. Boot continues: dbus → NetworkManager → sshd → home-manager.

## Storage (btrfs inside LUKS)

- LUKS: `/dev/nvme0n1p2` → `/dev/mapper/cryptroot` (argon2id, `allowDiscards`).
- Subvolumes: `root` (ephemeral), `home` (persistent), `nix`, `persist`, `log`,
  `swap` (32G hibernation swapfile), `root-blank` (read-only pristine snapshot).
- Impermanence: only `root` is erased each boot; `/home`, `/nix`, `/persist`,
  `/var/log` survive. `/persist` holds the opt-in state (SSH host keys, sops,
  Secure Boot keys, machine-id, …).

## Secrets & credentials — where they live

| secret | location | recovery |
|---|---|---|
| LUKS passphrase | private vault note (`inbox/2026-09-04-nixos-migration-session.md`) | typed at the prompt; the universal fallback |
| user password | sops `user-password` secret → `hashedPasswordFile` | sops decrypts at boot (host age key) |
| Secure Boot keys (PK/KEK/db) | `/persist/etc/secureboot/keys/` | **NOT in git** (db.key is a private signing key) |
| sops age key | derived from `/persist/etc/ssh/ssh_host_ed25519_key` | survives with the host keys |
| SSH authorized key | declarative in `modules/nixos/base.nix` | always present (key auth) |

The **LUKS passphrase is the root of all recovery**: it unlocks the disk, which
holds every other persistent secret (`/persist`).

## Secure Boot (Lanzaboote)

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

- Stack: **Hyprland** (dwindle tiling) + **ghostty** (terminal) + **waybar**
  (bar) + **mako** (notifications) + **fuzzel** (launcher); wl-clipboard,
  grim/slurp for clipboard/screenshots. `modules/nixos/desktop.nix` enables the
  compositor (and the screen-share portal); `modules/home/desktop.nix` holds the
  apps + their config.
- Launch: log in on **tty1** → `~/.bash_profile` runs `exec start-hyprland` (no
  display manager). Quitting Hyprland returns to the login prompt.
- Keybinds: `SUPER+Return` ghostty, `SUPER+Space` fuzzel, `SUPER+Q` close,
  `SUPER+V` float, `SUPER+F` fullscreen, `SUPER+M` exit, `SUPER+1..5` workspaces.
- `configType = "hyprlang"` is pinned — stateVersion 26.05 would default to the
  newer Lua configType, and catppuccin's Lua-only hyprland theming is disabled
  in favour of explicit rgba colours in the hyprland.conf.
- Gotcha: ghostty and ncurses both ship `share/terminfo/g/ghostty`, which
  collides in the shared home-manager buildEnv; the desktop aspect overrides
  ghostty to drop the duplicate entry and keep `x/xterm-ghostty`.

## TPM2 unlock

- LUKS **key slot 2** is bound to **PCR 7** (Secure Boot state).
- The TPM releases the key only to a boot chain in the same Secure Boot state —
  a live USB or a changed key set cannot unseal the disk.
- The **passphrase** (key slot 0) is always the fallback. It is never removed.

## Recovery procedures

| symptom | fix |
|---|---|
| LUKS prompt appears (TPM refused) | type the passphrase; if it keeps happening, re-enroll (below) |
| TPM unlock broke after a Secure Boot key change | re-enroll the TPM (below) |
| TPM unlock broke right after a systemd ≥261 update (no key change) | expected once — the new `systemd-pcrosseparator.service` measured `os-separator` into PCR 7; re-enroll the TPM (below) |
| Secure Boot keys lost / firmware reset | regenerate keys (or re-enroll) + re-enroll the TPM |
| Boot entry broken / bad generation | pick an older generation in the systemd-boot menu |
| SSH / networking down | see `docs/nixos-debugging.md` |

### Re-enroll the TPM (PCR 7)

```sh
printf '%s' '<LUKS passphrase>' > /tmp/k
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
  --unlock-key-file=/tmp/k /dev/nvme0n1p2
rm /tmp/k
```

### Re-enroll Secure Boot keys (if the key set ever changes)

1. Boot with Secure Boot in **Setup Mode** (ThinkPad: Security → Secure Boot →
   enable → "Reset to Setup Mode").
2. Boot NixOS; the `autoEnrollKeys` flow (or `sudo sbctl enroll-keys --microsoft`)
   stages the keys and systemd-boot enrolls them on the next boot.
3. Reboot, confirm `bootctl status` shows `enabled (user)`, then re-run the TPM
   cryptenroll command above (PCR 7 changed).
