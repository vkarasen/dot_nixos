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
  **not** the minimal ISO (it has no `passwd`/`sshd`).
- A USB-C ethernet dongle (or `wpa_supplicant` on the live ISO for wifi).
- Laptop and workstation on the same reachable network.
- The `nixos-troy` branch pushed (or merged to `main`) so `.#troy` resolves.
  (sarasti: `.#sarasti` on `main`.)

## 1. Boot the installer

1. Flash the ISO:
   `dd if=nixos-<version>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync`
2. BIOS: **disable Secure Boot**, and **match the live-ISO boot mode to the
   host's `my.boot.mode`** — troy is UEFI; sarasti is legacy BIOS/CSM (see
   `docs/boot-modes.md`). Booting the ISO in the wrong mode produces a
   mismatched NixOS — nixos-anywhere inherits the live environment's mode.
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
3. nixos-anywhere kexecs into its own environment, runs disko (partition + LUKS
   + btrfs), installs the system, and reboots the laptop.
4. Remove the key file when done: `rm /tmp/secret.key`

## 4. First boot (on the laptop)

1. LUKS prompt → type the passphrase.
2. Boot lands at a TTY (no desktop yet).
3. From the driving machine (troy or your workstation): `ssh vkarasen@<ip>`
   (SSH key auth) — or log in at the TTY with the user password from the vault.
   TTY with the user password from the vault.
4. Copy your SSH private key over (needed for git-over-SSH, the zqnr.de build
   host, and the `gentian` host — `/home` is persistent, so this survives):
   `scp ~/.ssh/id_ed25519 vkarasen@<ip>:~/.ssh/`
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
      host:
      ```bash
      sops updatekeys modules/home/sops/secrets/secrets.yaml
      ```
      Any encrypted `*.md` under `modules/home/pi/skills-private/` is a separate
      file and needs its own `sops updatekeys` — same recipient list, but
      `updatekeys` is per-file (none are committed right now; apply this when
      the first private skill lands).
   d. **Write the age *private* key for the home-manager sops module** (the
      NixOS sops module derives its own from `age.sshKeyPaths`; nothing to do
      there). On the host:
      ```bash
      sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt
      install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && sudo rm /tmp/keys.txt
      ```
   e. **Verify the re-encryption landed on the target** (do not trust a green
      `updatekeys`):
      ```bash
      # system-level secret via the host key (no repo needed):
      sudo test -s /run/secrets/user-password && echo system-ok
      # home-manager secrets via ~/.config/sops/age/keys.txt (from step d):
      cd <repo> && sops decrypt modules/home/sops/secrets/secrets.yaml > /dev/null \
        && echo home-ok
      ```
      Both commands must succeed. `sops`/`systemctl status sops-nix` failing
      here means step b's anchor was not referenced by the target's
      `path_regex` rule, or step c ran before the anchor edit was saved.
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
it is lost, because nothing else can unlock `cryptroot`.

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
   vault note at the same time:
   ```bash
   printf '%s' '<sarasti-LUKS-passphrase-from-vault>' > /tmp/secret.key
   ```
