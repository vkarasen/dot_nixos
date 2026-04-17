# Aggregates the homeManager modules used by user vkarasen and exposes the
# flake.homeConfigurations.vkarasen output for `home-manager switch`.
{ inputs, self, ... }: {
  flake.homeConfigurations.vkarasen = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    modules = [
      # Compose dendritic homeManager aspects
      self.modules.homeManager.common
      self.modules.homeManager.git
      self.modules.homeManager.shell
      self.modules.homeManager.terminal
      self.modules.homeManager.editor
      self.modules.homeManager.security

      # External modules
      inputs.nix-index-database.homeModules.nix-index
      inputs.catppuccin.homeModules.catppuccin
      inputs.nixvim.homeModules.nixvim
      inputs.sops-nix.homeManagerModules.sops

      # Per-user overrides
      ({ lib, ... }: {
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

        catppuccin = {
          enable = true;
          flavor = "mocha";
        };
      })
    ];
  };
}

