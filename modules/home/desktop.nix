# Dendritic aspect: desktop (home-manager class) — Hyprland config + the
# Wayland desktop apps (ghostty, waybar, mako, fuzzel) + clipboard/screenshot
# tools. The compositor itself is enabled in modules/nixos/desktop.nix.
{...}: {
  flake.modules.homeManager.desktop = {
    pkgs,
    lib,
    config,
    ...
  }: let
    # ghostty bundles share/terminfo/g/ghostty, which ncurses 6.6 also ships;
    # both land in the shared home-manager buildEnv and collide. Drop ghostty's
    # duplicate g/ghostty entry and keep x/xterm-ghostty, which ncurses lacks.
    ghostty = pkgs.ghostty.overrideAttrs (old: {
      postFixup =
        old.postFixup
        + ''
          rm -f $out/share/terminfo/g/ghostty
        '';
    });

    # Grouped, searchable keybinding cheatsheet (shown in fuzzel). Reads the
    # live binds (so it can't drift), decodes the modmask, groups by the
    # "Area: …" prefix in each bind's description, and pipes it into fuzzel.
    hypr-cheatsheet = pkgs.writeShellScriptBin "hypr-cheatsheet" ''
      # Hand-curated keybinding cheatsheet, grouped into areas. Keep in sync
      # with the binds in this file (modules/home/desktop.nix).
      printf '%s\n' \
        'Launch: Terminal — SUPER+Return' \
        'Launch: App launcher — SUPER+Space' \
        'Window: Close window — SUPER+Q' \
        'Window: Toggle floating — SUPER+V' \
        'Window: Toggle fullscreen — SUPER+F' \
        'Window: Move window (drag) — SUPER+Left click' \
        'Window: Resize window (drag) — SUPER+Right click' \
        'Window: Focus window (vim) — SUPER+h/j/k/l' \
        'Window: Move window in layout — SUPER+Shift+h/j/k/l' \
        'Window: Swap window — SUPER+Ctrl+h/j/k/l' \
        'Window: Window switcher (alt-tab) — SUPER+Tab' \
        'Workspace: Go to workspace 1 — SUPER+1' \
        'Workspace: Go to workspace 2 — SUPER+2' \
        'Workspace: Go to workspace 3 — SUPER+3' \
        'Workspace: Go to workspace 4 — SUPER+4' \
        'Workspace: Go to workspace 5 — SUPER+5' \
        'Workspace: Send window to workspace — SUPER+Shift+1..5' \
        'Monitor: Focus monitor left/right — SUPER+Alt+h/l' \
        'Monitor: Move workspace to monitor — SUPER+Alt+Shift+h/l' \
        'Media: Mute audio — Mute key' \
        'Media: Volume down — Volume down key' \
        'Media: Volume up — Volume up key' \
        'Media: Mute microphone — Mic mute key' \
        'Media: Brightness down — Brightness down key' \
        'Media: Brightness up — Brightness up key' \
        'Screenshot: Region — PrtSc' \
        'Screenshot: Fullscreen — Shift+PrtSc' \
        'Screenshot: Active window — Alt+PrtSc' \
        'System: Lock screen — SUPER+L' \
        'System: Exit Hyprland — SUPER+M' \
        'Help: Show keybindings — SUPER+/' \
      | fuzzel --dmenu --prompt 'Keys ' --width 70 --lines 40
    '';

    # Screenshot helper: captures the fullscreen or the active window,
    # saves a timestamped PNG to ~/Pictures/screenshots, and copies it to the
    # clipboard. Every tool it calls is pinned via runtimeInputs, so the
    # script is self-contained regardless of the ambient PATH.
    screenshot = pkgs.writeShellApplication {
      name = "screenshot";
      runtimeInputs = with pkgs; [
        grim # capture
        jq # parse `hyprctl -j activewindow`
        hyprland # hyprctl
        wl-clipboard # wl-copy
        libnotify # notify-send
        coreutils # date, mkdir
      ];
      text = ''
        dir="$HOME/Pictures/screenshots"
        mkdir -p "$dir"
        out="$dir/$(date +%Y%m%d-%H%M%S).png"
        case "''${1:-}" in
          screen) grim "$out" ;;
          window) grim -g "$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" "$out" ;;
          *) echo "usage: screenshot {screen|window}" >&2; exit 1 ;;
        esac
        wl-copy "$out"
        notify-send -a screenshot -i "$out" "Screenshot" "Copied to clipboard"
      '';
    };
  in {
    # Importing this aspect IS the GUI statement: derive the flag that
    # consumers (e.g. the pi GUI-vs-TUI context) read. NOTE: an aspect that
    # defines a my.* option must never be consumed by a standalone wrapped
    # package (repo AGENTS.md pitfall #6) — this one isn't.
    config = {
      my.gui.enable = true;
      home.packages = with pkgs; [
        grim # screenshots
        brightnessctl # screen/keyboard backlight for the Fn keys
        hypr-cheatsheet # SUPER+/ keybinding cheatsheet
        screenshot # Shift+PrtSc = fullscreen, Alt+PrtSc = window (region is Flameshot)
        flameshot # PrtSc = interactive region (drag + adjust + Enter)
      ];

      # Stylix owns the per-user DE chrome; its targets for these apps are
      # enabled on the NixOS side (modules/nixos/stylix.nix), not here — this
      # shared home aspect must never reference `stylix`, so the standalone
      # TUI-only config stays free of the Stylix home module. The
      # terminal/CLI layer (ghostty, bat, nvim, …) is left to catppuccin-nix.

      # Lock screen structure (Stylix's hyprlock target supplies the
      # background image + input-field colours).
      programs.hyprlock = {
        enable = true;
        settings = {
          general = {
            hide_cursor = true;
            grace = 5;
          };
          input-field = {
            monitor = "";
            size = "250, 50";
            outline_thickness = 2;
            dots_size = 0.2;
            dots_spacing = 0.15;
            dots_center = true;
            placeholder_text = "Password";
            position = "0, -40";
            halign = "center";
            valign = "center";
          };
          label = [
            {
              monitor = "";
              text = "cmd[update:1000] echo $(date +%H:%M)";
              font_size = 64;
              position = "0, 60";
              halign = "center";
              valign = "center";
            }
          ];
        };
      };

      # Auto-start Hyprland on the first TTY login (minimal, no display
      # manager). `start-hyprland` is the NixOS module wrapper that sets up the
      # Wayland environment; quitting Hyprland returns to the login prompt.
      programs.bash.profileExtra = ''
        if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
          exec start-hyprland
        fi
      '';

      programs = {
        ghostty = {
          enable = true;
          package = ghostty;
          settings = {
            theme = "catppuccin-mocha"; # built-in theme
            font-family = "NotoMono Nerd Font Mono";
            font-size = 11;
            window-padding-x = 8;
            window-padding-y = 4;
            cursor-style = "bar";
            gtk-titlebar = false; # minimal: no window chrome
            confirm-close-surface = false;
          };
        };

        fuzzel = {
          enable = true;
          settings = {
            main = {
              terminal = "${ghostty}/bin/ghostty";
              layer = "overlay";
              width = 50;
              lines = 12;
              prompt = "❯ ";
              # Colours + font are injected by Stylix's fuzzel target.
            };
          };
        };

        waybar = {
          enable = true;
          settings = {
            mainBar = {
              layer = "top";
              position = "top";
              height = 32;
              spacing = 4;
              modules-left = ["hyprland/workspaces"];
              modules-center = ["clock"];
              # `battery` is laptop-only: in modules-right only when
              # my.laptop.enable is true (set by modules/home/laptop.nix).
              modules-right =
                ["network" "pulseaudio"]
                ++ lib.optional config.my.laptop.enable "custom/battery-exception"
                ++ lib.optional config.my.laptop.enable "custom/suspend-exception"
                ++ lib.optional config.my.laptop.enable "custom/power-profile"
                ++ lib.optional config.my.laptop.enable "battery"
                ++ ["tray"];

              "hyprland/workspaces" = {
                format = "{name}";
                on-click = "activate";
              };

              clock = {
                format = "{:%a %d %b  %H:%M}";
                tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
              };

              network = {
                format-wifi = " {essid}";
                format-ethernet = " {ifname}";
                format-disconnected = " disconnected";
                tooltip-format = "{ifname}: {ipaddr}";
              };

              pulseaudio = {
                format = "{icon} {volume}%";
                format-muted = " muted";
                format-icons = [" " " "];
                on-click = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
              };

              battery = {
                format = "{icon} {capacity}%";
                format-icons = [" " " " " " " " " "];
                states = {
                  warning = 30;
                  critical = 15;
                };
                format-warning = "{icon} {capacity}%";
                format-critical = "{icon} {capacity}%";
              };

              # Glowing marker when battery "exception mode" (charge-to-full)
              # is armed — see modules/nixos/laptop.nix + modules/home/laptop.nix.
              "custom/battery-exception" = {
                exec = "battery-exception-status";
                interval = 2;
                return-type = "json";
                hide-empty-text = true;
              };

              # Suspend widget (Fn10 exception + idle-suspend countdown) — see
              # modules/home/laptop.nix. Always present: shows a dim "-:--"
              # placeholder when idle-suspend isn't counting, so the bar
              # layout doesn't shift. Ticks once a second.
              "custom/suspend-exception" = {
                exec = "suspend-exception-status";
                interval = 1;
                return-type = "json";
              };

              # Power-profile switch (power-profiles-daemon): click opens a
              # fuzzel menu to select the profile directly; scroll steps up/down.
              # Backed by the power-profile-* scripts in modules/home/laptop.nix
              # and ppd + the AC hook in modules/nixos/laptop.nix.
              "custom/power-profile" = {
                exec = "power-profile-status";
                interval = 5;
                return-type = "json";
                on-click = "power-profile-select";
                on-scroll-up = "power-profile-step up";
                on-scroll-down = "power-profile-step down";
              };

              tray = {
                spacing = 8;
              };
            };
          };
          style = ''
            /* Catppuccin mocha */
            * {
              font-family: "NotoMono Nerd Font Mono";
              font-size: 12px;
              border: none;
              border-radius: 0;
              min-height: 0;
            }

            window#waybar {
              background: rgba(30, 30, 46, 0.85);
              color: #cdd6f4;
            }

            #workspaces button {
              color: #6c7086;
              padding: 0 6px;
            }
            #workspaces button.active { color: #89b4fa; }
            #workspaces button.urgent { color: #f38ba8; }

            #clock {
              color: #a6adc8;
              font-weight: bold;
            }

            #network,
            #pulseaudio,
            #battery,
            #custom-power-profile,
            #tray {
              padding: 0 8px;
              color: #bac2de;
            }

            #battery.warning { color: #f9e2af; }
            #battery.critical { color: #f38ba8; }

            /* Battery exception-mode indicator (glows orange while armed).
               The module is hidden (hide-empty-text) when the flag is off. */
            #custom-battery-exception.exception {
              color: #fab387;
              font-weight: bold;
              text-shadow: 0 0 8px #fab387;
              padding: 0 0 0 6px;
            }

            /* Suspend widget: a dim "-:--" placeholder by default (keeps the
               bar layout stable), an orange moon while the exception is armed,
               and a blue countdown while idle-suspend ticks down. */
            #custom-suspend-exception {
              color: #a6adc8;
              padding: 0 0 0 6px;
            }
            #custom-suspend-exception.exception {
              color: #fab387;
              font-weight: bold;
              text-shadow: 0 0 8px #fab387;
            }
            #custom-suspend-exception.counting {
              color: #89b4fa;
              font-weight: bold;
            }

            /* Power profile: green = saving, yellow = balanced, red = performance.
               Slightly larger glyph so the state is readable at a glance. */
            #custom-power-profile { font-size: 14px; }
            #custom-power-profile.powersave   { color: #a6e3a1; }
            #custom-power-profile.balanced    { color: #f9e2af; }
            #custom-power-profile.performance { color: #f38ba8; }
          '';
        };
      };

      services.mako = {
        enable = true;
        settings = {
          anchor = "top-right";
          default-timeout = 5000;
          border-radius = 8;
          width = 400;
          margin = 10;
          padding = 10;
          # Colours + font are injected by Stylix's mako target.
        };
      };

      # hyprshell (formerly hyprswitch): GTK4 recent-window switcher, the
      # alt-tab replacement. The daemon runs as a systemd user service;
      # settings are rendered to ~/.config/hyprshell/config.json. Hold SUPER,
      # tap Tab to cycle windows, release to close. switch.filter_by defaults
      # to the current monitor — set [] for all monitors.
      services.hyprshell = {
        enable = true;
        settings = {
          version = 4;
          windows = {
            switch = {
              modifier = "super";
              key = "Tab";
            };
          };
        };
      };

      # Screenshot retention watchdog: a daily timer deletes screenshots older
      # than 30 days, so ~/Pictures/screenshots can't grow unbounded. The
      # leading `-` on ExecStart ignores find's exit code (e.g. before the
      # first screenshot has created the directory).
      systemd.user.services.screenshot-cleanup = {
        Unit.Description = "Remove screenshots older than 30 days";
        Service = {
          Type = "oneshot";
          ExecStart = "-${pkgs.findutils}/bin/find ${config.home.homeDirectory}/Pictures/screenshots -type f -mtime +30 -delete";
        };
      };
      systemd.user.timers.screenshot-cleanup = {
        Unit.Description = "Run screenshot cleanup daily";
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };

      wayland.windowManager.hyprland = {
        enable = true;
        # stateVersion 26.05 defaults configType to "lua"; the settings below
        # are written against the Lua (hl.*) API.
        # NOTE: monitor layout is intentionally left to auto-detection for the
        # first slice. Clamshell handling (disable eDP when the lid is closed
        # and only the Thunderbolt LG is connected) is a follow-up.
        settings = {
          # Lua locals — rendered as `local name = value`, referenced below.
          mod = {_var = "SUPER";};
          terminal = {_var = "ghostty";};
          launcher = {_var = "fuzzel";};

          # Options — rendered as hl.config({ ... }). The border colours are
          # explicit rgba (catppuccin also injects a `colors` table via its
          # themes/*.lua, available here as `colors.*` if we switch later).
          config = {
            general = {
              gaps_in = 2;
              gaps_out = 5;
              border_size = 2;
              col = {
                active_border = "rgba(89b4faee)";
                inactive_border = "rgba(313244ee)";
              };
              layout = "dwindle";
            };
            decoration = {
              rounding = 8;
              blur = {
                enabled = true;
                size = 3;
                passes = 1;
              };
            };
            input = {
              kb_layout = "us";
              kb_options = "caps:escape";
              follow_mouse = 1;
              touchpad.natural_scroll = true;
            };
            # Wake a DPMS-off panel on any key press or mouse movement, so the
            # Fn9 screen-off toggle (modules/hosts/troy.nix) never traps the
            # display in a state only Fn9 can undo.
            misc = {
              key_press_enables_dpms = true;
              mouse_move_enables_dpms = true;
            };
            dwindle = {
              preserve_split = true;
            };
            # Suppress the "Hyprland was updated" popup + the donation nag.
            ecosystem = {
              no_update_news = true;
              no_donation_nag = true;
            };
          };

          # Environment variables — rendered as hl.env("VAR", "value").
          env = [
            {_args = ["XCURSOR_SIZE" "24"];}
            {_args = ["XDG_CURRENT_DESKTOP" "Hyprland"];}
            {_args = ["XDG_SESSION_TYPE" "wayland"];}
            {_args = ["XDG_SESSION_DESKTOP" "Hyprland"];}
          ];

          # Run once Hyprland is up — rendered as hl.on("hyprland.start", …).
          on = {
            _args = [
              "hyprland.start"
              (lib.generators.mkLuaInline ''
                function()
                  hl.exec_cmd("waybar")
                  hl.exec_cmd("mako")
                end
              '')
            ];
          };

          # Keybinds — rendered as hl.bind(...).
          bind = [
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + RETURN"'')
                (lib.generators.mkLuaInline "hl.dsp.exec_cmd(terminal)")
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SPACE"'')
                (lib.generators.mkLuaInline "hl.dsp.exec_cmd(launcher)")
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + Q"'')
                (lib.generators.mkLuaInline "hl.dsp.window.close()")
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + V"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.float({ action = "toggle" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + F"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.fullscreen({ action = "toggle" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + M"'')
                (lib.generators.mkLuaInline "hl.dsp.exit()")
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + L"'')
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("hyprlock")'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + slash"'')
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("hypr-cheatsheet")'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + 1"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ workspace = "1" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + 2"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ workspace = "2" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + 3"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ workspace = "3" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + 4"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ workspace = "4" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + 5"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ workspace = "5" })'')
              ];
            }

            # Window focus (vim-style): move focus between windows on the
            # focused workspace. SUPER + h/j/k/l = left/down/up/right.
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + h"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "l" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + j"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "d" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + k"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "u" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + l"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "r" })'')
              ];
            }

            # Move the active window within the layout (dwindle).
            # SUPER + SHIFT + h/j/k/l.
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + h"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ direction = "l" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + j"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ direction = "d" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + k"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ direction = "u" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + l"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ direction = "r" })'')
              ];
            }

            # Swap the active window with its neighbour. SUPER + CTRL + h/j/k/l.
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + CTRL + h"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.swap({ direction = "l" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + CTRL + j"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.swap({ direction = "d" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + CTRL + k"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.swap({ direction = "u" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + CTRL + l"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.swap({ direction = "r" })'')
              ];
            }

            # Send the active window to workspace N without following (silent).
            # SUPER + SHIFT + 1..5. Drop `follow = false` to follow the window.
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + 1"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ workspace = "1", follow = false })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + 2"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ workspace = "2", follow = false })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + 3"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ workspace = "3", follow = false })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + 4"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ workspace = "4", follow = false })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + SHIFT + 5"'')
                (lib.generators.mkLuaInline ''hl.dsp.window.move({ workspace = "5", follow = false })'')
              ];
            }

            # Monitor navigation — relative l/r selectors work docked or
            # undocked, no hardcoded names. SUPER + ALT + h/l focuses the
            # monitor; + SHIFT moves the current workspace to that monitor.
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + ALT + h"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + ALT + l"'')
                (lib.generators.mkLuaInline ''hl.dsp.focus({ monitor = "r" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + ALT + SHIFT + h"'')
                (lib.generators.mkLuaInline ''hl.dsp.workspace.move({ monitor = "l" })'')
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + ALT + SHIFT + l"'')
                (lib.generators.mkLuaInline ''hl.dsp.workspace.move({ monitor = "r" })'')
              ];
            }

            # Screenshots: PrtSc = region (Flameshot: drag, adjust, Enter to capture),
            # Shift+PrtSc = fullscreen, Alt+PrtSc = active window.
            {
              _args = [
                "Print"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("flameshot gui --clipboard --path $HOME/Pictures/screenshots")'')
              ];
            }
            {
              _args = [
                "SHIFT + Print"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("screenshot screen")'')
              ];
            }
            {
              _args = [
                "ALT + Print"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("screenshot window")'')
              ];
            }

            # Fn / media keys (volume + screen brightness).
            {
              _args = [
                "XF86AudioMute"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'')
              ];
            }
            {
              _args = [
                "XF86AudioLowerVolume"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")'')
                {repeating = true;}
              ];
            }
            {
              _args = [
                "XF86AudioRaiseVolume"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")'')
                {repeating = true;}
              ];
            }
            {
              _args = [
                "XF86AudioMicMute"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")'')
              ];
            }
            {
              _args = [
                "XF86MonBrightnessDown"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("brightnessctl set 5%-")'')
              ];
            }
            {
              _args = [
                "XF86MonBrightnessUp"
                (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("brightnessctl set 5%+")'')
              ];
            }

            # Mouse binds (move + resize the active window).
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + mouse:272"'')
                (lib.generators.mkLuaInline "hl.dsp.window.drag()")
                {mouse = true;}
              ];
            }
            {
              _args = [
                (lib.generators.mkLuaInline ''mod .. " + mouse:273"'')
                (lib.generators.mkLuaInline "hl.dsp.window.resize()")
                {mouse = true;}
              ];
            }
          ];
        };
      };
    };
  };
}
