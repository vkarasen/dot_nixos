---
name: userspace-mounts
description: Use when adding or debugging userspace mounts in Home Manager or Nix configs, especially rclone, sshfs, FUSE, or WSL-related mount behavior.
---

# Userspace mounts

Use this skill when a task involves a FUSE-based mount in Home Manager,
non-NixOS Linux, WSL, or any other setup where a filesystem should appear as a
normal path without moving the data into NixOS/system configuration.

## Core rules

- Do **not** assume `fusermount3` from the Nix store is usable on non-NixOS.
- Prefer the system-provided helper at `/run/wrappers/bin/fusermount3` when a
  mount needs to be launched from Home Manager.
- Split debugging into two questions:
  1. does the backend/auth work without mounting?
  2. does the FUSE mount itself work on this host?
- If a mount fails with `Operation not permitted`, first check the host FUSE
  environment before changing the Home Manager module.
- Treat WSL as a special host environment: rootless FUSE may require host-side
  changes even when `/dev/fuse` exists.

## What to check first

When a mount fails:

1. Confirm the remote or backend itself works without mounting.
2. Check that the config file is readable by the user that runs the mount.
3. Verify the mount helper exists and is executable:

   ```bash
   ls -l /run/wrappers/bin/fusermount3
   ```

4. Check whether `/dev/fuse` exists and is writable:

   ```bash
   ls -l /dev/fuse
   ```

5. If the mount is intended to be shared with another user, verify that
   `/etc/fuse.conf` contains `user_allow_other`.
6. If the mount still fails rootless on WSL, treat that as a host-side issue
   before changing Home Manager.

## User setup guide: making fusermount work

When this repo needs a real `fusermount3`, the user typically has to do the
host-level work manually, usually with `sudo`.

### On normal Linux distributions

Install the distro package that provides a real setuid `fusermount3` binary.
For example, on Debian/Ubuntu-like systems:

```bash
sudo apt install fuse3
```

Then expose it where Home Manager and the Nix tooling expect to find it:

```bash
sudo mkdir -p /run/wrappers/bin
sudo ln -sf /usr/bin/fusermount3 /run/wrappers/bin/fusermount3
```

If the mount needs to be visible to another user, add:

```bash
echo user_allow_other | sudo tee /etc/fuse.conf
```

### On WSL

If a rootless mount fails with `Operation not permitted`, do not jump straight
to Home Manager changes. First verify the host-side pieces:

- `/dev/fuse` exists and is writable
- the backend/auth works without the mount
- `/etc/fuse.conf` contains `user_allow_other` if the mount uses
  `--allow-other`
- `/run/wrappers/bin/fusermount3` points to a real system helper

If the mount still fails rootless but works as root, prefer a system-level
mount service or a distro-provided `fusermount3` rather than relying on a
Nix-store helper.

## Home Manager guidance

- Put the mount logic in Home Manager only when the mount is genuinely a
  per-user feature.
- Keep the secret/config file in SOPS if the backend needs credentials.
- When a mount service uses `fusermount3`, point it at the system helper path,
  not at the Nix-store binary.
- If a mount needs special host setup, tell the user exactly which commands
  they must run manually; do not pretend Home Manager can perform those sudo
  steps.
- Do not overfocus on `/etc/fuse.conf`: it only affects `--allow-other`, not
  the core question of whether a rootless FUSE mount is permitted at all.

## Good wording for future tasks

If you are asked to add a userspace mount feature, remember this rule of thumb:

> For FUSE mounts on non-NixOS systems, use the system-provided `fusermount3`
> helper and verify the host FUSE environment before blaming Home Manager.
> On WSL, treat `Operation not permitted` as a host-side issue first and ask
> the user to check `/dev/fuse`, `user_allow_other`, and the real system mount
> helper.
