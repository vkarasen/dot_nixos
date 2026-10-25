# Boot modes (per host)

A host chooses **uefi** or **legacy** BIOS/CSM boot with `my.boot.mode`. The
shared system aspects branch on it: `modules/nixos/boot.nix` (bootloader) and
`modules/nixos/disks.nix` (partition layout). Everything above the bootloader —
LUKS `cryptroot`, the btrfs pool, the subvolumes — is **identical in both
modes** (where `/home` + `/persist` live is a *separate*, per-host axis — see
`my.disks.persistDevice` below).

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
one **btrfs** pool with the subvolumes `/root` (ephemeral), `/nix`, `/log`,
`/swap`, `/games`, plus the read-only `root-blank` snapshot. `/home` and
`/persist` are the two subvolumes whose *location* is host-dependent:

- **single-disk hosts** (`my.disks.persistDevice = null`, e.g. troy): `/home`
  and `/persist` are further subvolumes of the same `cryptroot` pool.
- **two-disk hosts** (`my.disks.persistDevice` set, e.g. sarasti): `/home` and
  `/persist` live on a **separate** LUKS2 `cryptpersist` + btrfs pool on a
  second NVMe. The system disk can then be reinstalled without touching user
  data or the secrets under `/persist`.

These two axes are independent: `my.boot.mode` decides the bootloader and the
*system disk's* partition layout; `my.disks.persistDevice` decides *where*
`/home` + `/persist` live. Both containers share one LUKS passphrase.

Why `/boot` (or the ESP) is unencrypted **by design**: the bootloader must be
able to read kernel + initrd without unlocking LUKS2 — only the **initrd**
unlocks `cryptroot` (and, where present, `cryptpersist`). Encrypting `/boot`
would move the passphrase prompt into the bootloader and defeat the Secure
Boot / TPM2 story.

## Per-host options

All of these live in `modules/options.nix` (generic class) and are **set in the
host file** — `modules/hosts/<name>.nix`, inside that host's
`flake.modules.nixos.<name>` attrset. Never in `modules/nixos/`.

| option | type | meaning |
|---|---|---|
| `my.boot.mode` | `enum ["uefi" "legacy"]`, default `"uefi"` | Which boot chain + partition layout the host installs for. Drives `boot.nix` and `disks.nix`. |
| `my.boot.resumeOffset` | `nullOr int`, default `null` | Physical offset of the btrfs swapfile → `boot.kernelParams`' `resume_offset=` for hibernation. `null` = hibernation not wired yet on this host. Compute after install: `btrfs inspect-internal map-swapfile -r /swap/swapfile`. |
| `my.disks.mainDevice` | `str`, **no default** | Whole system disk for disko (and, in legacy mode, the GRUB target). Use a stable `/dev/disk/by-id/...` path. No default on purpose: a host that imports the disks aspect must name its disk, so a default can never silently wipe the wrong device. Verify at install time with `ls -l /dev/disk/by-id/`. |
| `my.disks.persistDevice` | `nullOr str`, default `null` | Whole second disk holding `/persist` + `/home` as a separate LUKS2 `cryptpersist`. `null` = they stay subvolumes of `cryptroot` (single-disk hosts). Also a by-id path; disko formats it, so verify at install time too. |
| `my.disks.skipPersist` | `bool`, default `false` | `true` = keep `persistDevice` **out of disko** while still declaring its LUKS device + `/persist`/`/home` mounts. The only safe way to reinstall the system disk without formatting the persistent one (the legacy → uefi flip); set it **temporarily** and revert afterwards. |

## Current hosts

