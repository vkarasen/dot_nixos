# Dendritic aspect: worktrunk (home-manager class).
{inputs, ...}: {
  flake.modules.homeManager.worktrunk = let
    std = inputs.nix-std.lib;
  in
    {
      pkgs,
      lib,
      config,
      ...
    }: let
      cfg = config.my.worktrunk;

      # my.worktrunk.worktreeRoot is a plain Nix string (e.g. "~/code"); a
      # leading ~ does not expand inside a quoted bash string, and baking a
      # literal ~ into a generated script trips shellcheck's SC2088 (it
      # cannot tell a match-and-strip is intentional). Expanding to $HOME at
      # Nix eval time means the emitted script never contains a literal ~ at
      # all, and reads correctly at runtime.
      expandTilde = path:
        if path == "~"
        then "$HOME"
        else if lib.hasPrefix "~/" path
        then "$HOME/" + lib.removePrefix "~/" path
        else path;

      # Herdr's own worktree root is a deliberate SIBLING of this one (never
      # the same directory, so the two creation mechanisms can't collide),
      # derived from the same shared option so they can't drift apart. Set
      # as herdr's actual config in modules/home/herdr/default.nix, and
      # re-derived here (not read back from programs.herdr.settings) so this
      # aspect doesn't need the herdr module to be imported at all.
      herdrWorktreeRoot = "${cfg.worktreeRoot}/.herdr-worktrees";

      wtConfig = {
        worktree-path = "${cfg.worktreeRoot}/.worktrees/{{ repo }}/{{ branch | sanitize }}";
      };

      # Mechanism A (backstop, see my.worktrunk.autoPrune doc in
      # modules/options.nix): discover every repo with worktrees under either
      # root, and for each repo, remove only what `wt step prune` itself
      # considers safe (identical to or already merged into the default
      # branch) AND that herdr does not currently show as open in a
      # workspace. `wt step prune` has no per-branch exclusion, so this
      # replays its own dry-run candidates individually through `wt remove`
      # instead of running it directly. Safety comes from wt itself, not this
      # script: wt remove never touches a dirty worktree without -f, which is
      # never passed here.
      autoPruneScript = pkgs.writeShellApplication {
        name = "worktrunk-autoprune";
        runtimeInputs = [pkgs.git pkgs.worktrunk pkgs.jq pkgs.herdr];
        text = ''
          # writeShellApplication's wrapper forces `set -e` before this text
          # runs; turn it back off explicitly — one repo or one candidate
          # failing (e.g. malformed JSON from an unexpected wt output) must
          # skip that item, not abort the whole scan.
          set +e -u -o pipefail

          roots=(
            "${expandTilde cfg.worktreeRoot}/.worktrees"
            "${expandTilde herdrWorktreeRoot}"
          )

          declare -A seen_repos=()
          shopt -s nullglob
          for root in "''${roots[@]}"; do
            [ -d "$root" ] || continue
            for entry in "$root"/*/*/; do
              [ -e "$entry/.git" ] || continue
              common_dir="$(git -C "$entry" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
              seen_repos["$(dirname "$common_dir")"]=1
            done
          done

          for main_repo in "''${!seen_repos[@]}"; do
            echo "worktrunk-autoprune: scanning $main_repo"

            # Fail-safe: if herdr can't be reached, we cannot tell which
            # worktrees are open, so skip this repo entirely rather than
            # assume nothing is open.
            if ! open_json="$(herdr worktree list --cwd "$main_repo" 2>&1)"; then
              echo "worktrunk-autoprune: herdr unreachable for $main_repo, skipping" >&2
              continue
            fi
            open_paths="$(echo "$open_json" | jq -r '.result.worktrees[]? | select(.open_workspace_id) | .path' 2>/dev/null || true)"

            candidates="$(wt step prune --dry-run --min-age="${cfg.autoPrune.minAge}" --format=json -C "$main_repo" 2>/dev/null)" || continue

            echo "$candidates" | jq -c '.[]?' | while read -r cand; do
              kind="$(echo "$cand" | jq -r '.kind')"
              branch="$(echo "$cand" | jq -r '.branch')"
              path="$(echo "$cand" | jq -r '.path')"

              if [ "$kind" = "worktree" ] && [ "$path" != "null" ] && echo "$open_paths" | grep -qxF "$path"; then
                echo "worktrunk-autoprune: skip $branch ($path) - open in a herdr workspace"
                continue
              fi

              echo "worktrunk-autoprune: removing $branch in $main_repo"
              wt remove "$branch" -C "$main_repo" --format=json || echo "worktrunk-autoprune: remove failed for $branch, leaving it for next run" >&2
            done
          done
        '';
      };
    in {
      config = {
        home.packages = with pkgs; [
          worktrunk
        ];
        xdg.configFile."worktrunk/config.toml" = {
          enable = true;
          text = std.serde.toTOML wtConfig;
        };

        systemd.user.services.worktrunk-autoprune = lib.mkIf cfg.autoPrune.enable {
          Unit.Description = "Discover and prune merged/empty worktrunk + herdr worktrees";
          Service = {
            Type = "oneshot";
            ExecStart = "${autoPruneScript}/bin/worktrunk-autoprune";
          };
        };

        systemd.user.timers.worktrunk-autoprune = lib.mkIf cfg.autoPrune.enable {
          Unit.Description = "Timer for worktrunk-autoprune";
          Timer = {
            OnCalendar = cfg.autoPrune.schedule;
            Persistent = true;
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    };
}
