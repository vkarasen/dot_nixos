# Dendritic aspect: desktop (home-manager class) — Hyprland config + the
# Wayland desktop apps (ghostty, waybar, mako, fuzzel) + clipboard/screenshot
# tools. The compositor itself is enabled in modules/nixos/desktop.nix.
{...}: {
  flake.modules.homeManager.desktop = {pkgs, lib, ...}: let
    # ghostty bundles share/terminfo/g/ghostty, which ncurses 6.6 also ships;
    # both land in the shared home-manager buildEnv and collide. Drop ghostty's
    # duplicate g/ghostty entry and keep x/xterm-ghostty, which ncurses lacks.
    ghostty = pkgs.ghostty.overrideAttrs (old: {
      postFixup = old.postFixup + ''
        rm -f $out/share/terminfo/g/ghostty
      '';
    });
  in {
    config = {
      # catppuccin's hyprland theming targets the Lua configType (it injects a
      # Lua-inline `colors` block + themes/*.lua); with configType "hyprlang"
      # that block is invalid, and our explicit rgba borders below already
      # carry the mocha palette, so disable the catppuccin injection.
      catppuccin.hyprland.enable = lib.mkForce false;

      home.packages = with pkgs; [
        grim # screenshots
        slurp # region selection
      ];

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
              font = "NotoMono Nerd Font Mono:size=11";
              layer = "overlay";
              width = 50;
              lines = 12;
              prompt = "❯ ";
            };
            colors = {
              background = "1e1e2edd";
              text = "cdd6f4ff";
              match = "89b4faff";
              selection = "585b70ff";
              selection-match = "89b4faff";
              selection-text = "1e1e2eff";
              border = "89b4faff";
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
          border-color = "#89b4fa";
          background-color = "#1e1e2e";
          text-color = "#cdd6f4";
          width = 400;
          margin = 10;
          padding = 10;
          font = "NotoMono Nerd Font Mono 10";
        };
      };

      wayland.windowManager.hyprland = {
        enable = true;
        # stateVersion 26.05 defaults configType to "lua"; pin "hyprlang" so
        # the settings below (written in .conf syntax) render to hyprland.conf.
        configType = "hyprlang";
        # NOTE: monitor layout is intentionally left to auto-detection for the
        # first slice. Clamshell handling (disable eDP when the lid is closed
        # and only the Thunderbolt LG is connected) is a follow-up.
        settings = {
          "$mainMod" = "SUPER";

          exec-once = [
            "waybar"
            "mako"
          ];

          env = [
            "XCURSOR_SIZE,24"
            "XDG_CURRENT_DESKTOP,Hyprland"
            "XDG_SESSION_TYPE,wayland"
            "XDG_SESSION_DESKTOP,Hyprland"
          ];

          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 2;
            "col.active_border" = "rgba(89b4faee) rgba(f5c2e7ee) 45deg";
            "col.inactive_border" = "rgba(313244ee)";
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
            pseudotile = true;
            preserve_split = true;
          };

          bind = [
            "$mainMod, Return, exec, ghostty"
            "$mainMod, Space, exec, fuzzel"
            "$mainMod, Q, killactive,"
            "$mainMod, V, togglefloating,"
            "$mainMod, F, fullscreen,"
            "$mainMod, M, exit,"
            "$mainMod, 1, workspace, 1"
            "$mainMod, 2, workspace, 2"
            "$mainMod, 3, workspace, 3"
            "$mainMod, 4, workspace, 4"
            "$mainMod, 5, workspace, 5"
          ];

          bindm = [
            "$mainMod, mouse:272, movewindow"
            "$mainMod, mouse:273, resizewindow"
          ];
        };
      };
    };
  };
}
