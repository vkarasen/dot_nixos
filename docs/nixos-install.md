# NixOS install runbook — host `troy` (ThinkPad T14s Gen 1)

Companion to `nixosConfigurations.troy`. Secrets (LUKS passphrase, user
password) live in the private Obsidian vault note
`inbox/2026-09-04-nixos-migration-session.md` — this doc references them, never
embeds them.

## 0. Before you start

- The **graphical** NixOS installer ISO (GNOME or Plasma) + a USB stick —
  **not** the minimal ISO (it has no `passwd`/`sshd`).
- A USB-C ethernet dongle (or `wpa_supplicant` on the live ISO for wifi).
- Laptop and workstation on the same reachable network.
- The `nixos-troy` branch pushed (or merged to `main`) so `.#troy` resolves.

## 1. Boot the installer

1. Flash the ISO:
   `dd if=nixos-<version>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync`
2. BIOS: **disable Secure Boot**, ensure UEFI boot mode.
3. Boot from USB (`F12` at the ThinkPad logo).

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

## 3. Deploy from the workstation

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
3. From the workstation: `ssh vkarasen@<ip>` (SSH key auth) — or log in at the
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
the workstation:

```bash
nixos-rebuild switch --flake '.#troy' --target-host vkarasen@<ip> --use-remote-sudo
```

or on the laptop after cloning the repo and checking out the right branch:

```bash
nh os switch .#troy
```

## 6. Post-boot graduation (in order)

1. **TPM unlock** — removes the LUKS prompt:
   `sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2`
2. **sops host key** — the host keys live under `/persist/etc/ssh` (NOT
   `/etc/ssh`, which only holds symlinks to the store). Derive the age pubkey,
   add it to `.sops.yaml`, re-encrypt, then write the age *private* key for the
   home-manager sops module (the NixOS sops module derives it itself via
   `age.sshKeyPaths`):
   ```bash
   ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub   # prints age1… pubkey
   # add that pubkey to .sops.yaml, then:
   sops updatekeys modules/home/sops/secrets/secrets.yaml
   # on the host, for home-manager's ~/.config/sops/age/keys.txt:
   sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt
   install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && sudo rm /tmp/keys.txt
   ```
3. **hibernate** — `resume_offset=533760` is already hardcoded in
   `modules/nixos/boot.nix`; if the swapfile is ever recreated (e.g. size
   change), recompute it with `sudo btrfs inspect-internal map-swapfile -r
   /swap/swapfile` and update the value.
4. **Secure Boot** (lanzaboote) — configured (`autoGenerateKeys` +
   `autoEnrollKeys`); keys auto-generate on first boot and systemd-boot enrolls
   them. The one manual step is entering BIOS **Setup Mode** (Security → Secure
   Boot → enable → "Reset to Setup Mode") before the enrollment boot — see
   `docs/nixos-architecture.md`.
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
