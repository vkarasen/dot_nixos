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
      postFixup = old.postFixup + ''
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
        'Workspace: Go to workspace 1 — SUPER+1' \
        'Workspace: Go to workspace 2 — SUPER+2' \
        'Workspace: Go to workspace 3 — SUPER+3' \
        'Workspace: Go to workspace 4 — SUPER+4' \
        'Workspace: Go to workspace 5 — SUPER+5' \
        'Media: Mute audio — Mute key' \
        'Media: Volume down — Volume down key' \
        'Media: Volume up — Volume up key' \
        'Media: Mute microphone — Mic mute key' \
        'Media: Brightness down — Brightness down key' \
        'Media: Brightness up — Brightness up key' \
        'System: Lock screen — SUPER+L' \
        'System: Exit Hyprland — SUPER+M' \
        'Help: Show keybindings — SUPER+/' \
      | fuzzel --dmenu --prompt 'Keys ' --width 70 --lines 22
    '';
  in {
    config = lib.mkIf config.my.gui.enable {
      home.packages = with pkgs; [
        grim # screenshots
        slurp # region selection
        brightnessctl # screen/keyboard backlight for the Fn keys
        hypr-cheatsheet # SUPER+/ keybinding cheatsheet
      ];

      # Stylix owns the per-user DE chrome; its targets for these apps are
      # enabled on the NixOS side (modules/nixos/stylix.nix), not here — this
      # shared home aspect must never reference `stylix`, so the standalone
      # TUI-only config stays free of the Stylix home module. The
      # terminal/CLI layer (ghostty, bat, nvim, …) is left to catppuccin-nix.

      # Idle daemon: lock right before suspend/hibernate, never on idle.
      # (No `listener` blocks => no idle auto-lock.)
      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "hyprlock";
            before_sleep_cmd = "hyprlock";
          };
        };
      };

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
              modules-right = ["network" "pulseaudio" "battery" "tray"];

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
            #tray {
              padding: 0 8px;
              color: #bac2de;
            }

            #battery.warning { color: #f9e2af; }
            #battery.critical { color: #f38ba8; }
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
              gaps_in = 5;
              gaps_out = 10;
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
