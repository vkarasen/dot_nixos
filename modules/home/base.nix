# Base home aspect: identity, stateVersion, xdg, nix.conf, catppuccin theme.
# Merges what used to live in modules/home/default.nix and
# modules/hosts/desktop/default.nix.
{
  flake.modules.homeManager.base = {...}: {
    programs.home-manager.enable = true;

    home = {
      stateVersion = "26.05";
      username = "vkarasen";
      homeDirectory = "/home/vkarasen";
      sessionPath = ["~/.nix-profile/bin"];
    };

    xdg.enable = true;
    xdg.configFile."nix/nix.conf".text =
      #nix
      ''
        experimental-features = nix-command flakes
      '';

    catppuccin = {
      enable = true;
      flavor = "mocha";
    };
  };
}
