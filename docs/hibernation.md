# Hibernation: how it is wired, and how to diagnose it

Both hosts suspend-then-hibernate (S3 first, S4 after a delay) rather than
hibernating immediately. This file is the reference for the wiring, the
diagnosis markers, and the swap-headroom rule that the `nixos.sleep` aspect
enforces. The implementing aspect is `modules/nixos/sleep.nix`.

## Wiring

- **Trigger:** a short press of the power button is
  `HandlePowerKey=suspend-then-hibernate` (`modules/nixos/desktop.nix`). On
  troy the lid-close grace timer and hypridle idle also schedule
  `systemctl suspend-then-hibernate` (`modules/nixos/laptop.nix`,
  `modules/home/laptop.nix`).
- **Swapfile:** a btrfs swapfile at `/swap/swapfile` (disko
  `swap.swapfile.size`, now parameterized as `my.disks.swapSize`; 32G default,
  64G on sarasti). The `/swap` subvolume is `nodatacow,compress=none`.
- **Resume:** `boot.resumeDevice = "/dev/mapper/cryptroot"` +
  per-host `my.boot.resumeOffset` (kernel param `resume_offset=`), because the
  swapfile lives on the LUKS-encrypted btrfs root. The initrd's
  `systemd-hibernate-resume@dev-mapper-cryptroot.service` restores the image
  after cryptsetup opens the device — which is why the erase-on-boot rollback
  service orders itself *after* hibernate-resume (a resume boot must not wipe
  the resumed root; `modules/nixos/boot.nix`).
- **Delay:** systemd's `HibernateDelaySec` — default 2h (7200s) on sarasti,
  overridden to `15min` on troy by `systemd.sleep.settings.Sleep.HibernateDelaySec`
  (`modules/nixos/laptop.nix`).
- **The smart wrapper:** `modules/nixos/sleep.nix` replaces the ExecStart of
  `systemd-suspend-then-hibernate.service` with `nixos-smart-s2h`, a wrapper
  that arms the RTC wakealarm, suspends, and on the alarm either hibernates,
  scrubs then hibernates, or plain-suspends. A FAILED `echo disk` leaves the
  machine RUNNING (exit 1 — it never re-suspends); only the "no hibernate was
  attempted" paths fall back to a plain S3 suspend with no alarm and no retry.
  It also refuses to hibernate unless the live swapfile's `resume_offset`
  matches `my.boot.resumeOffset` (see gotcha (c) below).

## Diagnosis markers

- **Per-night failure:** the line
  `Couldn't hibernate, will try to suspend again.`
  in the journal means hibernation failed and systemd's fallback re-suspended.
  This is exactly the path the smart wrapper replaces; if you still see it,
  the wrapper is not installed/active.
- **Morning success:** a successful hibernate is visible as
  `systemd-hibernate-resume` running in the initrd journal and/or a
  `PM: hibernation: resume` line from the kernel during early boot.
