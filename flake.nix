{
  description = "I am a very special flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    catppuccin.url = "github:catppuccin/nix";

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
  };

  outputs = {
    nixpkgs,
    home-manager,
    nix-index-database,
    catppuccin,
    nixvim,
    ...
  }: let
    system = "x86_64-linux";

    pkgs = nixpkgs.legacyPackages.${system};
  in rec {
    homeManagerModules = [
      ./home-manager
      nix-index-database.hmModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      catppuccin.homeManagerModules.catppuccin
      nixvim.homeManagerModules.nixvim
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
    };

    formatter.${system} = pkgs.alejandra;
  };
}