3. **Flash the graphical NixOS ISO** (GNOME or Plasma — the minimal ISO has no
   `passwd`/`sshd`):
   ```bash
   dd if=nixos-<version>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

### Step 1 — firmware on sarasti [SARASTI]

1. Power on and hit **F11** for the MSI one-time boot menu.
2. Boot the USB in **CSM/legacy mode with Secure Boot disabled** —
   `my.boot.mode = "legacy"`, and nixos-anywhere inherits the live
   environment's mode.
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
     (`my.disks.persistDevice`). Its only content is an empty NTFS volume (`G:`).

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
   + btrfs), installs the system, and reboots.

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
3. Remove the key file: `rm /tmp/secret.key`

### Step 4 — first boot [SARASTI]

1. GRUB menu → **LUKS passphrase** → a TTY (no desktop yet).
2. The erase-on-boot service prints
   `first boot: capturing pristine root as blank snapshot` — **expected, not an
   error**. A sops activation warning may also appear on this first boot —
   expected until enrollment (step 6).
3. From the driving machine, `ssh-keygen -R <ip>` first (the host key changed
   with the reinstall), then `ssh vkarasen@<ip>`. Key auth works even though the
   password is locked — the reused `id_ed25519` is what gets you in; if the key
   is not on sarasti yet, copy it over:
   `scp ~/.ssh/id_ed25519 vkarasen@<ip>:~/.ssh/` (then `chmod 600` it there).

### Step 5 — hardware capture + rebuild [SARASTI or DRIVER]

`disko` already declares filesystems/LUKS/swap, so do **not** import a full
`nixos-generate-config` output (it would duplicate and conflict with them).

1. Capture only the hardware bits:
   ```bash
   sudo nixos-generate-config --no-filesystems --show-hardware-config
   ```
2. Fold the relevant lines (kernel modules, cpu governor, firmware) into
   `modules/hosts/sarasti.nix`, commit, and rebuild — from the driving machine:
   ```bash
   nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --use-remote-sudo
   ```
   (`--use-remote-sudo` works only because of the temporary
   `wheelNeedsPassword = false` from step 3; it is removed in step 6f.)

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
   ```bash
   sops updatekeys modules/home/sops/secrets/secrets.yaml
   ```
   Then `git add` + commit the re-encrypted `secrets.yaml` — a modified but
   **unstaged** file is **invisible** to the flake, so a forgotten `git add`
   looks exactly like a failed enrollment.
d. **[DRIVER or SARASTI]** Rebuild sarasti (from the driving machine:
   `nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --use-remote-sudo`).
e. **[SARASTI]** Now the **home-manager** age key:
   ```bash
   sudo ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
   ```
   > **WARNING — never run this on troy or the driving machine.** It writes the
   > *host* key into `~/.config/sops/age/keys.txt`, **overwriting your personal
   > age key**. Run it only on sarasti, and only against sarasti's own
   > `id_ed25519`.
f. **[SARASTI]** Verify before trusting a green switch, then close the sudo
   window:
   ```bash
   sudo test -s /run/secrets/user-password && echo system-ok
   ```
   Confirm password login works (log out at the TTY and back in as `vkarasen`
   with the vault password). **Then remove** the temporary
   `security.sudo.wheelNeedsPassword = false;` line added in step 3, commit, and
   rebuild once more — sudo now requires the sops-backed password.

### Step 7 — dual-boot verification [SARASTI]

1. `grep -i windows /boot/grub/grub.cfg` must show a Windows entry — GRUB
   chainloads it via os-prober (`boot.loader.grub.useOSProber = true` in
   `modules/nixos/boot.nix`) from the MBR Windows disk.
2. Confirm GRUB was installed to the **SN770**, not the Windows disk (disko
   auto-sets `grub.devices` from `my.disks.mainDevice`; `lsblk -o NAME,SIZE,MODEL`
   and the `bios_grub` partition must be on the SN770).
3. If Windows is absent from the menu, add an explicit entry via
   `boot.loader.grub.extraEntries` in `modules/hosts/sarasti.nix`.
4. Set the SN770 as the first **legacy/CSM** boot device in firmware. Windows
   stays selectable from the GRUB menu, not the firmware menu.

### Step 8 — NTFS data disks (manual for now) [SARASTI]

The NTFS data disks are **not yet declared** in `fileSystems`; mount them by
hand until they are (they become declarative `fileSystems` entries in M2, once
the disks are repurposed). First run `powercfg /h off` on the
Windows side (plus fast startup off) — mounting hibernated NTFS read-write
corrupts it.

> **`G:` no longer exists.** That volume was the SN730 — disk 4 — which disko
> reformatted into `cryptpersist` at install (step 3). Only the Windows-side
> volumes on the MBR boot disk (`C:` read-only, `E:`/`F:` read-write) are still
> mountable, so `/mnt/g` is gone from the list below.

```bash
sudo mkdir -p /mnt/windows-c /mnt/e /mnt/f
# C: read-only — it is the Windows system volume; never write to it
sudo mount -t ntfs3 -o ro,uid=1000,gid=1000 /dev/disk/by-label/System /mnt/windows-c
# E:/F: read-write data volumes
sudo mount -t ntfs3 -o uid=1000,gid=1000 /dev/disk/by-label/Superfast /mnt/e
sudo mount -t ntfs3 -o uid=1000,gid=1000 /dev/disk/by-label/<F-label>   /mnt/f
```

Confirm labels with `ls /dev/disk/by-label/` before mounting. These mounts are
**manual and non-persistent** for now — they vanish on reboot until declared as
`fileSystems` entries in M2 (Windows retired / mode flip to uefi, see
`docs/boot-modes.md`).

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
3. Recompute whenever the swapfile is recreated (size change, reinstall).

