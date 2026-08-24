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
- Let the service resolve `fusermount3` via a PATH that covers both NixOS
  (`/run/wrappers/bin`) and non-NixOS (`/bin`, `/usr/bin`). Never rely on the
  non-setuid copy bundled in the Nix store.
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
3. Verify a *setuid* `fusermount3` is reachable via the service's PATH (not
   the non-setuid Nix-store copy). On non-NixOS it is usually
   `/bin/fusermount3` or `/usr/bin/fusermount3`:

   ```bash
   ls -l /bin/fusermount3 /usr/bin/fusermount3 2>/dev/null
   stat -c '%a %U' /bin/fusermount3   # expect setuid, e.g. 4755 root
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

That is usually all that is needed: the `rclone` module's service PATH already
includes `/bin:/usr/bin`, so it finds the system helper (e.g.
`/bin/fusermount3`) directly. Do **not** create a
`/run/wrappers/bin/fusermount3` symlink for this — `/run` is a tmpfs, so it
would silently vanish on the next reboot and the mount would fail again.
(`/run/wrappers/bin` is a NixOS-ism that is populated automatically there; on
non-NixOS hosts the real location is `/bin` or `/usr/bin`.)

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
- a setuid `fusermount3` is reachable via the service's PATH (e.g.
  `/bin/fusermount3` or `/usr/bin/fusermount3`)

If the mount still fails rootless but works as root, prefer a system-level
mount service or a distro-provided `fusermount3` rather than relying on a
Nix-store helper.

## Home Manager guidance

- Put the mount logic in Home Manager only when the mount is genuinely a
  per-user feature.
- Keep the secret/config file in SOPS if the backend needs credentials.
- When a mount service uses `fusermount3`, resolve it via a PATH that includes
  the system helper location (`/bin`, `/usr/bin`) rather than hardcoding a
  single absolute path that only exists on NixOS, and never point it at the
  non-setuid Nix-store binary.
- If a mount needs special host setup, tell the user exactly which commands
  they must run manually; do not pretend Home Manager can perform those sudo
  steps.
- Do not overfocus on `/etc/fuse.conf`: it only affects `--allow-other`, not
  the core question of whether a rootless FUSE mount is permitted at all.

## Good wording for future tasks

If you are asked to add a userspace mount feature, remember this rule of thumb:

> For FUSE mounts on non-NixOS systems, resolve the system-provided
> `fusermount3` via PATH (it lives in `/bin` or `/usr/bin`, not
> `/run/wrappers/bin`) and verify the host FUSE environment before blaming
> Home Manager. On WSL, treat `Operation not permitted` as a host-side issue
> first and ask the user to check `/dev/fuse`, `user_allow_other`, and the real
> system mount helper.
