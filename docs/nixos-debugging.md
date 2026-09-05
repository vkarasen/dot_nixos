# NixOS debugging — headless / no-network machine playbook

Hard-won during the 2026-09 `troy` install. Written deliberately so it works
**in reverse**: the agent runs on a networked machine (laptop or workstation)
while a human sits at the keyboard of a target that may have no SSH, no
NetworkManager, no display server — just a TTY and possibly no working
networking at all.

The single most important realization: **when SSH is down, the human is your
only channel to the machine.** Everything below is about getting the most
signal through that channel, and about bringing up SSH/networking as fast as
possible so you can stop transcribing screens and start running commands.

## 0. The core channel: screen photos → vision transcription

Phone photos of the target's screen, transcribed by a **vision-capable
subagent** (the `media` agent), are the highest-bandwidth way to get terminal
state into the agent's context.

- Ask for a photo of **specific output**, never "the screen": the exact command
  (`sudo journalctl -u <unit> -b --no-pager | tail -30`, `systemctl --failed`,
  `ip -4 addr show`). A focused photo is readable; a wall of text is not.
- A vision subagent transcribes terminal text accurately, but **never trust a
  transcribed hex/base64/address/SSH-key verbatim** — one look-alike character
  is a multi-hour detour (we burned an hour on an SSH key that was
  character-identical under transcription but wrong under `md5sum`). For
  anything that must be copied byte-for-byte, get a second channel: `cat -A`,
  an md5sum cross-check, or fetch it from a canonical source (see the
  github `.keys` trick below).

## 1. Order of operations when a machine won't come up

1. **Get a shell.** A NixOS install that "fails" usually still boots to a
   working `getty` TTY — `sudo`, `nix`, and a shell all work even when 8
   services are dead. Don't reach for a reinstall.
2. **Triage: one unit or many?** `sudo systemctl --failed --no-pager`. If it's
   a *single* unit, chase it. If it's a *list* of unrelated units (dbus,
   logind, nscd, wpa_supplicant, ...), that's **one root cause** taking down
   the service layer — do not fix each unit individually.
3. **Read the actual error.** `systemctl status <unit>` and
   `journalctl -u <unit> -b --no-pager`. `journalctl` for system units needs
   sudo; non-root `systemctl status` may print "Transport endpoint is not
   connected" when dbus is down — that's a symptom of the bus being dead, not a
   separate problem.

Key signature: `Failed to spawn 'start' task: Operation not permitted` +
`Failed with result 'resources'` = a systemd **sandbox / mount-namespace**
failure (see §6), not a code bug.

## 2. Networking when NetworkManager / dbus is down

NetworkManager depends on dbus; when dbus is down, no DHCP. Bring the interface
up manually with a static address (this is how SSH gets restored):

```sh
sudo ip link set <iface> up
sudo ip addr flush dev <iface>
sudo ip addr add 192.168.x.y/24 dev <iface>
```

- Get the interface name from `ip link` (e.g. `enp0s31f6` — wired NICs are
  `en*`, wifi `wl*`).
- Type the four octets slowly — a mistyped IP is an easy self-inflicted wound.
- Once SSH is up, `sudo systemctl --failed` and `journalctl -b` are reachable.

## 3. SSH access without typing a key — the github `.keys` trick

When the target has network but you can't reliably transfer your public key
(no scp, fear of transcription typos), GitHub serves your keys at a stable
URL. On the target:

```sh
curl -fsSL https://github.com/<username>.keys > ~/.ssh/authorized_keys \
  && chmod 600 ~/.ssh/authorized_keys
```

Zero manual transcription → zero typos. This is how `troy` was reached after
the install's baked-in authorized_keys had a subtle character error. (Needs
`curl` + network on the target — useless when there is genuinely no network,
which is what §2 is for.)

## 4. NixOS read-only filesystem gotchas

NixOS mounts most of `/etc` as symlinks into the read-only store. Two traps:

- **`/etc/systemd/system` is read-only** (symlink into the store). Runtime unit
  drop-ins go in **`/run/systemd/system`** (a tmpfs), not `/etc/systemd/system`:
  ```sh
  sudo mkdir -p /run/systemd/system/<unit>.service.d
  sudo tee /run/systemd/system/<unit>.service.d/override.conf >/dev/null <<'EOF'
  [Service]
  PrivateTmp=no
  EOF
  sudo systemctl daemon-reload
  ```
  `/run` overrides vanish on reboot (by design).