- **One-liners** (the wrapper's own tags):
  - `journalctl -t nixos-smart-s2h` — every arming/wake/decision/hibernate
    outcome from the smart wrapper (this covers the power-key/lid/idle path).
  - `journalctl -t nixos-sleep-marker` — the post-resume hook, which logs one
    line per wake with `action`, `swapfree_kb` and `image_size_bytes` (covers
    direct `systemctl suspend` / `systemctl hibernate`).
- Note the two tags are complementary: the wrapper path does not run through
  `systemd-sleep`, so its decisions are under `nixos-smart-s2h`; direct
  suspend/hibernate goes through `systemd-sleep`, so those wakes are under
  `nixos-sleep-marker`.

## Swap-headroom requirement

Hibernation writes an image of up to `/sys/power/image_size` bytes (on a 32 GiB
box this defaults to ~2/5 of RAM, i.e. ~12.5 GiB). The kernel refuses with
ENOSPC when free swap is smaller than the image size. Over days of uptime,
zswap fills swap slots and free swap shrinks, so the headroom gate is:

- **free swap (SwapFree kB × 1024) >= `/sys/power/image_size`** → hibernate.
- otherwise, run a guarded scrub (`swapoff /swap/swapfile && swapon
  /swap/swapfile`, explicit path — no fstab dependency) **only** when
  `MemAvailable > (SwapTotal - SwapFree) + 2 GiB`, then re-check headroom and
  hibernate; if the scrub cannot run (or fails), fall back to a plain S3
  suspend (no alarm, no retry).

That guarded scrub runs **only pre-hibernate, inside the wrapper**, and only
when free swap is below the image size and the gate is safe. There is **no
periodic timer**. Rationale: the 64 GiB swapfile's headroom is the primary
hibernation guarantee, and the pre-hibernate scrub is the safety net; a daily
scrub was deliberately removed as a redundant safety-net layer that masked the
real mechanism.

`/proc/meminfo` has `MemAvailable`, `SwapTotal` and `SwapFree`; there is no
`SwapUsed` line — it is computed as `SwapTotal - SwapFree`.

## Gotchas

- **(a) Hibernate-resume does not reset boot-id/uptime.** A hibernated machine
  resumes into the *same* boot; `journalctl -b` still shows one boot spanning
  many days, and `uptime` keeps counting. Do not treat a long uptime as "the
  host never slept".
- **(b) A successful hibernate's final "Image saving done" lines are NOT in
  the journal.** journald is frozen when the image is written, so the tail of
  the hibernate sequence never reaches disk. The journal just stops; the
  evidence of success is the *next* boot's `systemd-hibernate-resume` /
  `PM: hibernation: resume`.
- **(c) `resume_offset` goes stale if the swapfile is recreated.** The offset
  is a physical location inside the btrfs swapfile; any recreate (size change
  or reinstall) invalidates it and resume can corrupt memory. Always recompute
  with `btrfs inspect-internal map-swapfile -r /swap/swapfile` and update
  `my.boot.resumeOffset`. Two gates make this non-silent: sarasti's
  `my.disks.swapSize = "64G"` is wrapped in a `lib.warnIf` that warns on every
  evaluation while `resumeOffset` is still the old `533760`, and the smart
  wrapper refuses to hibernate whenever the live offset does not equal the
  configured one.

## Live follow-up for the 32G → 64G swapfile change (sarasti)

The option `my.disks.swapSize = "64G"` alone changes **nothing** on the live
host: disko only creates the swapfile when it does not already exist
(`lib/types/btrfs.nix`: `if ! test -e ...; then btrfs filesystem mkswapfile
--size ...; fi`), and disko does not run at boot. The resize is a manual live
step, in this order:

1. `swapoff /swap/swapfile`
2. `rm /swap/swapfile`
3. `btrfs filesystem mkswapfile --size 64G /swap/swapfile`
4. `swapon /swap/swapfile`
5. `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile` and update
   `my.boot.resumeOffset` in `modules/hosts/sarasti.nix` with the new value,
   then rebuild/switch, AND **reboot**. `resume_offset` is a kernel
   command-line parameter (`resume_offset=`), so a rebuild/switch alone does
   not change the running kernel's value; until the reboot, logind still
   compares against the stale offset, reports suspend-then-hibernate as
   "not supported", and downgrades to plain suspend.

**WARNING:** in the window between step 3 (the swapfile is actually recreated)
and the reboot that commits the new offset, the host will only SUSPEND — it
will not hibernate — and that is expected and SAFE, not broken. Two gates
enforce it: logind reports suspend-then-hibernate as "not supported" while the
configured `resume_offset` does not match the live layout and downgrades to
plain suspend, and the smart wrapper's `verify_resume_offset` gate refuses to
hibernate whenever the live offset differs from `my.boot.resumeOffset`.
Hibernation only returns after the new offset is committed, rebuilt, **and
rebooted into**. Note that the old `resume_offset=533760` addresses the old
32G file's layout and must never be resumed from — the rebuild is not enough
on its own; the reboot is what makes the new value real.

**Reinstall hazard:** the committed state (`swapSize = "64G"` + stale
`resumeOffset = 533760`) is only safe because disko does NOT recreate an
existing swapfile. A fresh `disko create` / reinstall would materialize a NEW
64G swapfile while the stale offset is still configured — the first hibernate
would then corrupt memory. The `lib.warnIf` in `modules/hosts/sarasti.nix`
keeps this visible until the offset is updated, and the wrapper's
`resume_offset` check refuses to hibernate in that state too.
