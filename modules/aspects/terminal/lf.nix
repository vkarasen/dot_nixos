{ config, lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    lf
    zoxide
  ];

  xdg.configFile."lf/icons".source = ./icons;

  programs.lf = {
    enable = true;
    settings = {
      hidden = true;
      ignorecase = true;
      preview = true;
      drawbox = true;
      icons = true;
      mouse = true;
    };

    commands = {
      open = ''
        ''${{
          case $(file --mime-type -Lb $f) in
            text/*) lf -remote "send $id \$$EDITOR \$fx";;
            *) for f in $fx; do $OPENER $f > /dev/null 2> /dev/null & done;;
          esac
        }}
      '';

      mkdir = ''
        ''${{
          printf "Directory Name: "
          read DIR
          mkdir $DIR
        }}
      '';

      mkfile = ''
        ''${{
          printf "File Name: "
          read FILE
          $EDITOR $FILE
        }}
      '';

      sudomkfile = ''
        ''${{
          printf "File Name: "
          read FILE
          sudo $EDITOR $FILE
        }}
      '';

      setwallpaper = ''%cp "$f" ~/.config/wallpaper.jpg && feh --bg-scale "$f"'';

      fzf_jump = ''
        ''${{
          res="$(find . -maxdepth 1 | fzf --reverse --header='Jump to location' | sed 's/\\\\/\\\\\\\\/g;s/"/\\\\"/g')"
          if [ -d "$res" ] ; then
            cmd="cd"
          elif [ -f "$res" ] ; then
            cmd="select"
          else
            exit 0
          fi
          lf -remote "send $id $cmd \"$res\""
        }}
      '';

      zi = ''
        ''${{
          result="$(zoxide query -i)"
          lf -remote "send $id cd \"$result\""
        }}
      '';

      dragon = ''%${pkgs.xdragon}/bin/xdragon -a -x "$fx"'';
      cpdragon = ''%${pkgs.xdragon}/bin/xdragon -a -x "$fx"'';

      trash = ''%set -f; mv $fx ~/.trash'';

      extract = ''
        ''${{
          set -f
          case $f in
            *.tar.bz|*.tar.bz2|*.tbz|*.tbz2) tar xjvf $f;;
            *.tar.gz|*.tgz) tar xzvf $f;;
            *.tar.xz|*.txz) tar xJvf $f;;
            *.zip) unzip $f;;
            *.rar) unrar x $f;;
            *.7z) 7z x $f;;
          esac
        }}
      '';

      tar = ''
        ''${{
          set -f
          mkdir $1
          cp -r $fx $1
          tar czf $1.tar.gz $1
          rm -rf $1
        }}
      '';

      zip = ''
        ''${{
          set -f
          mkdir $1
          cp -r $fx $1
          zip -r $1.zip $1
          rm -rf $1
        }}
      '';
    };

    keybindings = {
      "\\\"" = "";
      o = "";
      c = "mkdir";
      "." = "set hidden!";
      "`" = "mark-load";
      "\\'" = "mark-load";
      "<enter>" = "open";
      y = "copy";
      x = "cut";
      enter = "open";
      g = "top";
      D = "trash";
      E = "extract";
      C = "cpdragon";
      T = "tar";
      Z = "zip";
      Y = ''copy-path'';
      A = "rename; cmd-end";
      I = "rename; cmd-home";
      i = "rename";
      a = "rename";
      B = "bulk-rename";
      b = "''$lf -remote \"send $id load-file-list\"";

      "<c-f>" = "fzf_jump";
      "<c-z>" = "zi";

      dd = "cut";
      p = "paste";
      v = "''$lf -remote \"send $id toggle-preview\"";
      V = "''$lf -remote \"send $id set ratios 1:5\"";

      # Movement
      gg = "top";
      G = "bottom";
      J = "scroll-down";
      K = "scroll-up";
      "<c-u>" = "half-up";
      "<c-d>" = "half-down";

      # Tabs
      "<c-n>" = "cmd-new-tab";
      "<c-w>" = "cmd-close-tab";
      "<a-1>" = "cmd-tab-switch 0";
      "<a-2>" = "cmd-tab-switch 1";
      "<a-3>" = "cmd-tab-switch 2";
      "<a-4>" = "cmd-tab-switch 3";
      "<a-5>" = "cmd-tab-switch 4";
      "<a-6>" = "cmd-tab-switch 5";
      "<a-7>" = "cmd-tab-switch 6";
      "<a-8>" = "cmd-tab-switch 7";
      "<a-9>" = "cmd-tab-switch 8";
    };
  };
}

