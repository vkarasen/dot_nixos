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
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ast-bro = {
      url = "github:aeroxy/ast-bro";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-std.url = "github:chessai/nix-std";

    # Skill collection by the nix-search-tv maintainer; consumed as a plain
    # source tree (flake = false) so aspects can point pi at skills/* without
    # copying the files into this repo.
    agent-stuff = {
      url = "github:0xferrous/agent-stuff";
      flake = false;
    };

    hm-wrapper-modules = {
      url = "github:sini/hm-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  # Dendritic pattern: every file under ./modules is a flake-parts module,
  # auto-imported by import-tree. flake.nix stays a thin entry point.
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
