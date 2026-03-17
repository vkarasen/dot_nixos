# Home Manager configurations — composes homeModules into concrete user configs
# Exports: flake.homeConfigurations.vkarasen
{ inputs, self, ... }: {
  flake.homeConfigurations.vkarasen = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    modules = [
      # Compose from dendritic homeModules
      self.homeModules.common
      self.homeModules.git
      self.homeModules.shell
      self.homeModules.terminal
      self.homeModules.editor
      self.homeModules.security

      # External modules
      inputs.nix-index-database.homeModules.nix-index
      inputs.catppuccin.homeModules.catppuccin
      inputs.nixvim.homeModules.nixvim
      inputs.sops-nix.homeManagerModules.sops

      # Per-user overrides
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

        catppuccin = {
          enable = true;
          flavor = "mocha";
        };
      })
    ];
  };
}

