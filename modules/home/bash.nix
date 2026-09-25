# Dendritic aspect: bash (home-manager class).
{...}: {
  flake.modules.homeManager.bash = {
    pkgs,
    config,
    lib,
    ...
  }: let
    bashprivate =
      if config.my.is_private
      then "eval $(ssh-agent)"
      else "";
  in {
    config = {
      home.packages = with pkgs; [
      ];

      programs = {
        bash = {
          enable = true;
          enableCompletion = true;
          historySize = 10000;
          historyControl = ["ignoreboth"];

          initExtra =
            lib.strings.concatLines
            [
              bashprivate
              #bash
              ''
                set -o vi

                bind 'set show-mode-in-prompt on'
                bind 'set vi-cmd-mode-string "\1\e[2 q\2"'
                bind 'set vi-ins-mode-string "\1\e[6 q\2"'

                eval "$(batpipe)"
                eval "$(batman --export-env)"

                eval "$(wt config shell init bash)"
              ''
              # Atuin history capture. Loaded via atuin's own bundled
              # bash-preexec (see the enableBashIntegration note above).
              ''
                eval "$(atuin init bash)"
                # Upstream intentionally leaves C-r unbound in vi-command mode (to
                # preserve redo), so C-r in normal mode falls through to readline's
                # native reverse-search-history. Bind it to atuin explicitly.
                atuin-bind -m vi-command '\C-r' atuin-search-vicmd
              ''
              # pi launcher: bootstrap a worktree before pi starts (see the
              # "20-git-workflow" policy). Bypasses the pi function, the wt
              # shell function, and the cd→z alias via command/builtin.
              # bash
              ''
                pi() {
                    # Manual suppression: -w/--no-worktree skips the worktree
                    # bootstrap and herdr relocation and runs pi in place. Runs
                    # first and strips the flag so it never reaches pi.
                    local _a args=() no_worktree=0
                    for _a in "$@"; do
                      case "$_a" in
                        -w|--no-worktree) no_worktree=1 ;;
                        *) args+=("$_a") ;;
                      esac
                    done
                    if [ "$no_worktree" = 1 ]; then command pi "''${args[@]}"; return; fi
                    # Pass-through: run pi in place for subcommands, help/version, and any
                    # invocation that is not a fresh task. $1 covers first-arg cases; the loop covers flags.
                    case "$1" in
                      install|remove|uninstall|update|list|config|auth) command pi "$@"; return ;;
                      -h|--help|-v|--version|--list-models)             command pi "$@"; return ;;
                    esac
                    local a
                    for a in "$@"; do
                      case "$a" in
                        -r|--resume|-c|--continue|--session|--session-id|--fork) command pi "$@"; return ;;
                        -p|--print|--mode|--session-dir|--no-session|--export)   command pi "$@"; return ;;
                      esac
                    done
                  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { command pi "$@"; return; }
                  local top
                  top="$(git rev-parse --show-toplevel)"
                  [ -d "$top/.git" ] || { command pi "$@"; return; }
                  local slug wt_path
                  slug="pi-$(date +%Y%m%d-%H%M%S)"
                  if ! wt_path="$(command wt switch --create "$slug" --no-cd --format json 2>/dev/null | jq -r '.path')" || [ -z "$wt_path" ]; then
                    command pi "$@"; return
                  fi
                  builtin cd "$wt_path" || { command pi "$@"; return; }
                  if [ "''${HERDR_ENV:-}" = "1" ]; then
                    local repo_root wt_open ws_id ws_ok pane_id src_ws_id src_tabs tab_id cur_json
                    # `builtin cd` above is invisible to herdr until this function
                    # returns, so herdr would otherwise infer the source repo from
                    # the stale caller cwd and open a NON-linked workspace rooted at
                    # main. Every herdr call below therefore passes an explicit
                    # --cwd (repo_root) and every target is validated as a linked
                    # workspace for THIS worktree (herdr-tab-relocate.ts enforces
                    # the complementary half of this guard: it refuses to relocate
                    # at all unless the current checkout is already a linked
                    # worktree).
                    repo_root="$(git rev-parse --path-format=absolute --git-common-dir | sed 's#/\.git/*$##')"
                    # Reuse `worktree list`'s open_workspace_id only when the
                    # worktree itself is linked (the main checkout's id is never a
                    # relocation target).
                    wt_open="$(herdr worktree list --cwd "$repo_root" 2>/dev/null | jq -r --arg p "$wt_path" '([.result.worktrees[] | select(.path == $p)] | first) // {} | if .is_linked_worktree == true then (.open_workspace_id // "") else "" end')"
                    ws_id="$wt_open"
                    # Then confirm the candidate is a LIVE linked workspace rooted
                    # at this worktree. A stale or mis-rooted mapping (a workspace
                    # that hijacked the worktree's association) is exactly the
                    # herdr-corruption class: drop it and re-mint. Do not work
                    # around it.
                    if [ -n "$ws_id" ]; then
                      ws_ok="$(herdr workspace get "$ws_id" 2>/dev/null | jq -r --arg p "$wt_path" '.result.workspace.worktree // {} | select(.is_linked_worktree == true and .checkout_path == $p) | "ok"')"
                      [ "$ws_ok" = "ok" ] || ws_id=""
                    fi
                    [ -n "$ws_id" ] || ws_id="$(herdr worktree open --cwd "$repo_root" --path "$wt_path" 2>/dev/null | jq -r '.result.workspace.workspace_id')"
                    cur_json="$(herdr pane current 2>/dev/null)"
                    pane_id="$(printf '%s' "$cur_json" | jq -r '.result.pane.pane_id // empty')"
                    src_ws_id="$(printf '%s' "$cur_json" | jq -r '.result.pane.workspace_id // empty')"
                    # Same-workspace guard: relocating a pane into the workspace it
                    # already occupies is a no-op at best and corrupts the layout
                    # at worst.
                    if [ -n "$ws_id" ] && [ -n "$pane_id" ] && [ "$ws_id" != "$src_ws_id" ]; then
                      if herdr pane move "$pane_id" --new-tab --workspace "$ws_id" --focus >/dev/null 2>&1; then
                        # Move the pi tab to the front of the workspace (cosmetic,
                        # best-effort). Re-resolve the tab id after the move — the
                        # pre-move id is stale.
                        tab_id="$(herdr pane current 2>/dev/null | jq -r '.result.pane.tab_id')"
                        [ -n "$tab_id" ] && herdr-tab-move "$tab_id" 0 >/dev/null 2>&1 || true
                        # The source workspace must never vanish: moving out of its
                        # last tab would empty it, so respawn a bare shell there
                        # (never focused).
                        if [ -n "$src_ws_id" ]; then
                          src_tabs="$(herdr workspace get "$src_ws_id" 2>/dev/null | jq -r '.result.workspace.tab_count // empty')"
                          if [ "$src_tabs" = "0" ]; then
                            herdr tab create --workspace "$src_ws_id" --no-focus >/dev/null 2>&1 || true
                          fi
                        fi
                      fi
                      herdr workspace focus "$ws_id" >/dev/null 2>&1 # pane move --focus focuses the pane but the client keeps rendering the old workspace; switch the client's view to the relocated workspace
                    fi
                  fi
                  command pi "$@"
                }
              ''
            ];

          shellAliases = {
            tw = "tw --theme catppuccin";
            cat = "bat";

            grep = "rg";

            cd = "z";

            gcd = "cd $(git rev-parse --show-toplevel 2>/dev/null)";

            #lists only directories (no files)
            ldo = "eza -lD";

            #lists only files (no directories)
            lfo = "eza -lf --color=always";

            #lists only hidden files (no directories)
            lho = "eza -dl .* --group-directories-first";

            #lists everything with directories first
            ll = "eza -al --group-directories-first";

            ls = "eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions";

            #lists everything sorted by time updated
            lt = "eza -al --sort=modified";
          };
        };

        atuin = {
          enable = true;
          # Disabled: HM's bash integration sources nixpkgs' bash-preexec
          # 0.6.0, whose __bp_install fails to strip its install string from
          # an array PROMPT_COMMAND (Bash >= 5.1), leaving `trap - DEBUG` to
          # run at every prompt and silently disabling history capture.
          # We eval `atuin init bash` manually in initExtra instead, which
          # uses atuin's own (fixed) bundled bash-preexec.
          enableBashIntegration = false;
          daemon.enable = true;
          settings = {
            auto_sync = false;
            style = "auto";
            dialect = "uk";
            # WORKAROUND: "workspace" collapses git worktrees to the main repo
            # (atuin PR #3366, since 18.14), so a worktree shows the main
            # checkout's history. "directory" (exact cwd) is the closest
            # supported filter in 18.19.0; we still want a true per-worktree
            # filter — see atuinsh/atuin#3819.
            filter_mode_shell_up_key_binding = "directory";
            keymap_mode = "auto";
            update_check = false;
            workspaces = true;
            enter_accept = true;
          };
        };

        zoxide = {
          enableBashIntegration = true;
        };

        starship = {
          enableBashIntegration = true;
          settings = {
            add_newline = false;

            # Catppuccin mocha (applied to the base prompt modules).
            directory.style = "bold #89b4fa";
            directory.truncation_length = 3;
            git_branch.style = "bold #a6e3a1";
            git_status.style = "#f38ba8";
            character = {
              success_symbol = "[❯](bold #a6e3a1)";
              error_symbol = "[❯](bold #f38ba8)";
            };
            time.style = "bold #a6adc8";

            # Custom herdr module — shows a green icon in shells outside herdr
            # whenever the herdr server is running.  Detection is socket-based
            # (the socket only exists while the server is up) so no herdr
            # subprocess is spawned on each prompt render.  Hidden inside
            # herdr panes (HERDR_ENV=1) where the context is already obvious.
            custom.herdr = {
              when = ''test -S "''${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock" && [ "$HERDR_ENV" != "1" ]'';
              symbol = "󱡃 ";
              style = "bold green";
            };

            # Custom tmux module
            custom.tmux = {
              command = "tmux list-sessions 2>/dev/null | wc -l";
              when = "test $(tmux list-sessions 2>/dev/null | wc -l) -gt 0 && test -z \"$TMUX\"";
              symbol = "󰗹 ";
              style = "bold blue";
            };

            status.disabled = false;
          };
        };
        carapace = {
          enableBashIntegration = true;
          enable = true;
        };
        eza = {
          enableBashIntegration = true;
          git = true;
        };

        direnv = {
          enableBashIntegration = true;
        };
      };
    };
  };
}