| host | mode | `my.disks.mainDevice` | `my.disks.persistDevice` | `my.boot.resumeOffset` |
|---|---|---|---|---|
| `troy` (ThinkPad T14s Gen 1) | `uefi` | `/dev/nvme0n1` | `null` — single disk, `/persist` + `/home` are cryptroot subvolumes | `533760` |
| `sarasti` (MSI B550-A PRO desktop) | `legacy` — dual-boots Windows | the **2 TB WD_BLACK SN770** by-id path, see `modules/hosts/sarasti.nix` | the **256 GB WD SN730** by-id path — separate `cryptpersist` disk holding `/persist` + `/home` | `null` — set after first boot |

`sarasti` runs legacy BIOS/CSM because the existing Windows install on its own
MBR disk is legacy; GRUB chainloads it via os-prober and the Windows disk is
left untouched. Its *second* NVMe (the SN730) is not a Windows disk any more —
it was one empty NTFS data volume (`G:`), and it is now the persistent disk
targeted by `my.disks.persistDevice`. See `modules/hosts/sarasti.nix`.

## Disk numbering (one definition, used everywhere)

The install runbook and this migration doc refer to disks by **number**. The
numbers are position-independent identities, anchored on `/dev/disk/by-id/`
paths — never on `nvme0n1`/`sda`, which reorder between boots and BIOS changes:

| # | model | size | role | by-id anchor |
|---|---|---|---|---|
| 0 | Crucial M4 (SATA SSD) | 128 GB | **Windows 10**, MBR-partitioned, **3 partitions** (`C:` = label `System` + recovery). Must never be touched. | `ata-<MODEL>_<SERIAL>` |
| 1 | Samsung (SATA SSD) | 250 GB | NTFS data volume `E:`, single partition | `ata-<MODEL>_<SERIAL>` |
| 2 | Crucial MX500 (SATA SSD) | 500 GB | NTFS data volume `F:`, single partition | `ata-<MODEL>_<SERIAL>` |
| 3 | WD_BLACK SN770 (NVMe) | 2 TB | **system disk** — `my.disks.mainDevice`; reformatted by every install/flip | `/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_E823_8FA6_BF53_0001_001B_444A_414D_7FB8` |
| 4 | WDC PC SN730 (NVMe) | 256 GB | **persist disk** — `my.disks.persistDevice`; `cryptpersist` holding `/persist` + `/home` | `/dev/disk/by-id/nvme-WDC_PC_SN730_SDBQNTY-256G-1001_001B_448B_4886_AE3B` |

Only disks 3 and 4 have their exact by-id string committed (in
`modules/hosts/sarasti.nix`); for 0–2 read the real one with
`ls -l /dev/disk/by-id/` and match on `MODEL` from
`lsblk -o NAME,SIZE,MODEL,PTTYPE,LABEL`. **Disks 0–2 are never written by this
config** — disks 0–2 appear in no `my.disks.*` option, and only 3 + 4 are in
`my.disks.mainDevice` / `my.disks.persistDevice`.

## Migrating legacy → uefi (sarasti, once Windows is retired)

This is a **REINSTALL, not a `nixos-rebuild`** — switching `my.boot.mode` to
`"uefi"` changes the disko layout (an ESP replaces the bios_grub partition +
unencrypted `/boot`). Throughout this section:

- **"disk 3" is the 2 TB WD_BLACK SN770** — the *system* disk named by
  `my.disks.mainDevice` as a `/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_…` path
  (the exact string lives in `modules/hosts/sarasti.nix`). The reinstall wipes
  and rebuilds **this disk only**: its root, `/nix`, `/var/log`, `/swap`, and
  `/games` are gone and recreated.
- **"disk 4" is the 256 GB WD SN730** — the *persistent* disk named by
  `my.disks.persistDevice`, carrying `cryptpersist` with `/persist` and
  `/home`. It is **not** part of the flip and its contents survive — but only
  if you take the step below that makes disko ignore it.

