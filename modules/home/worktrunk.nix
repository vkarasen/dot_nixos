# Dendritic aspect: worktrunk (home-manager class).
{inputs, ...}: {
  flake.modules.homeManager.worktrunk = let
    std = inputs.nix-std.lib;
  in
    {pkgs, ...}: let
      wtConfig = {
        worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}";
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
      };
    };
}