- **`/etc/nix/nix.conf` is a symlink** to a store path. To test a change
  without a rebuild, replace the symlink with a real file (last occurrence of a
  key wins), then restart `nix-daemon`. The proper fix is `nix.settings` in
  config.

## 5. Passwordless sudo for remote automation (temporary)

Remote deploys (`nixos-rebuild ... --target-host ... --use-remote-sudo`) and
remote debugging need NOPASSWD sudo, but every activation regenerates
`/etc/sudoers` and wipes it. Re-establish without an interactive prompt:

```sh
echo '<bootstrap-password>' | sudo -S sh -c \
  'echo "vkarasen ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers'
```

This append works because `security.sudo.extraConfig` generates `/etc/sudoers`
as a **real file** here — but on a pure-default NixOS it can be a read-only
store symlink, so check `ls -l /etc/sudoers` first. A cleaner alternative that
skips NOPASSWD entirely: SSH in as **root** (`--target-host root@<ip>`) when
root login is enabled.

Re-run the NOPASSWD line after every reboot/deploy that needs remote root.
(Don't forget to verify it actually took — a `sudo -n true` that passes because
of a cached credential is a false positive.)

## 6. Sandbox failures — "Failed to spawn … Operation not permitted"

systemd's sandbox directives (`ProtectSystem=`, `ProtectHome=`, `PrivateTmp=`,
`PrivateDevices=`, `NoNewPrivileges=`, …) can fail against a specific
filesystem state, producing the §1 spawn signature. When you suspect one:

1. **Confirm by disabling the sandbox** via a `/run/systemd/system` drop-in
   (§4) and try to start the unit. If it starts sandbox-free, the sandbox is
   the trigger.
2. **Bisect individual directives** with `systemd-run` (needs dbus up):
   ```sh
   sudo systemd-run --wait --pipe -p PrivateTmp=yes /run/current-system/sw/bin/echo hi
   ```
   Note: `/bin/echo` does **not** exist on NixOS — use
   `/run/current-system/sw/bin/echo` or `true`. A failed directive shows
   "Finished with result: resources" and the command never runs (CPU time 0).
   Test directives one at a time and in combination — `PrivateTmp` + any other
   mount-namespace directive can fail while each alone passes.

## 7. The btrfs + PrivateTmp gotcha (the `troy` root cause)

Symptom: after an erase-on-boot rollback re-snapshots the root from a
**read-only** `root-blank` snapshot, *every* sandboxed service fails to spawn
with `EPERM`, even though root is mounted `rw`.

Root cause: `/tmp` and `/var/tmp` remain **COW-shared with the read-only
`root-blank`** after the re-snapshot, and systemd's `PrivateTmp` tmpfs mount
over them fails. The rollback must recreate them fresh to break the sharing:

```sh
rm -rf /mnt/root/tmp /mnt/root/var/tmp
mkdir -m 1777 /mnt/root/tmp /mnt/root/var/tmp
```

Debugging path that found it: sandbox drop-in starts the unit → `systemd-run`
bisection isolates `PrivateTmp=yes` → manual `mount -t tmpfs` works but
`PrivateTmp` doesn't (systemd's new-mount-API path differs) → recreating
`/tmp`/`/var/tmp` fresh fixes it. If a wipe-then-restore rollback breaks
*sandboxed* services on btrfs, check COW-sharing with the source snapshot first.

## 8. Deterministic vs. generation-specific failures

To tell whether a failure is a config change or an environmental/boot issue,
reboot and pick the **previous generation** from the systemd-boot menu. If
*both* generations fail identically, it is not a config regression — look at
what the two boots share (the wipe/rollback, a kernel issue, hardware).

## 9. LUKS passphrase

Everything above assumes you're past LUKS. Keep the passphrase in pasteable
form; the human types it at the prompt before any of this is possible. TPM
enrollment (`systemd-cryptenroll --tpm2-device=auto`) removes the prompt
entirely — do it early on a machine you'll debug remotely.