1. **Update the BIOS first**: A.30 (2020) → current via M-Flash, *before*
   flipping firmware to UEFI. A 2020 firmware cannot be trusted with a modern
   UEFI/Secure Boot chain. Concrete shape of the M-Flash step:
   - download the **current version** from the MSI **B550-A PRO** support page
     ("BIOS" → latest non-beta release) onto a **FAT32-formatted USB stick**,
     as the extracted `.bin`/`.exe` that page provides;
   - reboot → DEL → **M-Flash** → select the file from that USB and let it
     complete **without interruption**;
   - **brick risk**: cutting power or pulling the USB mid-flash can leave the
     board unbootable. Do this **before touching any data**, while the machine
     is still a working Windows box, and do not combine it with any other step.
2. **Back up what lives on disk 3** — the ephemeral `/`, `/nix`, `/var/log`,
   `/swap`, and `/games` are recreated from scratch. `/home` and `/persist` are
   on disk 4 and survive, but back them up anyway: they are one passphrase away
   from loss, and a botched flip should cost nothing.
3. Set `my.boot.mode = "uefi"` in `modules/hosts/sarasti.nix` (drop
   `useOSProber` relevance; lanzaboote takes over) and **enter firmware Setup
   Mode *before* the first post-install boot** — Security → Secure Boot →
   enable → "Reset to Setup Mode". lanzaboote is configured with
   `autoEnrollKeys = true` and `autoReboot = false`, so the enrollment boot
   requires the firmware to already be in Setup Mode; without it the keys never
   enroll and later boots fail verification. In the same firmware session, set
   the SN770 as the first **UEFI** boot device (not the legacy/CSM entry).
4. **Boot the installer in UEFI mode this time.** The live environment's mode is
   inherited by nixos-anywhere, so a UEFI config installed from a legacy-booted
   ISO fails only after the install (see the mode-match rule in
   `docs/nixos-install.md` §1). Verify in the live ISO:
   `[ -d /sys/firmware/efi ] && echo UEFI` must print `UEFI`.
5. **Reinstall with the persist disk held out of disko.** The plain command
   from the runbook (§8 step 3) **would wipe disk 4** — see the warning below.

   > **Why not the obvious alternatives** (checked against
   > `nixos-anywhere 1.13.0` / `disko 1.13.0`): **`--no-disko` does not
   > exist.** `--phases` (`kexec,disko,install,reboot`) can be shortened, but
   > the disko phase is what formats *and* mounts, so dropping it leaves `/mnt`
   > empty and the install fails. `--disko-mode format` cannot help either —
   > disko's `format` mode is idempotent by design (it skips existing
   > filesystems), so it would *also* skip rebuilding the new ESP on disk 3.
   > And disko itself has **no per-disk filter**: `--mode destroy,format,mount`
   > formats every disk the NixOS config declares. The only reliable way to
   > leave disk 4 alone is therefore to **stop declaring it to disko** — the
   > `my.disks.skipPersist` option (`modules/options.nix`), which omits it from
   > `disko.devices.disk` while still declaring `boot.initrd.luks.devices`
   > and the `/persist` + `/home` mountpoints (`modules/nixos/disks.nix`), so
   > the *existing* `cryptpersist` is opened and mounted unmodified.

   a. **Before anything else, record the disk-4 fingerprint** [SARASTI, from the
      running system]:
      ```bash
      cryptsetup luksUUID /dev/disk/by-partlabel/disk-persist-cryptpersist
      btrfs subvolume list /persist
      sudo btrfs filesystem show /dev/mapper/cryptpersist
      ```
      Save the output somewhere off-machine. The **LUKS UUID**, the
      **partlabel** `disk-persist-cryptpersist`, the btrfs UUID and the
      **subvolume list** are the four things the flip must leave untouched —
      compare them after step d.
   b. **Set `my.disks.skipPersist = true;`** in `modules/hosts/sarasti.nix`
      (next to the other `my.disks.*` lines), commit, and confirm disko can no
      longer see disk 4 before booting the installer:
      ```bash
      nix eval --json .#nixosConfigurations.sarasti.config.disko.devices.disk \
        --apply builtins.attrNames    # must print exactly: ["main"]
      ```
      If it still lists `persist`, the edit is uncommitted (git flake — see
      the pitfall in `AGENTS.md`) and disko **will** format disk 4.
   c. **Run the same install command as the runbook** (§8 step 3) — unchanged:
      ```bash
      nix run github:nix-community/nixos-anywhere -- \
        --flake '.#sarasti' \
        --disk-encryption-keys /tmp/secret.key /tmp/secret.key \
        --target-host root@<ip>
      ```
      The legacy layout has no ESP, so the new GPT (1 GiB vfat ESP at `/boot`,
      LUKS `cryptroot` now at **partition p2**) replaces it on disk 3. The key
      file still supplies the passphrase for both containers — but only
      `cryptroot` is *created*; `cryptpersist` is merely opened.
   d. **Verify the guard, then restore disko ownership.** After the first boot:
      ```bash
      cryptsetup luksUUID /dev/disk/by-partlabel/disk-persist-cryptpersist
      btrfs subvolume list /persist
      findmnt /persist /home     # both must be /dev/mapper/cryptpersist
      ```
      The UUID, partlabel and subvolume list must match step a **exactly**. If
      they do not, disk 4 was touched — stop, do not proceed to any further
      rebuild, and restore from the backup taken in step 2. Once verified, set
      `my.disks.skipPersist = false;` (or delete the line) and commit, so
      ordinary installs/repairs regain full disko ownership of disk 4.
