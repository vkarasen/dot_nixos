{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    xdg.dataFile."lf/pv.sh" = {
      executable = true;
      enable = true;
      text =
        #bash
        ''
          #!/usr/bin/env bash
          bat --color=always "$1"
        '';
    };

    xdg.configFile."lf/icons".source = ./icons;

    programs = {
      bash = {
        initExtra =
          #bash
          ''
            lfcd () {
                # `command` is needed in case `lfcd` is aliased to `lf`
                cd "$(command lf -print-last-dir "$@")"
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
                  printf "File: "
                  read DIR
                  mkdir $DIR
            	}}
          '';
          mkfile = ''
                  ''${{
                        printf "File: "
                        read FILE
            touch "$FILE"
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
        };

        extraConfig =
          # put on-cd/on-select cmd extensions here
          ''
            cmd on-cd &{{
                zoxide add "$PWD"
            }}
            cmd on-select &{{
                lf -remote "send $id set statfmt \"$(eza -ld --color=always "$f" | sed 's/\\/\\\\/g;s/"/\\"/g')\""
            }}
            cmd on-cd &{{
                fmt="$(STARSHIP_SHELL= starship prompt | sed 's/\\/\\\\/g;s/"/\\"/g')"
                lf -remote "send $id set promptfmt \"$fmt\""
            }}
          '';
      };
    };
  };
}
