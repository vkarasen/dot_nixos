{
  description = "I am a very special flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?shallow=1&ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?shallow=1&ref=nixos-24.11";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    import-tree,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    nix-index-database,
    catppuccin,
    nixvim,
    sops-nix,
    ...
  }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      imports = [
        # Import all modules from the new modules directory
        (import-tree ./modules)
      ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # Formatter for each system
        formatter = pkgs.alejandra;

        # Standalone nixvim package
        packages.nvim = nixvim.legacyPackages.${system}.makeNixvimWithModule {
          inherit pkgs;
          module = import ./legacy-modules/nixvim;
        };
      };

      flake = {
        # Templates remain at the flake level
        templates = {
          py-venv = {
            path = ./templates/py-venv;
            description = "Python/Snakemake development environment";
          };
          latex = {
            path = ./templates/latex;
            description = "latex development template";
          };
          rust = {
            path = ./templates/rust;
            description = "rust template using naersk";
          };
          jekyll = {
            path = ./templates/jekyll;
            description = "Jekyll template";
          };
        };

        # Home Manager configuration
        homeConfigurations.vkarasen = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };

          modules = [
            # Dendritic modules
            ./modules/users/vkarasen

            # External modules
            nix-index-database.homeModules.nix-index
            catppuccin.homeModules.catppuccin
            nixvim.homeModules.nixvim
            sops-nix.homeManagerModules.sops

            # Global configuration
            ({lib, ...}: {
              programs.nix-index-database.comma.enable = true;
              nixpkgs.overlays = [
                (final: prev: {
                  stable = import nixpkgs-stable {
                    system = "x86_64-linux";
                  };
                })
              ];
              nix.registry.nixpkgs.flake = nixpkgs;
              my.is_private = lib.mkForce true;
            })
          ];
        };
      };
    };
}
