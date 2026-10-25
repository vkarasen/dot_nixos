# Boot modes (per host)

A host chooses **uefi** or **legacy** BIOS/CSM boot with `my.boot.mode`. The
shared system aspects branch on it: `modules/nixos/boot.nix` (bootloader) and
`modules/nixos/disks.nix` (partition layout). Everything above the bootloader —
LUKS `cryptroot`, the btrfs pool, the subvolumes — is **identical in both
modes**.

## Two boot modes

| | `my.boot.mode = "uefi"` | `my.boot.mode = "legacy"` |
|---|---|---|
| bootloader | **lanzaboote** (Secure Boot) + **systemd-boot** | **GRUB** (`efiSupport = false`, `useOSProber = true`) |
| boot artifacts | signed **UKI** (kernel + initrd + cmdline) on the ESP | GRUB `core.img` in a **bios_grub** partition; kernel + initrd read from `/boot` |
| disk partition | 1 GiB **ESP** (`EF00`, vfat, mountpoint `/boot`) | 1 MiB **EF02 bios_grub** (no filesystem) + 1 GiB unencrypted **ext4** `/boot` |
| Secure Boot | yes — keys auto-generated/enrolled (`pkiBundle = /persist/etc/secureboot`) | no — GRUB on a BIOS/CSM host |
| Windows chainload | via systemd-boot / os-prober if present | via GRUB **os-prober** |
| `boot.loader.grub.device` | n/a | not declared — disko auto-sets `grub.devices` from `my.disks.mainDevice` because the GPT has an EF02 partition |

Shared by both modes: **LUKS2 `cryptroot`** (argon2id, `allowDiscards`) holding
one **btrfs** pool with the subvolumes `/root` (ephemeral), `/home`, `/nix`,
`/persist`, `/log`, `/swap`, `/games`, plus the read-only `root-blank` snapshot.

Why `/boot` (or the ESP) is unencrypted **by design**: the bootloader must be
able to read kernel + initrd without unlocking LUKS2 — only the **initrd**
unlocks `cryptroot`. Encrypting `/boot` would move the passphrase prompt into
the bootloader and defeat the Secure Boot / TPM2 story.

## Per-host options

All three live in `modules/options.nix` (generic class) and are **set in the
host file** — `modules/hosts/<name>.nix`, inside that host's
`flake.modules.nixos.<name>` attrset. Never in `modules/nixos/`.

| option | type | meaning |
|---|---|---|
| `my.boot.mode` | `enum ["uefi" "legacy"]`, default `"uefi"` | Which boot chain + partition layout the host installs for. Drives `boot.nix` and `disks.nix`. |
| `my.boot.resumeOffset` | `nullOr int`, default `null` | Physical offset of the btrfs swapfile → `boot.kernelParams`' `resume_offset=` for hibernation. `null` = hibernation not wired yet on this host. Compute after install: `btrfs inspect-internal map-swapfile -r /swap/swapfile`. |
| `my.disks.mainDevice` | `str`, **no default** | Whole system disk for disko (and, in legacy mode, the GRUB target). Use a stable `/dev/disk/by-id/...` path. No default on purpose: a host that imports the disks aspect must name its disk, so a default can never silently wipe the wrong device. Verify at install time with `ls -l /dev/disk/by-id/`. |

## Current hosts

| host | mode | `my.disks.mainDevice` | `my.boot.resumeOffset` |
|---|---|---|---|
| `troy` (ThinkPad T14s Gen 1) | `uefi` | `/dev/nvme0n1` | `533760` |
| `sarasti` (MSI B550-A PRO desktop) | `legacy` — dual-boots Windows | `/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_…` (2 TB SN770, **not** the 256 GB WD SN730) | `null` — set after first boot |

`sarasti` runs legacy BIOS/CSM because the existing Windows install on its own
MBR disk is legacy; GRUB chainloads it via os-prober and the Windows disk is
left untouched. See `modules/hosts/sarasti.nix`.

## Migrating legacy → uefi (sarasti, once Windows is retired)

This is a **REINSTALL, not a `nixos-rebuild`** — switching `my.boot.mode` to
`"uefi"` changes the disko layout (an ESP replaces the bios_grub partition +
unencrypted `/boot`), so disk 3 is re-partitioned and its contents are gone:

1. **Update the BIOS first**: A.30 (2020) → current via M-Flash, *before*
flipping firmware to UEFI. A 2020 firmware cannot be trusted with a modern
UEFI/Secure Boot chain.
2. Set `my.boot.mode = "uefi"` in `modules/hosts/sarasti.nix` (drop
`useOSProber` relevance; lanzaboote takes over).
3. Re-run **disko** for that host (nixos-anywhere / a fresh install): the
legacy layout has no ESP partition, so switching modes requires the new GPT
(1 GiB vfat ESP at `/boot`). This **wipes the disk** — plan a reinstall, or
copy data off first. Back up `/home` and `/persist`.
4. **No TPM to migrate**: sarasti has no TPM (fTPM disabled), so there is
nothing to re-enroll and nothing to carry over. Secure Boot / lanzaboote do
**not** need a TPM. Enable fTPM later only if TPM-backed LUKS unlock is
wanted.
5. Enable **UEFI** boot (and Secure Boot) in firmware for the SN770.
6. First boot: lanzaboote's `autoGenerateKeys` / `autoEnrollKeys` (already
configured in `modules/nixos/boot.nix`, `includeMicrosoftKeys = true`,
`autoReboot = false`) generate keys into `/persist/etc/secureboot` and enroll
them on the boot where the firmware is in **Setup Mode**.
7. `/persist` is wiped by the reinstall, so SSH host key, machine-id, and
lanzaboote keys are all **freshly generated on the first uefi boot**. The
sops age key is derived from `/persist/etc/ssh/ssh_host_ed25519_key`, so
`secrets.yaml` must be **re-encrypted to the new age key** after that boot.
8. Boot menu difference: after migration generations are picked in the
**systemd-boot** menu (signed UKIs, `configurationLimit = 10`) instead of the
GRUB menu. GRUB's os-prober Windows chainload disappears with Windows.

## See also

- `docs/nixos-install.md` — install runbook, including the
  [sarasti (legacy BIOS desktop)](nixos-install.md) section.
- `docs/nixos-architecture.md` — boot chain, storage layout, TPM2 unlock and
  Secure Boot recovery for the uefi path.
- `modules/nixos/boot.nix`, `modules/nixos/disks.nix` — the two branching
  aspects.
