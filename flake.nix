{
  description = "I am a very special flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?shallow=1&ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?shallow=1&ref=nixos-24.11";

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

    nixai = {
      url = "github:olafkfreund/nix-ai-help";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    nix-index-database,
    catppuccin,
    nixvim,
    nixai,
    ...
  }: let
    system = "x86_64-linux";

    pkgs = nixpkgs.legacyPackages.${system};
    overlay-stable = final: prev: {
      stable = import nixpkgs-stable {
        inherit system;
      };
    };
  in rec {
    homeManagerModules = [
      ./home-manager
      nix-index-database.hmModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      catppuccin.homeModules.catppuccin
      nixvim.homeManagerModules.nixvim
      (
        {
          config,
          pkgs,
          ...
        }: {
          nixpkgs.overlays = [
            overlay-stable
          ];
          nix = {
            registry = {
              nixpkgs.flake = nixpkgs;
            };
          };
        }
      )
      nixai.homeManagerModules.${system}.default
      {
        services.nixai = {
          enable = true;
          mcp = {
            enable = true;

            # User-specific paths
            # socketPath = "$HOME/.local/share/nixai/mcp.sock";
            # host = "localhost";
            # port = 8081;

            # AI settings
            # aiProvider = "ollama";
            # aiModel = "llama3";

            # documentationSources = [
            #   "https://wiki.nixos.org/wiki/NixOS_Wiki"
            #   "https://nix.dev/manual/nix"
            #   "https://nixos.org/manual/nixpkgs/stable/"
            #   "https://nix.dev/manual/nix/2.28/language/"
            #   "https://nix-community.github.io/home-manager/"
            # ];
          };

          # Neovim integration
          # neovimIntegration = {
          #   enable = false;
          #   useNixVim = true;
          #   autoStartMcp = true;
          # };
        };
      }
    ];

    nix.nixPath = ["nixpkgs=${pkgs}"];

    homeConfigurations.vkarasen = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules =
        homeManagerModules
        ++ [
          ({lib, ...}: {
            config.my.is_private = lib.mkForce true;
          })
        ];
    };

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

    formatter.${system} = pkgs.alejandra;
  };
}
