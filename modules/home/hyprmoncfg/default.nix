# Dendritic aspect: hyprmoncfg (home-manager class).
# Dynamic monitor profile manager for Hyprland: auto-switches layouts by
# connected hardware set and re-applies saved arrangements, including
# clamshell (lid) and undock realignment. Replaces nwg-displays.
#
# Built from upstream crmne/hyprmoncfg @ v1.19.1 because nixpkgs ships a stale
# 1.9.1. v1.19.1 handles lid/clamshell natively: the closed-lid policy no longer
# loops remove/add on troy's eDP panel, which stays DRM-connected while shut.
# Drop the derivation below once nixpkgs catches up.
{inputs, ...}: {
  flake.modules.homeManager.hyprmoncfg = {
    pkgs,
    lib,
    config,
    ...
  }: let
    hyprmoncfg = pkgs.buildGoModule {
      pname = "hyprmoncfg";
      version = "0-unstable";
      src = inputs.hyprmoncfg;
      subPackages = ["cmd/hyprmoncfg" "cmd/hyprmoncfgd"];
      proxyVendor = true;
      vendorHash = "sha256-97z4+U/SumG5sidy62SW43E+Bi6FpvJKCI6wqwXts2g=";
      # buildGoModule already injects CGO_ENABLED into `env`; the derivation-arg
      # form conflicts, so override it in `env` instead.
      env.CGO_ENABLED = "0";
      nativeBuildInputs = [pkgs.makeWrapper];
      postInstall = ''
        wrapProgram $out/bin/hyprmoncfg --prefix PATH : ${lib.makeBinPath [pkgs.hyprland]}
        wrapProgram $out/bin/hyprmoncfgd --prefix PATH : ${lib.makeBinPath [pkgs.hyprland]}
      '';
    };

    # --- LG HDR WQHD+ (38" 3840x1600@144, HDR) profile -----------------------
    # hyprmoncfg keeps profiles as JSON in $XDG_CONFIG_HOME/hyprmoncfg/profiles,
    # one file per profile named slug(<name>).json, matched to hardware by
    # lowercase make|model|serial. A loaded profile is applied verbatim and is
    # never rewritten by the daemon.
    #
    # This seed is authoritative for *calibration*: mode/refresh, scale, vrr,
    # bitdepth, cm and the sdr_* fields are overwritten from it on every switch.
    # *Arrangement* fields (x, y, transform, and mirror when set) are preserved
    # from the live profile, so layout tweaks made in the TUI survive. That
    # merge is why the activation script does the work instead of
    # home.file/xdg.configFile, which would install a store symlink on every
    # switch and clobber (and make read-only) the live file.
    #
    # The daemon does not watch profile files, so re-applying after a change is
    # handled by the hyprmoncfg-profile path unit defined next to the daemon
    # unit. The activation only writes the file when the merged result actually
    # differs from what is on disk: a no-op switch touches nothing, so no path
    # event fires and nothing flashes the output.
    # `key` is deliberately not written: it is derived from make|model|serial
    # when the profile is loaded, so the file stays readable and hand-editable.
    #
    # scale MUST be a "sharp" scale: Hyprland snaps it to a 1/120 grid and only
    # keeps the value when the resulting logical width AND height are integers.
    # 0.83333 qualifies for 3840x1600 (logical 4608x1920); a non-sharp value such
    # as 0.9 gets rewritten (to 0.83333) at apply time, which hyprmoncfg's
    # ±0.02 apply-verification reads as a failure and answers by rolling the
    # whole layout back. Scale 0.83333 is sharp and is the only sharp scale
    # between 1.0 and 0.8 for this panel.
    lgHdrWqhdProfile = pkgs.writeText "hyprmoncfg-lg-hdr-wqhd-38.json" (builtins.toJSON {
      name = "lg-hdr-wqhd-38";
      created_at = "2026-10-27T00:00:00Z";
      updated_at = "2026-10-27T00:00:00Z";
      exec = "";
      outputs = [
        {
          make = "LG Electronics";
          model = "LG HDR WQHD+";
          serial = "109NTXR2N866";
          enabled = true;
          mode = "3840x1600@144.00Hz";
          width = 3840;
          height = 1600;
          refresh = 144;
          x = 0;
          y = 0;
          # scale = 0.83333;
          scale = 1.0;
          vrr = 2;
          transform = 0;
          bitdepth = 10;
          cm = "hdr";
          sdr_min_luminance = 0.2;
          # Tuned with a locked webcam against a MacBook-driven reference:
          # gamma22 gives the steeper shadow curve, and the measured
          # Mac-matched white level was 575 (575 compensates for gamma22's lower
          # white at equal sdr_max). 400 is a deliberate user preference — a
          # lower white level for dark-room use, chosen by blind A/B against
          # 575 — so it deviates from the measured value on purpose. Activation
          # merges this seed into the live profile: calibration (this value)
          # stays authoritative, arrangement (x/y/transform/mirror) is kept.
          sdr_max_luminance = 400;
          sdr_eotf = "gamma22";
        }
      ];
    });
  in {
    home.packages = [hyprmoncfg];

    # Merge the seeded calibration into the live profile (arrangement kept).
    # Re-applying it is the hyprmoncfg-profile path unit's job: the daemon does
    # not watch its profile store, and `systemctl --user` is unreachable from an
    # activation shell (no user bus / XDG_RUNTIME_DIR).
    home.activation.hyprmoncfgSeedProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
      profileDir="${config.xdg.configHome}/hyprmoncfg/profiles"
      profile="$profileDir/lg-hdr-wqhd-38.json"
      mkdir -p "$profileDir"
      jqbin="${pkgs.jq}/bin/jq"
      if [ -e "$profile" ]; then
        tmp="$profileDir/.lg-hdr-wqhd-38.merge.$$"
        if ! "$jqbin" -s '
            .[0] as $live | .[1] as $seed | $seed
            | .outputs[0].x = ($live.outputs[0].x // 0)
            | .outputs[0].y = ($live.outputs[0].y // 0)
            | .outputs[0].transform = ($live.outputs[0].transform // 0)
            | if $live.outputs[0].mirror != null
              then .outputs[0].mirror = $live.outputs[0].mirror else . end
          ' "$profile" ${lgHdrWqhdProfile} > "$tmp"; then
          rm -f "$tmp"; exit 1
        fi
        # Canonical (sorted+compact) compare: key order / whitespace-only
        # differences count as unchanged, so no spurious re-apply and flash.
        if [ "$("$jqbin" -S -c . "$tmp" 2>/dev/null)" = "$("$jqbin" -S -c . "$profile" 2>/dev/null)" ]; then
          rm -f "$tmp"
        else
          install -Dm644 "$tmp" "$profile"; rm -f "$tmp"
        fi
      else
        install -Dm644 ${lgHdrWqhdProfile} "$profile"
      fi
    '';

    # Mirrors upstream packaging/systemd/hyprmoncfgd.service.
    systemd.user.services.hyprmoncfgd = {
      Unit = {
        Description = "Hyprland monitor profile daemon (hyprmoncfgd)";
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${hyprmoncfg}/bin/hyprmoncfgd";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install = {WantedBy = ["default.target"];};
    };

    # The daemon does not watch its profile store (it re-reads only on monitor
    # hotplug/lid/power), and an activation shell cannot reach `systemctl --user`.
    # This path unit watches the LG profile file and restarts the daemon on any
    # change, so the merged seed applies immediately after `nh home switch` — and
    # so do edits made in the hyprmoncfg TUI.
    systemd.user.paths.hyprmoncfg-profile = {
      Unit.Description = "Re-apply hyprmoncfg when the LG profile changes";
      Path.PathChanged = "${config.xdg.configHome}/hyprmoncfg/profiles/lg-hdr-wqhd-38.json";
      Install.WantedBy = ["default.target"];
    };
    systemd.user.services.hyprmoncfg-profile = {
      Unit.Description = "Restart hyprmoncfgd after a profile change";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user try-restart hyprmoncfgd";
      };
    };

    # hyprmoncfg writes ~/.config/hypr/hyprmoncfg-monitors.lua and appends a
    # guarded dofile(...) line to the Hyprland root config. home-manager owns
    # that config (regenerated on switch), so we declare the include here; the
    # daemon's EnsureIncluded recognises this exact line and leaves it alone.
    # The guard means a not-yet-generated file is not a fatal load error.
    wayland.windowManager.hyprland.extraConfig = ''
      -- Added by hyprmoncfg: its generated monitor rules load last
      do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
    '';
  };
}
