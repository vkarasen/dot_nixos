# NixOS install runbook — host `troy` (ThinkPad T14s Gen 1)

Companion to `nixosConfigurations.troy`. The main flow below is **troy** (UEFI);
the second host, `sarasti` — a legacy BIOS/CSM desktop that dual-boots Windows —
is covered by its own section at the end ([§8](#8-sarasti-legacy-bios-desktop))
and by `docs/boot-modes.md`. Secrets (LUKS passphrase, user password) live in
the private Obsidian vault note
`inbox/2026-09-04-nixos-migration-session.md` — this doc references them, never
embeds them.

## 0. Before you start

- The **graphical** NixOS installer ISO (GNOME or Plasma) + a USB stick —
  **not** the minimal ISO (it has no `passwd`/`sshd`). Use a **recent** stable
  NixOS graphical ISO (`nixos-<current-release>-x86_64-linux.iso` from the
  download page). The exact version barely matters: the live environment only
  has to *boot* and run `sshd` — the system is built and installed from this
  flake (and offloaded to the remote builder), not from the ISO.
- A USB-C ethernet dongle (or `wpa_supplicant` on the live ISO for wifi).
- Laptop and workstation on the same reachable network.
- The `nixos-troy` branch pushed (or merged to `main`) so `.#troy` resolves.
  (sarasti: `.#sarasti` on `main`.)

## 1. Boot the installer

1. Flash the ISO:
   `dd if=<the-downloaded-graphical-installer>.iso of=/dev/sdX bs=4M status=progress oflag=sync`
2. BIOS: **disable Secure Boot**, and **match the live-ISO boot mode to the
   host's `my.boot.mode`** — troy is UEFI; sarasti is legacy BIOS/CSM (see
   `docs/boot-modes.md`). Booting the ISO in the wrong mode produces a
   mismatched NixOS — nixos-anywhere inherits the live environment's mode.
   On sarasti's MSI B550-A PRO, legacy/CSM is not always exposed by the F11
   menu — if the USB entry boots UEFI (or does not appear), fix the firmware
   first: **Settings → Advanced → Windows OS Configuration → enable CSM**, set
   **Storage Boot Option Control = Legacy**, and disable **Windows 10 WHQL
   Support** if the option is present. Reboot, F11, boot the USB again, and
   re-run the `LEGACY` check from §8 step 1.
3. Boot from USB (`F12` at the ThinkPad logo; sarasti: `F11` / the MSI boot
   menu key).

## 2. Bring up the live environment (on the laptop)

> Why graphical and not minimal: the minimal ISO ships no `passwd`, no `sshd`,
> and no easy networking — it can't be SSH'd into without `nix-shell`
> gymnastics. The graphical ISO has all of that plus NetworkManager
> auto-connecting the dongle.

1. You land in a desktop. Open a terminal and become root: `sudo su -`
2. Set a throwaway password so nixos-anywhere can SSH in: `passwd`
3. Start sshd: `systemctl start sshd`
4. Get the IP: `ip addr` (NetworkManager should have the dongle up already).
5. Note the IP (`192.168.x.y`).

## 3. Deploy from the driving machine (troy or your workstation)

1. Put the LUKS passphrase in a temp file:
   `printf '%s' '<LUKS-passphrase-from-vault>' > /tmp/secret.key`
2. From the worktree, run:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake '.#troy' \
     --disk-encryption-keys /tmp/secret.key /tmp/secret.key \
     --target-host root@<ip>
   ```
   - `--disk-encryption-keys <remote> <local>`: uploads the key to the target for
     disko's `passwordFile = /tmp/secret.key`. Same path twice — one pair per
     LUKS device (we have one).
   - `github:nix-community/nixos-anywhere` is **unpinned** (no `?rev=`), so an
     install today runs whatever HEAD is: pin a rev in the command, or expect
     behaviour to drift between runs.
3. nixos-anywhere kexecs into its own environment, runs disko (partition + LUKS
   + btrfs), installs the system, and reboots the laptop.
4. Remove the key file when done (on troy): `rm /tmp/secret.key`

## 4. First boot (on the laptop)

1. LUKS prompt → type the passphrase.
2. Boot lands at a TTY (no desktop yet).
3. From the driving machine (troy or your workstation): `ssh vkarasen@<ip>`
   — key auth works because the **public** key is already authorized
   declaratively by `users.users.vkarasen.openssh.authorizedKeys.keys` in
   `modules/nixos/base.nix`; nothing needs copying for login.
4. Copy your SSH **private** key over — needed only for git-over-SSH, the
   zqnr.de build host, and the `gentian` host (`/home` is persistent, so this
   survives). Do **not** create it with `ssh-keygen`: copy the existing,
   passphrase-less key (an agent-generated key would not be authorized
   anywhere):
   ```bash
   # on the driving machine
   ssh vkarasen@<ip> 'install -d -m700 ~/.ssh'
   scp ~/.ssh/id_ed25519 vkarasen@<ip>:~/.ssh/id_ed25519
   ssh vkarasen@<ip> 'chmod 600 ~/.ssh/id_ed25519'
   ```
   (Later this should be sops-provisioned rather than hand-copied.)

## 5. Capture the hardware config (post-boot)

disko already declares filesystems/LUKS/swap, so don't import a full
`nixos-generate-config` output (it would duplicate those and conflict). On the
laptop after first boot, capture just the hardware bits:

```bash
sudo nixos-generate-config --no-filesystems --show-hardware-config
```

and fold the relevant lines (kernel modules, cpu governor, firmware) into
`modules/hosts/troy.nix` / `modules/nixos/boot.nix`, then rebuild — either from
the driving machine (troy or your workstation):

```bash
nixos-rebuild switch --flake '.#troy' --target-host vkarasen@<ip> --use-remote-sudo
```

or on the laptop after cloning the repo and checking out the right branch:

```bash
nh os switch .#troy
```

## 6. Post-boot graduation (in order)

1. **TPM unlock** — removes the LUKS prompt (substitute the **LUKS partition on
   the device named by `my.disks.mainDevice`** for this host):
   ```bash
   # uefi layout (troy): ESP p1, LUKS cryptroot p2
   sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2
   # legacy layout (a uefi-flipped sarasti): bios_grub p1, /boot p2, cryptroot p3
   sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-id/<mainDevice>-part3
   ```
   Note the two gotchas: on the **legacy** layout `cryptroot` is **partition 3**
   (after BIOS-BOOT `p1` and boot `p2`), not `p2`; and by-id device paths use a
   **`-partN`** suffix (`…-part3`), never `pN`. On legacy sarasti there is also
   no TPM — skip this step there entirely.
2. **sops host key** — the host keys live under `/persist/etc/ssh` (NOT
   `/etc/ssh`, which only holds symlinks to the store). The ed25519 host key is
   **auto-generated by sshd on first boot** — it is declared as
   `services.openssh.hostKeys` in `modules/nixos/base.nix` (pointed at
   `/persist` for impermanence) and does **not** exist on the installer or in
   the nixos-anywhere phase. So this step starts *after* §4's first boot, once
   §5's rebuild is done:
   a. **Derive** the host's age pubkey, on the new host:
      ```bash
      ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub   # prints age1… pubkey
      ```
   b. **Enroll it in `.sops.yaml`** (edit on the driving machine — troy or your
      workstation — in this worktree).
      That file has a `keys:` anchor list **and two** `creation_rules`
      (`modules/home/sops/secrets/*` and `modules/home/pi/skills-private/*.md`),
      each enumerating recipients in its own `key_groups`. The new pubkey must
      be added as an anchor **and** referenced in **both** rules — enrolling it
      in only one leaves the other path family undecryptable on that host:
      ```yaml
      keys:
        - &user_key age1f948…   # personal key
        - &troy age1rvvn…       # troy host key
        - &sarasti age1…        # ← new host: add its own anchor
      creation_rules:
        - path_regex: modules/home/sops/secrets/[^/]+\.(yaml|json|env|ini)$
          key_groups:
            - age: [*user_key, *troy, *sarasti]   # ← reference it here
        - path_regex: modules/home/pi/skills-private/[^/]+\.md$
          key_groups:
            - age: [*user_key, *troy, *sarasti]   # ← and here
      ```
   c. **Re-encrypt from a machine that already holds an enrolled recipient's
      age private key** — `sops updatekeys` must decrypt the file's data key,
      which the *new* host cannot do yet (this is the whole point of the step).
      Run it on the driving machine (troy or your workstation; personal key at
      `~/.config/sops/age/keys.txt`)
      or on **troy** (`/persist/etc/ssh/ssh_host_ed25519_key`), never on the new
      host. `sops` may not be on the driver's `PATH` — prefix it with
      `nix run nixpkgs#sops --` if `command -v sops` comes back empty:
      ```bash
      nix run nixpkgs#sops -- updatekeys modules/home/sops/secrets/secrets.yaml
      ```
      Any encrypted `*.md` under `modules/home/pi/skills-private/` is a separate
      file and needs its own `sops updatekeys` — same recipient list, but
      `updatekeys` is per-file (none are committed right now; apply this when
      the first private skill lands).
   d. **Verify the SYSTEM secret before touching the user key** — this proves
      step b/c landed, and it is the only check that does not depend on the
      home-manager age key:
      ```bash
      # system-level secret via the HOST key (sops.age.sshKeyPaths in
      # modules/nixos/sops.nix — no repo and no user key needed):
      sudo test -s /run/secrets/user-password && echo system-ok
      ```
      If this fails, stop here: step b's anchor was not referenced by the
      target's `path_regex` rule, or step c ran before the anchor edit was
      saved. `systemctl status sops-install-secrets` shows which recipient
      failed.
   e. **Write the age *private* key for the home-manager sops module** — a
      DIFFERENT key from the system one: the NixOS sops module derives its own
      from the **host** key (`/persist/etc/ssh/ssh_host_ed25519_key`, via
      `age.sshKeyPaths`), while home-manager reads
      `~/.config/sops/age/keys.txt`, which must be the **user** key — the one
      derived from `~/.ssh/id_ed25519` (that is `&user_key` in `.sops.yaml`).
      On the host:
      ```bash
      sudo ssh-to-age -private-key -i ~/.ssh/id_ed25519 > /tmp/keys.txt
      mkdir -p ~/.config/sops/age
      install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && sudo rm /tmp/keys.txt
      ```
   f. **Verify the home-manager secrets** (do not trust a green `updatekeys`):
      ```bash
      cd <repo> && sops decrypt modules/home/sops/secrets/secrets.yaml > /dev/null \
        && echo home-ok
      ```
      If this fails but step d printed `system-ok`, the file in
      `~/.config/sops/age/keys.txt` is not the user key (someone derived it from
      the host key).
3. **hibernate** — `resume_offset` is **per-host** via `my.boot.resumeOffset`
   (`boot.kernelParams`, applied only when non-null): troy = `533760`; for
   `sarasti` it stays `null` until, after first boot, you compute
   `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile` and set
   `my.boot.resumeOffset` in `modules/hosts/sarasti.nix`. If the swapfile is
   ever recreated (e.g. size change), recompute and update the host value.
4. **Secure Boot** (lanzaboote) — **only when `my.boot.mode == "uefi"`**.
   Configured (`autoGenerateKeys` + `autoEnrollKeys`); keys auto-generate on
   first boot and systemd-boot enrolls them. The one manual step is entering
   BIOS **Setup Mode** (Security → Secure Boot → enable → "Reset to Setup
   Mode") before the enrollment boot — see `docs/nixos-architecture.md`. On a
   `legacy` host there is no Secure Boot: GRUB + bios_grub + unencrypted
   `/boot` instead (skip this step entirely).
5. **desktop.nix** — Hyprland + terminal + Firefox.

## 7. Remote builder (zqnr.de)

Wired in `modules/nixos/remote-builder.nix`. Troy delegates builds over SSH using
`~/.ssh/id_ed25519` (verified passphrase-less). Verify delegation:

```bash
nix build .#nixosConfigurations.troy.config.system.build.toplevel --print-build-logs --rebuild
# look for "building ... on 'ssh://zqnr.de'"
```

Notes: `maxJobs` (8 cores) and `supportedFeatures` (`nixos-test benchmark
big-parallel kvm`) were confirmed directly against gentian. The key file must
remain at `~/.ssh/id_ed25519` (it lives in persistent `/home`).

## 8. sarasti (legacy BIOS desktop)

MSI B550-A PRO / Ryzen 5 3600 / RX 6750 XT, dual-booting an existing Windows 10
install. Full model in `docs/boot-modes.md` and `modules/hosts/sarasti.nix`.

This section is a **self-contained runbook** — you do not need §0–§7 to install
sarasti. Every step is tagged with where it runs:

- **[DRIVER]** — the driving machine (troy or your workstation): holds this
  repo and drives the install over SSH.
- **[SARASTI]** — the desktop being installed (live ISO, then the new system).
- **[TROY]** — troy specifically, in this repo's worktree.

> **Read this once before starting:** sarasti has **no TPM** (fTPM disabled), so
the LUKS passphrase is its **only** boot unlock path. The passphrase used at
step 0 **must** be recorded in the private vault note
(`inbox/2026-09-04-nixos-migration-session.md`); there is no recovery path if
it is lost, because nothing else can unlock `cryptroot` **or** `cryptpersist`
— and losing `cryptpersist` loses `/home` and `/persist` (every secret,
including the sops host key). One passphrase, both containers — and **two
copies**: the vault note *and* a second, independently reachable offline copy
(password manager entry, printed paper in a drawer — anywhere that does not
depend on the machine being installed). A vault note that is only readable
from the machine you are about to wipe is not a copy.

### Step 0 — prepare on troy [TROY]

1. Get the repo current and **pre-build the config before touching the USB**, so
   a Nix error surfaces here and not 20 minutes into an install:
   ```bash
   git checkout main && git pull
   nix build .#nixosConfigurations.sarasti.config.system.build.toplevel --no-link
   ```
   This only *evaluates and builds* — no disk is touched.
2. **LUKS passphrase** (per-host — do **not** reuse troy's). Write it to the
   temporary key file nixos-anywhere uploads, and record it in the private
   vault note at the same time — **and** in a second, independently reachable
   copy (offline: password-manager entry or paper), not only the vault note:
   ```bash
   printf '%s' '<sarasti-LUKS-passphrase-from-vault>' > /tmp/secret.key
   ```
   Two copies matter because the vault note is only reachable from a machine
   that is already online; if `/tmp/secret.key` is deleted and the only copy
   lives on the box whose disks you just encrypted, a single mistyped
   character becomes unrecoverable disks.
3. **[SARASTI, in Windows — before any install work starts]** Turn hibernation
   and fast startup off on the Windows side:
   ```
   powercfg /h off
   ```
   (Admin `cmd`/PowerShell.) Fast startup is part of hibernation, so this also
   disables it — confirm in *Control Panel → Power Options → Choose what the
   power buttons do* that "Turn on fast startup" is gone (uncheck + save if it
   is still listed). This has to happen **now**, while Windows still boots
   normally: step 8 mounts `C:` read-only and `E:`/`F:` read-write, and a
   **hibernated** NTFS volume carries a live journal — mounting one read-write
   corrupts it. This is the only Windows-side prerequisite in the runbook;
   after the install there is no Windows left to run it from.
4. **Flash the graphical NixOS ISO** (GNOME or Plasma — the minimal ISO has no
   `passwd`/`sshd`). Any **recent** stable graphical ISO works: the live
   environment only has to boot and run `sshd`, because the system itself is
   built from this flake (and, on troy, offloaded to the remote builder) — the
   ISO version does not become the installed system. Download the current one
   from the NixOS site, then:
   ```bash
   dd if=<the-downloaded-graphical-installer>.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
   (`/dev/sdX` = the USB stick — double-check with `lsblk` before running: `dd`
   does not ask.)

### Step 1 — firmware on sarasti [SARASTI]

1. Power on and hit **F11** for the MSI one-time boot menu.
2. Boot the USB in **CSM/legacy mode with Secure Boot disabled** —
   `my.boot.mode = "legacy"`, and nixos-anywhere inherits the live
   environment's mode.

   **If the USB entry is missing, or boots UEFI, fix CSM first** (BIOS setup,
   DEL at power-on): **Settings → Advanced → Windows OS Configuration → enable
   CSM**; set **Storage Boot Option Control = Legacy**; disable **Windows 10
   WHQL Support** if the option is present (some firmware revisions hide it).
   Save and exit, then F11 again. Without CSM enabled the installer only shows
   up as a UEFI entry.
3. **Verify it actually booted legacy — do this before anything else:**
   ```bash
   [ -d /sys/firmware/efi ] && echo UEFI || echo LEGACY
   ```
   It must print `LEGACY`. **If it prints `UEFI`, STOP and reboot in legacy
   mode.** A UEFI-booted installer deploying a legacy config looks completely
   normal until after the reboot, then fails to boot. This is the
   highest-consequence silent mistake in the whole runbook.

### Step 2 — live environment on sarasti [SARASTI]

1. Open a terminal and become root: `sudo su -`
2. Set a **throwaway** root password (only for nixos-anywhere's SSH login):
   `passwd`
3. Start sshd: `systemctl start sshd`
4. Get the IP: `ip addr` — note the `192.168.x.y` address.

### Step 3 — deploy from the driving machine [DRIVER] (+ one check [SARASTI])

**Before deploying, open the temporary sudo window.** `users.users.vkarasen`
has no usable password until sops enrollment (step 6), and the switch in
step 5 needs sudo. So, *before* running nixos-anywhere, add to
`modules/hosts/sarasti.nix` (inside the `flake.modules.nixos.sarasti`
attrset):

```nix
# TEMPORARY: removable once sops enrollment gives vkarasen a password.
# REMOVE after sops enrollment (step 6f of docs/nixos-install.md).
security.sudo.wheelNeedsPassword = false;
```

commit it, and leave it in place until step 6f. SSH key auth already works on
sarasti because it reuses troy's `~/.ssh/id_ed25519` (copied in step 4), so
this line is what lets the reused key — and an agent driving from troy via
`--use-remote-sudo` — run sudo without a password in the meantime.

1. **Verify BOTH target disks** [SARASTI]: `ls -l /dev/disk/by-id/` must show
   - `nvme-WD_BLACK_SN770_2TB_…` — the **2 TB system disk** (`my.disks.mainDevice`);
   - `nvme-WDC_PC_SN730_…` (256 GB) — the **second NVMe, the persistent disk**
     (`my.disks.persistDevice`). Its only content is an empty NTFS volume
     (the former `G:` — it is the persist disk now, not a data disk).

   Compare each exact string with `my.disks.mainDevice` / `my.disks.persistDevice`
   in `modules/hosts/sarasti.nix`. If either differs, edit the file and
   `git add` + commit — **the flake only sees the git tree**, so an uncommitted
   edit is silently ignored. Getting this wrong wipes the wrong disk (the
   Windows MBR boot disk is the one that must **not** appear here).
2. **Deploy** [DRIVER]:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake '.#sarasti' \
     --disk-encryption-keys /tmp/secret.key /tmp/secret.key \
     --target-host root@<ip>
   ```
   nixos-anywhere kexecs into its own environment, runs disko (partition + LUKS
   + btrfs), installs the system, and **reboots it itself**.

   > **What boots after that reboot.** The deploy ends with a reboot the driver
   > does not control, and F11 is a **one-time** boot menu — so that reboot
   > falls back to the firmware's default boot order, which is still
   > **Windows**. Either set the SN770 first in firmware **before** deploying
   > (Step 1.2 is the moment, or DEL → Settings → Boot), or stand ready to press
   > F11 at the reboot and pick the SN770. **If Windows starts, that is the old
   > boot order — not a failed install.** Nothing was written to the Windows
   > disk; power off and boot the SN770.

   - `github:nix-community/nixos-anywhere` is **unpinned** (no `?rev=`): pin a
     rev for a reproducible run, or accept that HEAD may behave differently.
   - **If this fails and you retry**: the kexec phase re-generates the target's
     SSH host key, so the second attempt will refuse to connect with a
     `HOST KEY VERIFICATION FAILED` error. Clear the stale entry first —
     `ssh-keygen -R <ip>` — then re-run exactly the same command.
   - **disko formats BOTH disks**: `<mainDevice>` (the 2 TB SN770) into
     `cryptroot`, and `<persistDevice>` (the 256 GB SN730) into a second LUKS2
     container, `cryptpersist`, holding `/persist` and `/home`. The separate
     persist disk is what lets a *later* reinstall of the system disk leave user
     data — and every secret under `/persist` — intact.
   - **One passphrase, both containers**: the single
     `--disk-encryption-keys /tmp/secret.key /tmp/secret.key` pair uploads one
     key file, and disko's `passwordFile` hands the *same* file to `cryptroot`
     and `cryptpersist`. There is no second passphrase to invent or record —
     the one in the vault unlocks both.
   - **The SN730's current contents are destroyed**: disk 4 is today one empty
     NTFS volume, `G:`, and it is reformatted at install. Anything on `G:` must
     be copied off first.
   - The **Windows MBR boot disk** is a different drive and stays untouched.
3. **Do NOT delete `/tmp/secret.key` yet** — it stays on troy until step 4 has
   proved the passphrase in it is the one that actually unlocks both
   containers. See step 4.7.

### Step 4 — first boot [SARASTI]

1. **Prompt sequence at the GRUB menu**: GRUB menu → **LUKS passphrase for
   `cryptroot`** → then `cryptpersist` (same passphrase). With
   `crypttabExtraOpts = ["password-cache=yes"]` (both LUKS blocks in
   `modules/nixos/disks.nix`) this should be **ONE prompt** — the cached key
   opens the second container. If you are prompted **twice**, that is not a
   fault: type the same passphrase again. (A *wrong* `cryptpersist` passphrase
   drops you to an emergency shell with `cryptpersist` not mounted — that is
   **not** data loss; reboot and try again, or from the emergency shell run
   `systemctl default` to continue booting without `/persist`.)
2. The erase-on-boot service prints
   `first boot: capturing pristine root as blank snapshot` — **expected, not an
   error**.
   The **`setupSecrets` activation script will FAIL with a NON-ZERO exit** on
   this first switch — that is expected too: sops is not yet enrolled (no host
   age key, no `&sarasti` recipient), and sops-nix refuses to start rather than
   activating a system with missing secrets. It is a **hard failure, not a
   warning** — do not proceed past it as if it were cosmetic. It also does not
   lock you out: the `users` activation runs *before* `setupSecrets`, so your
   SSH key (authorized declaratively in `modules/nixos/base.nix`) still works.
   The failure disappears after step 6d's rebuild.
3. **Confirm the two-disk layout before going further** — `/persist` and
   `/home` must both be mounted from `cryptpersist`, not from `cryptroot`:
   ```bash
   findmnt /home /persist
   ```
   Each line must show `/dev/mapper/cryptpersist` as the source (and
   `subvol=/home` / `subvol=/persist` in the options). A missing `/persist`
   means the passphrase prompt for `cryptpersist` failed — see item 1.
4. **Reboot once now, before spending time on enrollment.** One extra reboot
   exercises both things that only break on the *second* boot: the erase-on-boot
   rollback (root is wiped and re-snapshotted) and the persistence split
   (`/home` + `/persist` survive, `/` does not). Finding a problem here costs a
   reboot; finding it after enrollment costs a re-install. On this boot the
   blank-snapshot line does **not** reappear (only on the very first boot).
5. From the driving machine, `ssh-keygen -R <ip>` first (the host key changed
   with the reinstall), then `ssh vkarasen@<ip>`. Key auth works even though the
   password is locked — the **public** key is already authorized declaratively
   by `users.users.vkarasen.openssh.authorizedKeys.keys` in
   `modules/nixos/base.nix`, so nothing has to be copied just to log in.
6. Copy the **private** key over — only needed for git-over-SSH, the zqnr.de
   build host, and `gentian` (`/home` is persistent, so it survives reboots).
   Copy the existing passphrase-less key; do not `ssh-keygen` a new one, it
   would not be authorized anywhere:
   ```bash
   # on the driving machine
   ssh vkarasen@<ip> 'install -d -m700 ~/.ssh'
   scp ~/.ssh/id_ed25519 vkarasen@<ip>:~/.ssh/id_ed25519
   ssh vkarasen@<ip> 'chmod 600 ~/.ssh/id_ed25519'
   ```
7. **Only now delete the key file** — on troy, where step 0 wrote it:
   ```bash
   rm /tmp/secret.key
   ```
   Do this **only after** the unlock in item 1 actually succeeded with the
   *typed* vault passphrase (not a paste, and not a boot that skipped the
   prompt). That typed unlock is the verification that the recorded passphrase
   has no typo. Delete it earlier — as an earlier revision of this runbook did,
   at the end of step 3 — and a typo in the recorded passphrase becomes
   **unrecoverable disks**: both `cryptroot` and `cryptpersist` were created
   from that exact key file, and there is no TPM, no recovery key, and no other
   copy that could open them.

### Step 5 — hardware capture + rebuild [SARASTI or DRIVER]

`disko` already declares filesystems/LUKS/swap, so do **not** import a full
`nixos-generate-config` output (it would duplicate and conflict with them).

1. Capture only the hardware bits:
   ```bash
   sudo nixos-generate-config --no-filesystems --show-hardware-config
   ```
2. **Mount `C:` read-only before the rebuild** — os-prober can only find a
   Windows install that is mounted when `update-grub` runs, and the rebuild is
   what regenerates `/boot/grub/grub.cfg`:
   ```bash
   sudo mkdir -p /mnt/windows-c
   sudo mount -t ntfs3 -o ro,uid=1000,gid=1000 /dev/disk/by-label/System /mnt/windows-c
   ```
   Keep it mounted **through** the rebuild and through every later rebuild in
   step 6 (6d and 6f regenerate `grub.cfg` too). The mount does not survive a
   reboot, so remount before each rebuild — otherwise the menu silently loses
   its Windows entry. Read-only always: `C:` is a live Windows system volume.
3. Fold the relevant lines (kernel modules, cpu governor, firmware) into
   `modules/hosts/sarasti.nix`, commit, and rebuild — from the driving machine:
   ```bash
   nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --use-remote-sudo
   ```
   (`--use-remote-sudo` works only because of the temporary
   `wheelNeedsPassword = false` from step 3; it is removed in step 6f.)
   The **`setupSecrets` activation script still fails with a non-zero exit** on
   this rebuild too — sops is not enrolled until step 6. The switch completes
   anyway (users, sshd and sudo are already activated), so keep going; the
   failure goes away at step 6d.

### Step 6 — sops/age enrollment [SARASTI] + [DRIVER]

**Preflight — declared secrets exist.** Before enrolling, confirm the secrets the
host actually consumes are present in the (encrypted) file — an absent key
defeats the whole enrollment:

```bash
for k in user-password wifi-home-psk; do grep -q "^$k:" modules/home/sops/secrets/secrets.yaml || echo "MISSING $k"; done
```

No output = all declared secrets exist. (`user-password` feeds
`users.users.vkarasen.hashedPasswordFile`; `wifi-home-psk` is declared for
portable-config parity — sarasti is wired-only.)

a. **[SARASTI]** Derive the host's age pubkey — needs **no root**:
   ```bash
   ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub
   ```
   The host key is generated by sshd on first boot (`services.openssh.hostKeys`
   in `modules/nixos/base.nix`, pointed at `/persist` for impermanence), so it
   never exists in the installer or the nixos-anywhere phase.
b. **[DRIVER]** Add that pubkey to `.sops.yaml` **as an anchor and in both
   `key_groups`** — enrolling it in only one rule leaves the other path family
   undecryptable on sarasti:
   ```yaml
   keys:
     - &user_key age1f948…
     - &troy age1rvvn…
     - &sarasti age1…        # ← new anchor
   creation_rules:
     - path_regex: modules/home/sops/secrets/[^/]+\.(yaml|json|env|ini)$
       key_groups:
         - age: [*user_key, *troy, *sarasti]   # ← here
     - path_regex: modules/home/pi/skills-private/[^/]+\.md$
       key_groups:
         - age: [*user_key, *troy, *sarasti]   # ← and here
   ```
   Commit.
c. **[DRIVER]** Re-encrypt from a machine that already holds an enrolled
   recipient's age private key. `sops` reads that key from
   `SOPS_AGE_SSH_PRIVATE_KEY_FILE` or `~/.config/sops/age/keys.txt` — it does
   **not** auto-read `/persist/etc/ssh/…`, so point it at the right file
   explicitly if it is not the default:
   **`sops` may not be on the driver's `PATH`** — if `command -v sops` finds
   nothing, use `nix run nixpkgs#sops --`:
   ```bash
   nix run nixpkgs#sops -- updatekeys modules/home/sops/secrets/secrets.yaml
   ```
   Then `git add` + commit the re-encrypted `secrets.yaml` — a modified but
   **unstaged** file is **invisible** to the flake, so a forgotten `git add`
   looks exactly like a failed enrollment.
d. **[DRIVER or SARASTI]** Rebuild sarasti (from the driving machine:
   `nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --use-remote-sudo`).
   This is the rebuild that makes the **system** secrets decrypt: sops-nix now
   has an enrolled host key. Verify it *before* touching the user key — this
   check does not depend on `~/.config/sops/age/keys.txt`:
   ```bash
   sudo test -s /run/secrets/user-password && echo system-ok
   ```
   `system-ok` with no error means the **SYSTEM** sops key path works: sops-nix
   derived its key from the **HOST** key `/persist/etc/ssh/ssh_host_ed25519_key`
   (`sops.age.sshKeyPaths` in `modules/nixos/sops.nix`). If it fails, stop and
   re-check step b/c — do not go on to the home-manager key.
e. **[SARASTI]** Now the **home-manager** age key — a *different* key from the
   system one. Home-manager reads `~/.config/sops/age/keys.txt`, and what
   belongs there is the **USER** key derived from `~/.ssh/id_ed25519` (that is
   `&user_key` in `.sops.yaml`) — **not** the host key used by the system
   module:
   ```bash
   sudo ssh-to-age -private-key -i ~/.ssh/id_ed25519 > /tmp/keys.txt
   mkdir -p ~/.config/sops/age
   install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && sudo rm /tmp/keys.txt
   ```
   > **WARNING — run this only on sarasti.** It **overwrites**
   > `~/.config/sops/age/keys.txt`. On the driving machine that file holds your
   > personal age identity (possibly an `age-keygen` identity, which is not
   > reproducible from an SSH key) — overwriting it there is irreversible.
   > Note the key it writes is derived from the **user** key, so it is the same
   > recipient as troy's; deriving from the **host** key here would write a key
   > the home-manager rules do not list.
f. **[SARASTI]** Verify the home-manager path, confirm password login works
   (log out at the TTY and back in as `vkarasen` with the vault password), then
   close the sudo window.
   **The repo checkout has to exist on sarasti first** — a fresh install does
   not create one, so the literal `cd <repo>` from earlier revisions of this
   runbook has no referent. Clone it using the SSH key copied in step 4.6 (`git`
   is in `environment.systemPackages` in `modules/nixos/base.nix`, so no
   install is needed; `/home` is persistent, so this clone survives every later
   reinstall and flip):
   ```bash
   git clone git@github.com:vkarasen/dot_nixos.git ~/src/dot_nixos
   cd ~/src/dot_nixos && sops decrypt modules/home/sops/secrets/secrets.yaml > /dev/null \
     && echo home-ok
   ```
   (`sops` is not in `environment.systemPackages` — if `command -v sops` finds
   nothing, use `nix run nixpkgs#sops -- -d modules/home/sops/secrets/secrets.yaml`.)
   Equivalent check driven from troy, so the prompt lands on the terminal you
   are already sitting at (the decrypt still runs **on sarasti**, against
   sarasti's `~/.config/sops/age/keys.txt` — remoteness does not change whose
   key is used):
   ```bash
   ssh -t vkarasen@<ip> 'cd ~/src/dot_nixos && nix run nixpkgs#sops -- -d modules/home/sops/secrets/secrets.yaml > /dev/null && echo home-ok'
   ```
   **Then remove** the temporary `security.sudo.wheelNeedsPassword = false;`
   line added in step 3, commit, and run the **final rebuild** — this one is
   the first rebuild that requires a password, so the flag must be gone:
   - **[SARASTI]**, from a repo checkout on the machine itself (the clone from
     item f): `cd ~/src/dot_nixos && sudo nixos-rebuild switch --flake .#sarasti`
   - **[DRIVER]**, from troy:
     `nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --ask-sudo-password`
     (`--use-remote-sudo` will **not** work: it needs a passwordless sudo on the
     target, and the temporary passwordless window is exactly what you just
     removed. With the flag gone, `--ask-sudo-password` — which prompts the
     *local* TTY, so it needs a TTY — is the supported path.)
   The rebuild must finish clean, with no `setupSecrets` failure.

### Step 7 — dual-boot verification [SARASTI]

1. `grep -i windows /boot/grub/grub.cfg` must show a Windows entry — GRUB
   chainloads it via os-prober (`boot.loader.grub.useOSProber = true` in
   `modules/nixos/boot.nix`) from the MBR Windows disk.
   **The entry only appears if `C:` was mounted when that `grub.cfg` was
   generated.** os-prober does not scan unpartitioned guesswork: it reads the
   mounted filesystems, so a `grub.cfg` built with `/mnt/windows-c` unmounted has
   no Windows menuentry no matter how many times you rebuild — that is the whole
   of gap R1, and it is why step 5.2 mounts `/dev/disk/by-label/System` read-only
   and keeps it mounted through every rebuild. Fix it by remounting `C:`
   read-only and running one more rebuild, then re-grepping.
2. Confirm GRUB was installed to the **SN770**, not the Windows disk (disko
   auto-sets `grub.devices` from `my.disks.mainDevice`; `lsblk -o NAME,SIZE,MODEL`
   and the `bios_grub` partition must be on the SN770).
3. If Windows is absent from the menu **even after a rebuild with `C:` mounted**,
   fall back to an explicit entry via `boot.loader.grub.extraEntries` in
   `modules/hosts/sarasti.nix` (`flake.modules.nixos.sarasti`). This is the
   **guaranteed** path: it does not depend on os-prober discovering anything, so
   it can never silently disappear on a later rebuild the way an os-prober
   entry does. The Windows boot disk is a **separate MBR
   disk** (disk 0) that GRUB sees as `hd0` or `hd1` depending on boot order —
   check `sudo fdisk -l` / `lsblk -o NAME,SIZE,PTTYPE,MODEL` first and use the
   `(hdN,…)` that actually holds the MBR. Shape (substitute the real `hdN` and,
   for a plain MBR without a boot partition flag, use the disk-level
   `chainloader +1`):
   ```nix
   boot.loader.grub.extraEntries = ''
     menuentry "Windows 10 (MBR disk)" {
       insmod part_msdos
       insmod ntfs
       insmod chain
       set root=(hd1)
       chainloader +1
     }
   '';
   ```
   If the Windows volume needs to be addressed explicitly instead, use the
   partition form — MBR partitions are `msdosN`, not `gptN`:
   `chainloader (hd1,msdos1)+1`. Getting `hdN` wrong boots the wrong disk
   (Windows' own bootmgr will report a `\Boot\BCD` error); it does not write
   anything, so a wrong guess is recoverable — fix the number and rebuild.
   Note `extraEntries` is **visible in the menu and editable at boot**, so it
   does not expire: keep it only if os-prober stays unreliable.
4. Set the SN770 as the first **legacy/CSM** boot device in firmware. Windows
   stays selectable from the GRUB menu, not the firmware menu.

### Step 8 — NTFS data disks (manual for now) [SARASTI]

The NTFS data disks are **not yet declared** in `fileSystems`; mount them by
hand until they are (they become declarative `fileSystems` entries in M2, once
the disks are repurposed). These mounts assume the Windows-side preparation
from **step 0.3** (`powercfg /h off`, fast startup off) is already done — a
hibernated NTFS volume mounted read-write is corrupted by the first write, so
if you skipped that step, go back and do it before mounting `E:`/`F:`.

**Find the real labels — do not trust the names below.** Identify every volume
before mounting anything:

```bash
lsblk -o NAME,SIZE,LABEL,FSTYPE,MODEL /dev/nvme0n1 /dev/nvme1n1 /dev/sda /dev/sdb /dev/sdc
ls /dev/disk/by-label/
```

Match against the disk numbering in `docs/boot-modes.md`: the **Windows MBR
disk** (disk 0, 128 GB Crucial M4) is the *only* `dos`-partitioned disk and is
the one showing **3 partitions** — that is where the `C:` volume (label
`System`, plus recovery partitions) lives. `E:` (disk 1, 250 GB Samsung) and
`F:` (disk 2, 500 GB Crucial MX500) are single-volume NTFS disks; their real
labels are whatever `lsblk`/`ls /dev/disk/by-label/` print — the strings in the
commands below are only the historically observed values. If a label does not
appear, use the partition path instead
(`/dev/disk/by-partlabel/…` or `/dev/sdXN`) and mount that.

> **`G:` no longer exists.** That volume was the SN730 — disk 4 — which disko
> reformatted into `cryptpersist` at install (step 3). `E:`/`F:` are separate
> data disks (not on the MBR disk) and are still mountable, so `/mnt/g` is gone
> from the list below.

```bash
sudo mkdir -p /mnt/windows-c /mnt/e /mnt/f
# C: read-only — it is the Windows system volume; never write to it
sudo mount -t ntfs3 -o ro,uid=1000,gid=1000 /dev/disk/by-label/System /mnt/windows-c
# E:/F: read-write data volumes — substitute the LABEL lsblk actually printed
sudo mount -t ntfs3 -o uid=1000,gid=1000 /dev/disk/by-label/<E-label> /mnt/e
sudo mount -t ntfs3 -o uid=1000,gid=1000 /dev/disk/by-label/<F-label> /mnt/f
```

A `<E-label>` / `<F-label>` placeholder left unresolved is a hard stop: mounting
by a guessed label attaches the wrong volume, and the mount "succeeds" whether
or not it landed where you meant. Keep `C:` **read-only** always — it is a live
Windows system volume.

These mounts are **manual and non-persistent** for now — they vanish on reboot
until declared as `fileSystems` entries in M2 (Windows retired / mode flip to
uefi, see `docs/boot-modes.md`).

### Step 9 — hibernation [SARASTI or DRIVER]

`sarasti` is wired-only with no lid, so suspend/hibernate are manual — but the
`resume_offset` must still be set once, or resume after hibernate has no swap
location:

1. **[SARASTI]** Compute the swapfile offset:
   ```bash
   sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
   ```
2. **[DRIVER]** Set `my.boot.resumeOffset = <that number>;` in
   `modules/hosts/sarasti.nix` (it is `null` until then, so no
   `resume_offset=` kernel param is emitted), commit, rebuild.
3. **Test it**: on sarasti, run `systemctl hibernate`. It should power off and
   come back on the next power-on with your session intact. Verify the resume
   actually consumed the swap image — the only reliable check is the *previous*
   boot's log:
   ```bash
   journalctl -b -1 | grep -i resume
   ```
   A line mentioning `PM: Image successfully loaded` (or `resume=` / the
   `resume_offset`) means it resumed; a plain cold boot with no such line means
   it silently ignored the swapfile and you got a clean boot instead of a
   resume.
   Only the **offset** is manual: `boot.resumeDevice =
   "/dev/mapper/cryptroot"` is already set in `modules/nixos/boot.nix`, so the
   `resume=` kernel parameter is always present once `my.boot.resumeOffset` is.
4. Recompute whenever the swapfile is recreated (size change, reinstall).