6. **No TPM to migrate**: sarasti has no TPM (fTPM disabled), so there is
   nothing to re-enroll and nothing to carry over. Secure Boot / lanzaboote do
   **not** need a TPM. Enable fTPM later only if TPM-backed LUKS unlock is
   wanted.
7. First boot: lanzaboote's `autoGenerateKeys` / `autoEnrollKeys` (already
   configured in `modules/nixos/boot.nix`, `includeMicrosoftKeys = true`,
   `autoReboot = false`) generate and enroll the boot keys. The key bundle is
   `pkiBundle = /persist/etc/secureboot`, i.e. it lives on **disk 4** — it is
   written on this first uefi boot (nothing generated it in legacy mode, where
   lanzaboote is off) and, from then on, survives any later reinstall of
   disk 3.
8. **Nothing is re-keyed — no age-key rotation, no `secrets.yaml`
   re-encryption.** Because `/persist` and `/home` survive on disk 4, the SSH
   host key, machine-id, and the sops age key derived from
   `/persist/etc/ssh/ssh_host_ed25519_key` are all **unchanged**. The `&sarasti`
   anchor in `.sops.yaml` stays valid, and there is no `sops updatekeys` step.
   (Key rotation is the *fresh-install* story, where `/persist` is wiped — the
   legacy install of sarasti went through it, see `docs/nixos-install.md` §8
   step 6. Re-run that procedure only if you ever deliberately wipe disk 4.)
9. **Recompute `my.boot.resumeOffset`** after the reinstall — the `/swap`
   subvolume lives on disk 3 and is recreated, so the old offset is invalid:
   `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile`, then set it in
   `modules/hosts/sarasti.nix` and rebuild. A stale offset breaks hibernate
   resume silently (the kernel resumes from the wrong blocks).
10. Boot menu difference: after migration generations are picked in the
    **systemd-boot** menu (signed UKIs, `configurationLimit = 10`) instead of the
    GRUB menu. GRUB's os-prober Windows chainload disappears with Windows.

## See also

- `docs/nixos-install.md` — install runbook, including the
  [sarasti (legacy BIOS desktop)](nixos-install.md#8-sarasti-legacy-bios-desktop)
  section.
- `docs/nixos-architecture.md` — boot chain, storage layout, TPM2 unlock and
  Secure Boot recovery for the uefi path.
- `modules/nixos/boot.nix`, `modules/nixos/disks.nix` — the two branching
  aspects.
