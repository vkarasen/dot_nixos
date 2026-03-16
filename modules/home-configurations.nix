# Home Manager configurations
{ inputs, ... }: {
  flake.homeConfigurations.vkarasen = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    modules = [
      # User-specific configuration
      ./_home/users/vkarasen.nix

      # External modules
      inputs.nix-index-database.homeModules.nix-index
      inputs.catppuccin.homeModules.catppuccin
      inputs.nixvim.homeModules.nixvim
      inputs.sops-nix.homeManagerModules.sops

      # Global configuration
      ({lib, ...}: {
        programs.nix-index-database.comma.enable = true;
        nixpkgs.overlays = [
          (final: prev: {
            stable = import inputs.nixpkgs-stable {
              system = "x86_64-linux";
            };
          })
        ];
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
        my.is_private = lib.mkForce true;

        # Catppuccin theme configuration
        catppuccin = {
          enable = true;
          flavor = "mocha";
        };
      })
    ];
  };
}

