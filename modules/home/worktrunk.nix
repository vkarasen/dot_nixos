# Dendritic aspect: worktrunk (home-manager class).
{...}: {
  flake.modules.homeManager.worktrunk = {
    pkgs,
    std,
    ...
  }: let
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
