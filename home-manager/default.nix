{...}: {
  imports = [
    ./options.nix
    ../modules/home
  ];

  programs.home-manager.enable = true;
  home.sessionPath = ["~/.nix-profile/bin"];
}
