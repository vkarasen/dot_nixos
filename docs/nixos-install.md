# NixOS install runbook — host `troy` (ThinkPad T14s Gen 1)

Companion to `nixosConfigurations.troy`. The main flow below is **troy** (UEFI);
the second host, `sarasti` — a legacy BIOS/CSM desktop that dual-boots Windows —
is covered by its own section at the end ([§8](#8-sarasti-legacy-bios-desktop))
and by `docs/boot-modes.md`. Secrets (each host's LUKS passphrase, the shared
user password) live in the KeePassXC database `~/sync/private/vkarasen.kdbx` —
this doc references them, never embeds them. The sops decryption keys are the
hosts' own `/persist/etc/ssh/ssh_host_ed25519_key` files; their private halves
belong in that kdbx as **attachments**, because losing both host keys makes
`secrets.yaml` unreadable (there is no user key and no recovery path).

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
   `printf '%s' '<LUKS-passphrase-from-kdbx>' > /tmp/secret.key`
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
   (troy's flow only — sarasti's §8 deliberately **defers** this deletion to
   step 4.7, after the passphrase has been proved at a typed unlock. Do not copy
   troy's pattern there.)

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
   `/etc/ssh`, which only holds symlinks to the store). In **troy's** flow the
   ed25519 host key is **auto-generated by sshd on first boot** — it is declared
   as `services.openssh.hostKeys` in `modules/nixos/base.nix` (pointed at
   `/persist` for impermanence) and does **not** exist on the installer or in
   the nixos-anywhere phase, which is why this step starts *after* §4's first
   boot, once §5's rebuild is done. (This is **troy-specific**: sarasti
   pre-seeds the key before the deploy instead — see §8 step 0.5.)
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
      in only one leaves the other path family undecryptable on that host. The
      only recipients are **machine host keys** (no user-held key exists):
      ```yaml
      keys:
        - &troy age1rvvn…       # troy host key
        - &sarasti age1…        # ← new host: add its own anchor
      creation_rules:
        - path_regex: modules/home/sops/secrets/[^/]+\.(yaml|json|env|ini)$
          key_groups:
            - age: [*troy, *sarasti]   # ← reference it here
        - path_regex: modules/home/pi/skills-private/[^/]+\.md$
          key_groups:
            - age: [*troy, *sarasti]   # ← and here
      ```
   c. **Re-encrypt from a machine that already holds an enrolled recipient's
      age private key** — `sops updatekeys` must decrypt the file's data key,
      which the *new* host cannot do yet (this is the whole point of the step).
      Run it on **troy** (`/persist/etc/ssh/ssh_host_ed25519_key`, the only
      recipient identity an operator has access to), never on the new host.
      `sops` may not be on the driver's `PATH` — prefix it with
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
      # modules/nixos/sops.nix — no repo and no user key needed; `neededForUsers`
      # puts it in /run/secrets-for-users):
      sudo test -s /run/secrets-for-users/user-password && echo system-ok
      ```
      If this fails, stop here: step b's anchor was not referenced by the
      target's `path_regex` rule, or step c ran before the anchor edit was
      saved. `systemctl status sops-install-secrets` shows which recipient
      failed.
   e. **Write the age *private* key for the home-manager sops module** — a
      separate *file* from the system one, but the **same** identity: the NixOS
      sops module derives its key from the **host** key
      (`/persist/etc/ssh/ssh_host_ed25519_key`, via `age.sshKeyPaths`), and
      home-manager reads `~/.config/sops/age/keys.txt`, which must hold the age
      private key derived from that **same host key** (this is exactly how
      troy's `keys.txt` equals its own `&troy` recipient).
      `~/.ssh/id_ed25519` is **not** a sops key at all. On the host:
      ```bash
      (umask 077; sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt)
      mkdir -p ~/.config/sops/age
      install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && rm /tmp/keys.txt
      ```
   f. **Verify the home-manager secrets** (do not trust a green `updatekeys`):
      ```bash
      cd <repo> && sops decrypt modules/home/sops/secrets/secrets.yaml > /dev/null \
        && echo home-ok
      ```
      If this fails but step d printed `system-ok`, the file in
      `~/.config/sops/age/keys.txt` is not the host-derived identity — most
      likely someone derived it from `~/.ssh/id_ed25519`, which is not a
      recipient in `.sops.yaml`.
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
step 0 lives in a **KeePassXC entry** in `~/sync/private/vkarasen.kdbx` (its
own entry — **not** troy's passphrase); there is no recovery path if it is
lost, because nothing else can unlock `cryptroot` **or** `cryptpersist` — and
losing `cryptpersist` loses `/home` and `/persist` (every secret, including the
sops host key). One passphrase, both containers — and **two copies**: the kdbx
entry *and* a **paper copy of the kdbx master password** kept offline. The kdbx
is the second-copy anchor (a database is only reachable if its master password
is recorded somewhere other than your head), and the paper copy is what makes
that true on a machine that holds none of your files.

> Two more kdbx **attachments** matter just as much: **sarasti's**
`/persist/etc/ssh/ssh_host_ed25519_key` (staged in step 0.5) and **troy's**
`/persist/etc/ssh/ssh_host_ed25519_key`. `.sops.yaml` lists only machine host
keys, so those two private keys are the *only* things that can decrypt
`secrets.yaml` — lose both and every secret is unreadable, with no `sops`
recovery path.

### Step 0 — prepare on troy [TROY]

1. Get the repo current and **pre-build the config before touching the USB**, so
   a Nix error surfaces here and not 20 minutes into an install:
   ```bash
   git checkout main && git pull
   nix build .#nixosConfigurations.sarasti.config.system.build.toplevel --no-link
   ```
   This only *evaluates and builds* — no disk is touched.
2. **LUKS passphrase** (per-host — do **not** reuse troy's; generate it as
   ASCII diceware). Store it in a **KeePassXC entry** in
   `~/sync/private/vkarasen.kdbx`, and keep the **kdbx master password** on
   paper somewhere offline. Then write the same passphrase to the temporary key
   file nixos-anywhere uploads:
   ```bash
   printf '%s' '<sarasti-LUKS-passphrase-from-kdbx>' > /tmp/secret.key
   ```
   The kdbx entry is the copy that is reachable independently of the machine
   being installed; the paper master-password copy is what makes the kdbx
   reachable when none of your machines (and therefore no synced copy of the
   database) are available. What is *not* recoverable is a passphrase whose only
   copy lives on the box whose disks you just encrypted — a single mistyped
   character then becomes unrecoverable disks.
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

### Step 0.5 — pre-seed the sops host key [TROY]

sops on sarasti decrypts with the **host** key at
`/persist/etc/ssh/ssh_host_ed25519_key`. Generating that key *before* first boot
and enrolling its age recipient *before* the deploy is what removes the whole
bootstrap problem: there is **no** temporary
`security.sudo.wheelNeedsPassword = false` window, **no** expected
`setupSecrets` failure, and the normal login password (the same one troy uses —
both hosts read the same sops `user-password` hash) works at the console on the
very first boot. The key is carried into the install by `--extra-files` in
step 3.

1. **Generate the key into a staging tree** (not `/etc`, never in the repo):
   ```bash
   mkdir -p /tmp/scratch/sarasti-extra/persist/etc/ssh
   chmod 700 /tmp/scratch/sarasti-extra
   ssh-keygen -t ed25519 -N '' -C sarasti-host \
     -f /tmp/scratch/sarasti-extra/persist/etc/ssh/ssh_host_ed25519_key
   chmod 755 /tmp/scratch/sarasti-extra/persist \
     /tmp/scratch/sarasti-extra/persist/etc \
     /tmp/scratch/sarasti-extra/persist/etc/ssh
   chmod 600 /tmp/scratch/sarasti-extra/persist/etc/ssh/ssh_host_ed25519_key
   ssh-to-age < /tmp/scratch/sarasti-extra/persist/etc/ssh/ssh_host_ed25519_key.pub
   # expect: age1j3cqugcgnsyldrdx7l7wxg93yx0g6kldusvg5pg3jqkw6y7t6uyqv4ce5l
   ```
   **Why the two different modes:** the stage **root**'s `700` is not copied —
   `--extra-files` copies the tree into `/mnt` and nixos-anywhere then runs
   `chmod 755 /mnt` itself, so the root mode only matters locally. The
   **subdirectory** modes *are* copied and land on `/mnt/persist` and
   `/mnt/persist/etc`, which become the live `/persist` and `/persist/etc` —
   they must be `755`, or those directories end up group/other-inaccessible on
   the installed system. The key itself stays `600`.
   That pubkey is already committed in `.sops.yaml` as `&sarasti`. If you
   regenerate the key (or install a *different* host), the anchor **must** be
   re-derived and re-enrolled — deploying a host key whose age recipient is not
   in `.sops.yaml` is the one failure this step exists to prevent.

2. **Enroll the recipient and re-encrypt** — in `.sops.yaml`, add the
   `&sarasti` anchor under `keys:` **and** reference it in **both**
   `creation_rules` (`modules/home/sops/secrets/*` and
   `modules/home/pi/skills-private/*.md`); one rule only leaves the other path
   family undecryptable. Then re-encrypt **every** covered file from troy
   (whose host key is already a recipient):
   ```bash
   nix run nixpkgs#sops -- updatekeys -y modules/home/sops/secrets/secrets.yaml
   # each encrypted private-skill .md is a separate file — repeat per file:
   # nix run nixpkgs#sops -- updatekeys -y modules/home/pi/skills-private/<name>.md
   ```
3. **Verify, then commit** — the flake only sees the git tree, so an
   uncommitted `.sops.yaml` edit or an unstaged `secrets.yaml` is invisible to
   the deployed system and sops fails on sarasti:
   ```bash
   grep -c 'recipient: age1' modules/home/sops/secrets/secrets.yaml   # one per recipient
   nix run nixpkgs#sops -- decrypt modules/home/sops/secrets/secrets.yaml > /dev/null && echo sops-ok
   git add .sops.yaml modules/home/sops/secrets/secrets.yaml
   git status --short .sops.yaml modules/home/sops/secrets/   # must show them staged
   ```
   then commit (`sops updatekeys` has already re-encrypted the data key to the
   new recipient list). An uncommitted or unstaged file is invisible to the
   flake, so a forgotten `git add` looks exactly like a failed enrollment.
4. **Store the private key as a kdbx attachment right now — before deploying.**
   `/tmp/scratch/…` does not survive a troy reboot and troy's root is erased on
   every boot (impermanence), so a reboot between here and step 3 would lose the
   only copy of a key that `secrets.yaml` is now encrypted to. Same for troy's
   own `/persist/etc/ssh/ssh_host_ed25519_key`, which is the only *other* way
   back into the file.

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

**There is no temporary sudo window to open.** Because step 0.5 pre-seeded
`/persist/etc/ssh/ssh_host_ed25519_key` and committed its recipient in
`.sops.yaml`, sops decrypts on the very first boot: the `users` activation gets
the real `user-password` hash, so `vkarasen`'s normal login password works from
the first boot and sudo prompts for it as usual. There is therefore no
`security.sudo.wheelNeedsPassword = false` line to add anywhere, and no
expected `setupSecrets` failure to tolerate (step 4.2).

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
   nix run github:nix-community/nixos-anywhere/bad98b0685cf47eaeadcaf6787da8b51cf025693 -- \
     --flake '.#sarasti' \
     --disk-encryption-keys /tmp/secret.key /tmp/secret.key \
     --extra-files /tmp/scratch/sarasti-extra \
     --target-host root@<ip>
   ```
   nixos-anywhere kexecs into its own environment, runs disko (partition + LUKS
   + btrfs), installs the system, and **reboots it itself**.

   > **What boots after that reboot.** The deploy ends with a reboot the driver
   > does not control, and F11 is a **one-time** boot menu — so that reboot
   > falls back to the firmware's default boot order, which is still
   > **Windows**. Either set the SN770 first in firmware **before** deploying
   > (Step 1 is the firmware session — DEL → Settings → Boot: put the SN770 first
   > among the legacy/CSM boot devices; it carries no bootloader until the deploy
   > writes one, but this is the order that post-deploy reboot will follow), or
   > stand ready to press F11 at the reboot and pick the SN770. **If Windows
   > starts, that is the old
   > boot order — not a failed install.** Nothing was written to the Windows
   > disk; power off and boot the SN770.

   - **Pinned** to nixos-anywhere `1.13.0`
     (`bad98b0685cf47eaeadcaf6787da8b51cf025693`): the phase ordering below is
     that version's, and the plain `github:nix-community/nixos-anywhere` (HEAD)
     may order phases differently between runs.
   - `--extra-files /tmp/scratch/sarasti-extra` is what carries the host key
     from step 0.5 into the installed system. nixos-anywhere copies the tree
     into `/mnt` **after** the disko phase and **before** `nixos-install`, so
     `…/persist/etc/ssh/ssh_host_ed25519_key` lands on the already-mounted
     `cryptpersist` at `/mnt/persist/etc/ssh/ssh_host_ed25519_key` — i.e. on the
     encrypted persist filesystem, not on the ephemeral system disk. File modes
     are preserved — the key's `600` **and** the `755` set on the stage's
     `persist`, `persist/etc` and `persist/etc/ssh` directories in step 0.5
     (the stage root's `700` is irrelevant: nixos-anywhere re-chmods `/mnt` to
     `755`). Ownership becomes `root`, so no `--chown` is needed.
   - `--disk-encryption-keys <remote> <local>` — remote path first; the same
     path twice is fine. `--phases` cannot skip `disko` safely (disko is what
     creates *and mounts* the filesystems, so dropping it leaves `/mnt` empty);
     otherwise nothing about the phase list needs changing.
   - **If this fails and you retry**: the kexec phase re-generates the target's
     SSH host key, so the second attempt will refuse to connect with a
     `HOST KEY VERIFICATION FAILED` error. Clear the stale entry first —
     `ssh-keygen -R <ip>` — then re-run exactly the same command.
     **Check the staged tree still exists before retrying.** troy's root is
     erased on every boot (impermanence), so if troy rebooted since step 0.5 the
     whole `/tmp/scratch/sarasti-extra` tree is **gone** — recreating it from
     the kdbx attachment (same layout: `persist/etc/ssh/`, dirs `755`, key
     `600`, plus the `.pub`) is a prerequisite, and a deploy without
     `--extra-files` (or with an empty tree) lands no host key at all and fails
     at first-boot `setupSecrets` (step 4.2).
   - **disko formats BOTH disks**: `<mainDevice>` (the 2 TB SN770) into
     `cryptroot`, and `<persistDevice>` (the 256 GB SN730) into a second LUKS2
     container, `cryptpersist`, holding `/persist` and `/home`. The separate
     persist disk is what lets a *later* reinstall of the system disk leave user
     data — and every secret under `/persist` — intact.
   - **One passphrase, both containers**: the single
     `--disk-encryption-keys /tmp/secret.key /tmp/secret.key` pair uploads one
     key file, and disko's `passwordFile` hands the *same* file to `cryptroot`
     and `cryptpersist`. There is no second passphrase to invent or record —
     the one in the kdbx entry unlocks both.
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
   error**. **`setupSecrets` must now SUCCEED** — a non-zero exit here is a hard
   failure, not a warning: the host key was pre-seeded in step 0.5 and its
   recipient is in the committed `.sops.yaml`, so sops decrypts on this very
   first switch. Verify it:
   ```bash
   sudo test -s /run/secrets-for-users/user-password && echo system-ok
   sudo systemctl status sops-install-secrets   # no failed unit
   ```
   If it **failed**, one of two things is wrong: the staged key did not land
   (`sudo ls -l /persist/etc/ssh/ssh_host_ed25519_key` — must exist, be
   non-empty and mode 600), or the `.sops.yaml` / `updatekeys` commit was not in
   the flake that was actually deployed (the flake only sees the git tree).
   **Stop and fix that — do not proceed past a `setupSecrets` failure.**
   Recovering from the *didn't-land* case (sshd generated its own key instead,
   so the enrolled recipient's key is not on the box — and with no
   `user-password` there is **no console password and no sudo**; the only way in
   is the baked-in `authorizedKeys` SSH key):
   1. If sshd is up, **SSH in with the SSH key** (`ssh vkarasen@<ip>`) and
      replace `/persist/etc/ssh/ssh_host_ed25519_key{,.pub}` there, then reboot.
   2. Otherwise boot the **live ISO** (any mode), open the persist container
      with the *typed* passphrase, and restore the key:
      ```bash
      sudo cryptsetup open /dev/disk/by-partlabel/disk-persist-cryptpersist cryptpersist
      sudo mkdir -p /mnt/persist
      sudo mount -o subvol=/persist /dev/mapper/cryptpersist /mnt/persist
      # restore from the kdbx attachment (same layout/modes):
      sudo install -m 600 -o root -g root <attach>/ssh_host_ed25519_key \
        /mnt/persist/etc/ssh/ssh_host_ed25519_key
      sudo install -m 644 -o root -g root <attach>/ssh_host_ed25519_key.pub \
        /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
      sudo umount /mnt/persist && sudo cryptsetup close cryptpersist && sudo reboot
      ```
      On reboot sops finds the enrolled key and `setupSecrets` succeeds. (If the
      *pub* key differs from the one enrolled in `.sops.yaml`, the flake was
      built from a commit that did not contain the anchor edit — fix the commit
      and redeploy rather than swapping keys.)
   **Console login is the cheapest early test:** at the TTY, log in as
   `vkarasen` with the login password from the kdbx entry (the same password
   troy uses — both hosts read the same sops `user-password` hash). If that
   works, `user-password` decrypted and sudo will prompt for it normally.
3. **Confirm the two-disk layout before going further** — `/persist` and
   `/home` must both be mounted from `cryptpersist`, not from `cryptroot`:
   ```bash
   findmnt /home /persist
   ```
   Each line must show `/dev/mapper/cryptpersist` as the source (and
   `subvol=/home` / `subvol=/persist` in the options). A missing `/persist`
   means the passphrase prompt for `cryptpersist` failed — see item 1.
4. **Reboot once now, before spending time on the user-key setup.** One extra
   reboot exercises both things that only break on the *second* boot: the
   erase-on-boot
   rollback (root is wiped and re-snapshotted) and the persistence split
   (`/home` + `/persist` survive, `/` does not). Finding a problem here costs a
   reboot; finding it after you have wired up the home-manager key costs a
   re-install. On this boot the blank-snapshot line does **not** reappear (only
   on the very first boot).
5. From the driving machine, `ssh-keygen -R <ip>` first (the host key changed
   with the reinstall), then `ssh vkarasen@<ip>`. Key auth works as before: the
   **public** key is already authorized declaratively by
   `users.users.vkarasen.openssh.authorizedKeys.keys` in `modules/nixos/base.nix`,
   so nothing has to be copied just to log in — and the login password works too
   (step 4.2), so sudo does not need any workaround.
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
   *typed* passphrase from the kdbx entry (not a paste, and not a boot that
   skipped the prompt). That typed unlock is the verification that the recorded
   passphrase has no typo. Delete it earlier — as an earlier revision of this
   runbook did, at the end of step 3 — and a typo in the recorded passphrase
   becomes **unrecoverable disks**: both `cryptroot` and `cryptpersist` were
   created
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
   step 6 (the rebuild in 6d regenerates `grub.cfg` too). The mount does not
   survive a reboot, so remount before each rebuild — otherwise the menu
   silently loses its Windows entry. Read-only always: `C:` is a live Windows
   system volume.
3. Fold the relevant lines (kernel modules, cpu governor, firmware) into
   `modules/hosts/sarasti.nix`, commit, and rebuild — from the driving machine:
   ```bash
   nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --ask-sudo-password
   ```
   `--ask-sudo-password` prompts on the *local* TTY for sarasti's sudo password,
   so it needs a TTY. `--use-remote-sudo` is **not** usable here: it expects
   passwordless sudo on the target, which sarasti deliberately does not have
   (there is no temporary passwordless window any more — see step 3).
   > **Flag name is provisional:** `--ask-sudo-password` is the
   > `nixos-rebuild`/`nixos-rebuild-ng` spelling on 26.05, **not verified by the
   > reviewer**. Confirm with `nixos-rebuild --help` on the driver before relying
   > on it (it may be `--sudo-password` or similar on other versions).
   `setupSecrets` succeeds on this rebuild too; the same non-zero exit means the
   same thing it did in step 4.2 — stop and fix it.

### Step 6 — home-manager sops key [SARASTI]

Enrollment is **already done**: the host key was pre-seeded and its recipient
committed in step 0.5, so the system secrets decrypt from first boot (step 4.2).
There is no `updatekeys` step here, no anchor edit, and no temporary sudo flag
to remove. What is left is the *home-manager* key file — a separate path.

**Preflight — declared secrets exist.** Before wiring the user key, confirm the
secrets the host actually consumes are present in the (encrypted) file:

```bash
for k in user-password wifi-home-psk \
  tavily_api_key anthropic_api_key deepseek_api_key linkedin_api_key \
  google_oauth_client_id google_oauth_client_secret \
  rclone_gdrive_conf rclone_nextcloud_conf; do
  grep -q "^$k:" modules/home/sops/secrets/secrets.yaml || echo "MISSING $k"
done
```

No output = all declared secrets exist. That list is **both layers**: the two
NixOS secrets (`user-password` → `neededForUsers` →
`hashedPasswordFile`; `wifi-home-psk` → the NetworkManager template rendered on
sarasti too, since it selects `nixos.wifi`) and the eight home-manager secrets
declared in the `lib.mkIf config.my.is_private` block of
`modules/home/sops/default.nix` — the home-manager `sops-nix` service fails at
activation on a declared-but-missing key, exactly like the system one.
(`mcp_proxy_auth_token` is only declared when `my.pi.mcpProxy.requireAuth` is
enabled, which is off by default — add it here if that is ever turned on.)

a. **[SARASTI]** Re-confirm the **system** sops path — it does not depend on
   `~/.config/sops/age/keys.txt`, so it is the honest baseline:
   ```bash
   sudo test -s /run/secrets-for-users/user-password && echo system-ok
   ```
   sops-nix derived that key from the **HOST** key
   `/persist/etc/ssh/ssh_host_ed25519_key` (`sops.age.sshKeyPaths` in
   `modules/nixos/sops.nix`). No `system-ok` = the flake that was deployed does
   not match the committed `.sops.yaml`: go back to step 0.5 before touching the
   user key.
b. **[SARASTI]** Write the age **private** key for the home-manager sops
   module. Home-manager reads `~/.config/sops/age/keys.txt`, and this repo's
   `.sops.yaml` lists **machine host keys only** — so that file must hold the
   identity derived from *this host's* key, exactly as troy's does:
   ```bash
   (umask 077; sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt)
   mkdir -p ~/.config/sops/age
   install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && rm /tmp/keys.txt
   ```
   The `umask 077` subshell matters: the redirection runs in **your** shell, so
   without it `/tmp/keys.txt` is created world-readable (`644`) for the moment
   before it is installed. The file is owned by you (not root), so the plain
   `rm` after `install` suffices.
   > **WARNING — run this only on sarasti.** It **overwrites**
   > `~/.config/sops/age/keys.txt`. Deriving from `~/.ssh/id_ed25519` (as an
   > earlier revision of this runbook did) writes a key that is **not a
   > recipient at all** — `~/.ssh/id_ed25519` is only for git-over-SSH, the
   > zqnr.de build host, and `gentian`. On the driving machine the same command
   > would also overwrite troy's working host-derived identity, which is the
   > only key that decrypts `secrets.yaml` there.
c. **[SARASTI]** Verify the home-manager path — this is the `home-ok` gate.
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
   Equivalent check driven from troy [DRIVER], so the prompt lands on the
   terminal you are already sitting at (the decrypt still runs **on sarasti**,
   against sarasti's `~/.config/sops/age/keys.txt` — remoteness does not change
   whose key is used):
   ```bash
   ssh -t vkarasen@<ip> 'cd ~/src/dot_nixos && nix run nixpkgs#sops -- -d modules/home/sops/secrets/secrets.yaml > /dev/null && echo home-ok'
   ```
d. **Final rebuild** — there is no temporary flag to remove, so this is an
   ordinary password-prompting rebuild:
   - **[SARASTI]**, from the repo checkout on the machine itself (item c):
     `cd ~/src/dot_nixos && sudo nixos-rebuild switch --flake .#sarasti`
   - **[DRIVER]**, from troy:
     `nixos-rebuild switch --flake '.#sarasti' --target-host vkarasen@<ip> --ask-sudo-password`
     (`--ask-sudo-password` prompts the *local* TTY, so it needs a TTY; its
     exact spelling is the unverified one flagged in step 5.3 — check
     `nixos-rebuild --help`. `--use-remote-sudo` does **not** work here — it
     expects passwordless sudo on the target, which sarasti does not have and no
     longer needs.)
   The rebuild must finish clean, with no `setupSecrets` failure. If it fails,
   the deployed flake and the committed `.sops.yaml` disagree — the same failure
   mode as step 4.2.

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

