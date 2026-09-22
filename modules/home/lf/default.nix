# Dendritic aspect: lf (home-manager class).
{...}: {
  flake.modules.homeManager.lf = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = {
      xdg.dataFile."lf/pv.sh" = {
        executable = true;
        source = ./previewer;
      };

      xdg.dataFile."lf/clean" = {
        executable = true;
        source = ./clean;
      };

      xdg.configFile."lf/icons".source = ./icons;

      # Full previewer stack, shipped unconditionally. The runtime probe in
      # pv.sh decides what actually gets used per terminal (kitty-protocol
      # rendering when the terminal supports it, chafa-symbol / text tier
      # otherwise) and self-probes `command -v` for each tool. kitty here only
      # provides `kitten icat`, which emits/reads escape codes on /dev/tty and
      # needs no display — safe on headless / remote hosts too.
      home.packages = with pkgs; [
        chafa # unicode-symbol image fallback (works in any terminal)
        poppler-utils # pdftoppm (PDF->image) and pdftotext (text fallback)
        ffmpegthumbnailer # video thumbnails + audio album art
        mediainfo # media metadata
        libarchive # bsdtar for archive listings
        kitty # kitten icat for kitty-protocol rendering + support detection
      ];

      programs = {
        bash = {
          initExtra =
            #bash
            ''
              lfcd () {
                  # `command` is needed in case `lfcd` is aliased to `lf`.
                  #
                  # Normal quit (q) only prints the last visited directory to
                  # stdout. Quit-and-cd (Q) additionally drops a marker file,
                  # which is what actually triggers the cd here.
                  local last_dir cd_marker
                  last_dir="$(mktemp)"
                  cd_marker="$(mktemp)"
                  LF_LAST_DIR="$last_dir" LF_CD_MARKER="$cd_marker" command lf "$@"
                  if [ -s "$cd_marker" ]; then
                      local dir
                      dir="$(command cat "$last_dir")"
                      [ -d "$dir" ] && cd "$dir"
                  else
                      # `command` bypasses a `cat` alias (e.g. to `bat`).
                      command cat "$last_dir"
                      echo
                  fi
                  rm -f "$last_dir" "$cd_marker"
              }
            '';
          shellAliases = {
            lf = "lfcd";
          };
        };
        lf = {
          enable = true;
          settings = {
            preview = true;
            hidden = false;
            drawbox = true;
            icons = true;
            ignorecase = true;
            cleaner = toString config.xdg.dataFile."lf/clean".source;
          };

          # taken from https://github.com/gokcehan/lf/wiki/Integrations
          commands = {
            z = ''
              %{{
                  result="$(zoxide query --exclude "$PWD" "$@" | sed 's/\\/\\\\/g;s/"/\\"/g')"
                  lf -remote "send $id cd \"$result\""
              }}
            '';
            zi = ''
              ''${{
                result="$(zoxide query -i | sed 's/\\/\\\\/g;s/"/\\"/g')"
                lf -remote "send $id cd \"$result\""
              }}
            '';
            fzf_jump = ''
              ''${{
                    res="$(find . -maxdepth 1 | fzf --reverse --header="Jump to location")"
                    if [ -n "$res" ]; then
                      if [ -d "$res" ]; then
                        cmd="cd"
                      else
                        d="select"
                      fi
                      res="$(printf '%s' "$res" | sed 's/\\/\\\\/g;s/"/\\"/g')"
                      lf -remote "send $id $cmd \"$res\""
                  fi
              }}
            '';
            fzf_search = ''
              ''${{
                      cmd="rg --column --line-number --no-heading --color=always --smart-case"
                      fzf --ansi --disabled --layout=reverse --header="Search in files" --delimiter=: \
                              --bind="start:reload([ -n {q} ] && $cmd -- {q} || true)" \
                              --bind="change:reload([ -n {q} ] && $cmd -- {q} || true)" \
                              --bind='enter:become(lf -remote "send $id select \"''$(printf "%s" {1} | sed '\'''s/\\/\\\\/g;s/"/\\"/g'\''')\"")' \
                              --preview='bat --color=always --highlight-line={2} -- {1}'
              }}
            '';
            mkdir = ''
              ''${{
                    printf "Directory name: "
                    read DIR
                    mkdir $DIR
              	}}
            '';
            yank-path = ''
              ''${{
                    printf '%s' "$fx" | wl-copy
              }}
            '';
            mkfile = ''
                    ''${{
                          printf "File name: "
                          read FILE
              touch "$FILE"
                    	}}
            '';
            quit-cd = ''
              %{{
                  printf 1 > "$LF_CD_MARKER"
                  lf -remote "send $id quit"
              }}
            '';
          };

          previewer.source = config.xdg.dataFile."lf/pv.sh".source;
          previewer.keybinding = "i";

          keybindings = {
            "gff" = ":fzf_jump";
            "gfg" = ":fzf_search";
            "A" = "mkdir";
            "a" = "mkfile";
            "." = "set hidden!";
            "D" = "delete";
            "Y" = "yank-path";
            "Q" = "quit-cd";
          };

          extraConfig =
            # put on-cd/on-select cmd extensions here
            ''
              # Always record the last visited directory for the lfcd wrapper.
              # Plain quit (q) only prints it; quit-cd (Q) additionally cds
              # into it (see the quit-cd command and the lfcd bash function).
              cmd on-quit %{{
                  printf '%s' "$PWD" > "$LF_LAST_DIR"
              }}
              cmd on-cd &{{
                  zoxide add "$PWD"
              }}
              cmd on-cd &{{
                  fmt="$(STARSHIP_SHELL= starship prompt | sed 's/\\/\\\\/g;s/"/\\"/g')"
                  lf -remote "send $id set promptfmt \"$fmt\""
              }}
            '';
        };
      };
    };
  };
}
