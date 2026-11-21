# Dendritic aspect: hibernation hardening (NixOS class).
#
# Two pieces, all system-side:
#   1. A systemd-sleep "post" hook that writes ONE grep-able journal line per
#      wake (operation + SwapFree + /sys/power/image_size), so "did we
#      hibernate or just suspend last night" is a journalctl one-liner. The
#      smart wrapper emits the SAME tag after its own wakes, so one tag covers
#      every wake regardless of path.
#   2. A smart suspend-then-hibernate wrapper that replaces systemd's
#      "Couldn't hibernate, will try to suspend again" fallback (which wedged
#      the amdgpu GPU when swap was full) with a decision tree that NEVER
#      re-enters that retry loop. A failed hibernation leaves the machine
#      RUNNING (never re-suspends); only the safe "no hibernate attempted"
#      paths fall back to a plain S3 suspend with no alarm and no retry. When
#      free swap is below /sys/power/image_size it runs a guarded scrub before
#      hibernating.
#
# The former periodic (daily) swap scrub was deliberately REMOVED: the 64 GiB
# swapfile's headroom is the primary hibernation guarantee, and the wrapper's
# pre-hibernate scrub is the safety net. A daily timer was a redundant
# safety-net layer that masked the real mechanism.
#
# Selected by both hosts (modules/hosts/{sarasti,troy}.nix). Full rationale
# and the diagnosis markers are in docs/hibernation.md.
{lib, ...}: {
  flake.modules.nixos.sleep = {
    pkgs,
    config,
    ...
  }: let
    # (a) Post-resume journal marker. systemd-sleep runs every executable in
    # /etc/systemd/system-sleep/ with argv[1]=pre|post and argv[2]= the sleep
    # action (systemd-sleep(8)). NixOS builds systemd with
    # SYSTEM_SLEEP_PATH=/etc/systemd/system-sleep (nixpkgs
    # pkgs/os-specific/linux/systemd/default.nix:615), so environment.etc is
    # the supported way to install a hook (same mechanism as the nixpkgs
    # fw-fanctrl module).
    markerScript = pkgs.writeShellScript "nixos-sleep-marker" ''
      set -euo pipefail
      export PATH="${lib.makeBinPath (with pkgs; [gawk util-linux])}"

      phase="''${1:-}"
      action="''${2:-}"

      if [ "$phase" != "post" ]; then
        exit 0
      fi

      swap_free=$(awk '$1 == "SwapFree:" { print $2 + 0; found = 1; exit } END { if (!found) print 0 }' /proc/meminfo 2>/dev/null || echo 0)

      image_size=""
      read -r image_size < /sys/power/image_size 2>/dev/null || true
      [ -n "$image_size" ] || image_size=0

      sub_action=$(awk 'BEGIN { print ENVIRON["SYSTEMD_SLEEP_ACTION"] }')

      logger -t nixos-sleep-marker "post action=$action sub_action=$sub_action swapfree_kb=$swap_free image_size_bytes=$image_size"
    '';

    # (b) Guarded swap scrub of the hibernation swapfile. Invoked ONLY by the
    # smart wrapper's pre-hibernate path (the `$SCRUB` call below) — there is
    # no periodic timer anymore. Turning swap off pages every swapped page
    # back in, so only do it when MemAvailable exceeds the amount that must
    # come back (SwapTotal - SwapFree, i.e. swap in use — /proc/meminfo has no
    # SwapUsed line) plus 2 GiB of headroom.
    # The whole body runs under flock(/run/nixos-swap-scrub.lock), the same
    # lock the smart wrapper takes across its decide→hibernate region.
    #
    # Exit code: 0 on both "scrubbed" and "safely skipped" (a skip is not a
    # failure); non-zero only when swapoff/swapon really failed. The wrapper
    # does NOT use the exit code to decide whether to hibernate — it re-reads
    # SwapFree afterwards.
    scrubScript = pkgs.writeShellScript "nixos-swap-scrub" ''
      set -euo pipefail
      export PATH="${lib.makeBinPath (with pkgs; [gawk util-linux])}"

      TAG=nixos-swap-scrub
      SWAPFILE=/swap/swapfile
      LOCKFILE=/run/nixos-swap-scrub.lock
      HEADROOM_KB=2097152 # 2 GiB, in kB

      log() {
        logger -t "$TAG" "$*" 2>/dev/null || true
      }

      meminfo_kb() {
        awk -v k="$1" '$1 == k ":" { print $2 + 0; found = 1; exit } END { if (!found) print 0 }' /proc/meminfo 2>/dev/null || echo 0
      }

      exec 9>"$LOCKFILE"
      flock 9

      mem_available=$(meminfo_kb MemAvailable)
      swap_total=$(meminfo_kb SwapTotal)
      swap_free=$(meminfo_kb SwapFree)
      swap_used=$(( swap_total - swap_free ))
      need_kb=$(( swap_used + HEADROOM_KB ))

      log "check: MemAvailable=$mem_available SwapTotal=$swap_total SwapFree=$swap_free SwapUsed=$swap_used need_gt=$need_kb"

      if [ "$mem_available" -le "$need_kb" ]; then
        log "skip: MemAvailable ($mem_available kB) is not > SwapUsed ($swap_used kB) + 2GiB ($HEADROOM_KB kB)"
        exit 0
      fi

      # Disable only the hibernation swapfile (explicit path, not fstab), then
      # re-enable it explicitly so the scrub never depends on a fstab entry.
      if awk -v p="$SWAPFILE" '$1 == p { found = 1 } END { exit (found ? 0 : 1) }' /proc/swaps; then
        if ! swapoff "$SWAPFILE"; then
          log "FAILED: swapoff $SWAPFILE (still active; cannot scrub)"
          exit 1
        fi
      else
        log "note: $SWAPFILE not active; no swapoff needed"
      fi

      if ! swapon "$SWAPFILE"; then
        # Recovery: fall back to re-enabling everything in fstab (disko
        # registers the swapfile there via swapDevices), then give up loudly.
        log "WARNING: swapon $SWAPFILE failed; trying swapon --all"
        if ! swapon --all; then
          log "FAILED: swapon --all (swap left OFF)"
          exit 1
        fi
        log "recovered via swapon --all"
      fi
      log "scrub complete"
      exit 0
    '';

    # (c) Smart suspend-then-hibernate wrapper. Replaces the ExecStart of the
    # upstream systemd-suspend-then-hibernate.service (which is
    # `systemd-sleep suspend-then-hibernate` and falls back to re-suspending
    # when hibernation fails — systemd src/sleep/sleep.c execute_s2h). This
    # wrapper arms the RTC wakealarm, S3-suspends, and on the alarm decides
    # hibernate vs guarded-scrub-then-hibernate vs plain suspend. A FAILED
    # `echo disk` returns 1 and leaves the machine running — it never echoes
    # `mem` again, because that is the exact retry loop that wedged the GPU.
    # The decide→scrub→hibernate region is serialized against the scrub
    # script with flock(/run/nixos-swap-scrub.lock).
    smartS2hScript = pkgs.writeShellScript "nixos-smart-s2h" ''
      set -euo pipefail
      export PATH="${lib.makeBinPath (with pkgs; [coreutils util-linux gawk])}"

      TAG=nixos-smart-s2h
      WAKEALARM=/sys/class/rtc/rtc0/wakealarm
      STATE=/sys/power/state
      IMAGE_SIZE_FILE=/sys/power/image_size
      MEMINFO=/proc/meminfo
      SWAPFILE=/swap/swapfile
      LOCKFILE=/run/nixos-swap-scrub.lock
      BTRFS=${pkgs.btrfs-progs}/bin/btrfs
      EXPECTED_RESUME_OFFSET=${toString config.my.boot.resumeOffset}
      # systemd 262's compiled default for no-battery hosts is 2h
      # (src/sleep/sleep.c: DEFAULT_HIBERNATE_DELAY_USEC_NO_BATTERY =
      # 2 * USEC_PER_HOUR), matching systemd-sleep.conf(5) "defaults to 2h".
      DEFAULT_DELAY_SECS=7200
      SCRUB=${scrubScript}

      log() {
        logger -t "$TAG" "$*" 2>/dev/null || true
      }

      meminfo_kb() {
        awk -v k="$1" '$1 == k ":" { print $2 + 0; found = 1; exit } END { if (!found) print 0 }' "$MEMINFO" 2>/dev/null || echo 0
      }

      # Emit the same one-line-per-wake marker the systemd-sleep hook emits,
      # so journalctl -t nixos-sleep-marker covers the wrapper's wakes too.
      mark_wake() {
        local sub_action="$1"
        local swap_free_kb image_size_b
        swap_free_kb=$(meminfo_kb SwapFree)
        image_size_b=""
        read -r image_size_b < "$IMAGE_SIZE_FILE" 2>/dev/null || true
        image_size_b=$(printf '%s' "$image_size_b" | awk 'NF { print $1 + 0; exit }')
        logger -t nixos-sleep-marker "post action=suspend-then-hibernate sub_action=$sub_action swapfree_kb=$swap_free_kb image_size_bytes=$image_size_b"
      }

      # systemd reads /etc/systemd/sleep.conf then /etc/systemd/sleep.conf.d/*.conf
      # in lexical order (later files win). Parse the last uncommented
      # HibernateDelaySec and convert the systemd time span (e.g. "15min", "2h",
      # "7200") to whole seconds. Default 7200 (2h) per systemd-sleep.conf(5).
      read_hibernate_delay_secs() {
        local spec=""
        local v
        local f
        for f in /etc/systemd/sleep.conf /etc/systemd/sleep.conf.d/*.conf; do
          [ -r "$f" ] || continue
          v=$(awk '
            {
              line = $0
              sub(/[#;].*$/, "", line)
              if (line ~ /^[[:space:]]*HibernateDelaySec[[:space:]]*=/ ) {
                value = line
                sub(/^[[:space:]]*HibernateDelaySec[[:space:]]*=[[:space:]]*/, "", value)
                sub(/[[:space:]]+$/, "", value)
                spec = value
              }
            }
            END { print spec }
          ' "$f")
          if [ -n "$v" ]; then
            spec="$v"
          fi
        done

        if [ -z "$spec" ]; then
          echo "$DEFAULT_DELAY_SECS"
          return 0
        fi

        local secs
        secs=$(awk -v spec="$spec" '
          BEGIN {
            n = split(spec, tok, /[[:space:]]+/)
            total = 0
            for (i = 1; i <= n; i++) {
              t = tok[i]
              if (t == "") continue
              if (t ~ /^[0-9]+$/) { total += t; continue }
              if (match(t, /^([0-9]+)([A-Za-z]+)$/, m)) {
                v = m[1] + 0
                u = tolower(m[2])
                if (u == "s" || u == "sec" || u == "secs") total += v
                else if (u == "m" || u == "min" || u == "mins") total += v * 60
                else if (u == "h" || u == "hr" || u == "hrs") total += v * 3600
                else if (u == "d" || u == "day" || u == "days") total += v * 86400
                else if (u == "w" || u == "week" || u == "weeks") total += v * 604800
                else { total = -1; break }
              } else { total = -1; break }
            }
            printf "%d\n", total
          }
        ')
        if [ -z "$secs" ] || [ "$secs" -lt 0 ]; then
          log "unparseable HibernateDelaySec '$spec'; using default $DEFAULT_DELAY_SECS"
          echo "$DEFAULT_DELAY_SECS"
          return 0
        fi
        echo "$secs"
      }

      # Arm the RTC one-shot wakealarm for now + delay (epoch seconds). Returns
      # the armed epoch target on stdout, or non-zero when unavailable.
      arm_alarm() {
        local delay_secs="$1"
        local now target
        if [ ! -w "$WAKEALARM" ]; then
          log "no writable $WAKEALARM; suspending without hibernation"
          return 1
        fi
        now=$(date +%s)
        target=$(( now + delay_secs ))
        if ! echo "$target" > "$WAKEALARM" 2>/dev/null; then
          log "failed to arm $WAKEALARM; suspending without hibernation"
          return 1
        fi
        echo "$target"
      }

      disarm_alarm() {
        if [ -w "$WAKEALARM" ]; then
          echo 0 > "$WAKEALARM" 2>/dev/null || log "failed to clear $WAKEALARM"
        fi
      }

      # Driver-independent alarm detection: do NOT trust wakealarm readback
      # (rtc-cmos keeps the armed epoch in its registers after a fire). The
      # alarm fired iff wall-clock now is at/after the armed target epoch.
      alarm_fired() {
        local target="$1"
        local now
        now=$(date +%s 2>/dev/null || echo 0)
        [ "$now" -ge "$target" ]
      }

      # Refuse to hibernate unless the live swapfile's resume offset matches
      # the configured my.boot.resumeOffset. This is the gate that prevents a
      # stale resume_offset (swapfile recreated/reinstalled) from corrupting
      # memory on resume. Unverifiable => refuse.
      verify_resume_offset() {
        local actual=""
        if [ -z "$EXPECTED_RESUME_OFFSET" ]; then
          log "no resume offset configured; refusing to hibernate"
          return 1
        fi
        if [ -x "$BTRFS" ]; then
          actual=$($BTRFS inspect-internal map-swapfile -r "$SWAPFILE" 2>/dev/null || true)
        fi
        actual=$(printf '%s' "$actual" | awk 'NF { print $1; exit }')
        if [ "$actual" != "$EXPECTED_RESUME_OFFSET" ]; then
          log "resume_offset mismatch: live='$actual' configured='$EXPECTED_RESUME_OFFSET' (swapfile recreated?); refusing to hibernate"
          return 1
        fi
        log "resume_offset verified: $actual"
        return 0
      }

      suspend_plain() {
        log "S3 suspend (mem)"
        if [ ! -w "$STATE" ]; then
          log "no writable $STATE"
          return 1
        fi
        echo mem > "$STATE" || { log "suspend failed"; return 1; }
      }

      hibernate_now() {
        log "hibernate (disk)"
        if [ ! -w "$STATE" ]; then
          log "no writable $STATE"
          return 1
        fi
        echo disk > "$STATE" || { log "hibernate write failed"; return 1; }
      }

      main() {
        local delay_secs alarm_target
        local swap_free_kb swap_free_b image_size_b

        delay_secs=$(read_hibernate_delay_secs)

        if ! alarm_target=$(arm_alarm "$delay_secs"); then
          log "wakealarm unavailable; plain suspend (no hibernation scheduled)"
          if ! suspend_plain; then
            log "plain suspend failed"
            return 1
          fi
          mark_wake "suspend"
          log "resumed (no hibernation was scheduled)"
          return 0
        fi

        log "armed wakealarm for +$delay_secs s (epoch $alarm_target); suspending"

        if ! suspend_plain; then
          disarm_alarm
          return 1
        fi
        mark_wake "suspend"

        if ! alarm_fired "$alarm_target"; then
          log "manual wake before the RTC alarm; clearing alarm and resuming"
          disarm_alarm
          return 0
        fi

        # The alarm target was reached (or passed). Clear any lingering RTC
        # register state before deciding what to do next.
        disarm_alarm
        log "RTC alarm target reached; deciding hibernation"

        image_size_b=""
        read -r image_size_b < "$IMAGE_SIZE_FILE" 2>/dev/null || true
        image_size_b=$(printf '%s' "$image_size_b" | awk 'NF { print $1 + 0; exit }')
        if [ -z "$image_size_b" ] || [ "$image_size_b" -le 0 ]; then
          log "image_size unreadable/0; cannot verify headroom — plain suspend (no hibernate)"
          if ! suspend_plain; then
            log "plain suspend failed"
            return 1
          fi
          mark_wake "suspend"
          return 0
        fi

        if ! verify_resume_offset; then
          log "resume_offset not verified — plain suspend (no hibernate, no retry)"
          if ! suspend_plain; then
            log "plain suspend failed"
            return 1
          fi
          mark_wake "suspend"
          return 0
        fi

        # Serialize the swap decision against the scrub script: the same lock
        # file the scrub script flocks around its swapoff→swapon.
        exec 9>"$LOCKFILE"
        flock 9

        swap_free_kb=$(meminfo_kb SwapFree)
        swap_free_b=$(( swap_free_kb * 1024 ))
        log "swapfree_kb=$swap_free_kb swapfree_bytes=$swap_free_b image_size_bytes=$image_size_b"

        if [ "$swap_free_b" -ge "$image_size_b" ]; then
          log "free swap >= image_size; hibernating"
          if hibernate_now; then
            mark_wake "hibernate"
            log "resumed from hibernation"
            return 0
          fi
          log "HIBERNATION FAILED; leaving machine running (NOT re-suspending)"
          return 1
        fi

        # Release before invoking the scrub script: it acquires the lock
        # itself, so holding it here would self-deadlock.
        flock -u 9

        log "free swap < image_size; trying guarded scrub before hibernating"
        if "$SCRUB"; then
          log "scrub returned success"
        else
          log "swap scrub FAILED (swap may be OFF); not hibernating without headroom"
        fi

        # Re-read after the scrub attempt: a successful scrub refills SwapFree
        # to ~SwapTotal; a skip leaves it unchanged (still < image_size).
        flock 9
        swap_free_kb=$(meminfo_kb SwapFree)
        swap_free_b=$(( swap_free_kb * 1024 ))
        if [ "$swap_free_b" -ge "$image_size_b" ]; then
          log "headroom OK after scrub; hibernating"
          if hibernate_now; then
            mark_wake "hibernate"
            log "resumed from hibernation"
            return 0
          fi
          log "HIBERNATION FAILED AFTER SCRUB; leaving machine running (NOT re-suspending)"
          return 1
        fi
        flock -u 9

        log "insufficient headroom (scrub skipped/failed); plain suspend (no alarm, no retry, no hibernate)"
        if ! suspend_plain; then
          log "plain suspend failed"
          return 1
        fi
        mark_wake "suspend"
        return 0
      }

      main
    '';
  in {
    # (a) Install the post-resume marker hook.
    environment.etc."systemd/system-sleep/nixos-sleep-marker".source = markerScript;

    # (b) Replace systemd's suspend-then-hibernate ExecStart with the smart
    # wrapper. `overrideStrategy = "asDropin"` renders this as a DROP-IN
    # (overrides.conf) that extends the upstream systemd-package unit, so
    # Type=oneshot, DefaultDependencies=no, Requires=sleep.target and
    # After=sleep.target are preserved. The empty first ExecStart resets the
    # upstream command list; Type is restated explicitly so the oneshot type
    # cannot silently change.
    systemd.services."systemd-suspend-then-hibernate" = {
      overrideStrategy = "asDropin";
      unitConfig.RequiresMountsFor = ["/swap"];
      serviceConfig.ExecStart = [
        "" # reset the upstream ExecStart (systemd-sleep suspend-then-hibernate)
        "${smartS2hScript}"
      ];
      serviceConfig.Type = "oneshot";
    };
  };
}
