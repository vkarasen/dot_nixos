{
  system = {
    stateVersion = "24.11";
    experimentalFeatures = [ "nix-command" "flakes" ];
  };

  # Theme configuration - values used by other modules
  # Do not define catppuccin.* options here as they are not available at flake-parts level
  theme = {
    catppuccin = {
      flavor = "mocha";
    };
  };

  editor = {
    leader = ";";
    localLeader = " ";
  };
}

