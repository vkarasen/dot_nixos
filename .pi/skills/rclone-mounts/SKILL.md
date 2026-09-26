---
name: rclone-mounts
description: How to declare and modify rclone mount/sync/bisync targets in this config (my.rclone.mounts). Use when adding, changing, or debugging a remote-storage mount or offline sync (gdrive, nextcloud).
---

# rclone mounts (gdrive + nextcloud)

Remote storage (Google Drive, Nextcloud) is exposed as declarative
`my.rclone.mounts` targets. Each target becomes a systemd user service (mount)
or a service + timer (sync/bisync). Targets are declared in
`modules/home/rclone.nix`; the option schema lives in `modules/options.nix`.

## The three variants

| type | what it does | use for |
|------|--------------|---------|
| `mount` | lazy cached FUSE mount (sparse, LRU eviction) | everyday access — the "everything else" bucket |
| `sync` | one-way remote→local mirror | read-only offline copies (e.g. music) |
| `bisync` | two-way sync with conflict handling | files edited on both sides (vault, keepass) |

## Declaring a target

```nix
my.rclone.mounts.foo = {
  enable = true;                 # mkEnableOption defaults to FALSE — set true!
  type = "mount";                # mount | sync | bisync
  remote = "gdrive:some/path";   # rclone remote + path
  path = "/home/vkarasen/mnt/foo"; # mountpoint (mount) or local mirror (sync/bisync)
  cacheDir = null;               # mount only: override the VFS cache dir
  interval = "*:0/15";           # sync/bisync: systemd OnCalendar calendar event (not a bare time span); null = run once per session
  extraArgs = [ "--vfs-cache-mode" "full" ]; # extra rclone flags, passed verbatim
};
```

Per-machine override: attrs merge, so in a host manifest
`my.rclone.mounts.nextcloud.cacheDir = "/mnt/nextcloud-cache";` overrides just
that one field.

## Secrets

One full rclone.conf blob per remote, stored in sops: `rclone_gdrive_conf`,
`rclone_nextcloud_conf`. The sops-nix systemd user service decrypts each blob
into `~/.config/sops-nix/secrets/`; an activation step (`writeRcloneConfig`,
ordered after `sops-nix`) truncates and re-concatenates them into
`~/.config/rclone/rclone.conf`, so every target shares one config file.

To add a remote (one time):
1. Create an app password / OAuth token in the provider.
2. `rclone config create <name> <backend> ...` — rclone obscures the password
   automatically.
3. Copy the section from the FILE (not `rclone config show`, which masks
   `pass` as `*** ENCRYPTED ***`): `sed -n '/\[<name>\]/,$p' ~/.config/rclone/rclone.conf`
4. Store it in sops as `rclone_<name>_conf`.
5. `nix flake check`, then switch.

## Lifecycle

- A `mount` unit starts at login and restarts on failure; the mountpoint exists only while mounted.
- A `sync`/`bisync` unit runs immediately after every switch (`home.activation.rcloneSyncNow` starts it `--no-block`) and again on its `interval` timer.
- `bisync` self-seeds: on its first run (detected as "the local dir has no files yet") it runs with `--resync`, so the remote seeds the local copy; afterwards it runs a normal incremental bisync. Wiping the local dir re-seeds from the remote rather than erroring.
- `bisync` targets run with `--resilient --recover --max-lock 2m` so an interrupted run recovers on the next tick instead of wedging into a "requires --resync" state.

## Gotchas

- `enable` defaults to false — a target you forget to enable silently produces nothing.
- The mountpoint exists only while mounted (ExecStartPre/ExecStopPost guard).
- VFS cache: `full` mode caches lazily (sparse files); eviction is
  least-recently-accessed. The directory cache is in-memory (lost on restart);
  `--vfs-refresh` re-warms it at start.
- Mount write-back is last-write-wins (local wins) with no conflict detection —
  use `bisync` for two-way safety (`--conflict-loser` keeps both by default).
- `--poll-interval` only works on remotes that support change polling (Drive);
  WebDAV/Nextcloud ignores it.
- systemd has no HOME: the module passes absolute `--config`/`--cache-dir` paths.
