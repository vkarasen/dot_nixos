{...}: {
  imports = [
    ../../options.nix
    ../../home
  ];

  programs.home-manager.enable = true;
  home.sessionPath = ["~/.nix-profile/bin"];
}
