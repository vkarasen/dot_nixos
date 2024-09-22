{
	description = "I am a very special flake";

	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

		home-manager = {
			url = "github:nix-community/home-manager/master";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		nix-index-database = {
			url = "github:nix-community/nix-index-database";
    		inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs = inputs@{
		nixpkgs,
		home-manager,
		nix-index-database,
		...
	}: let

		system = "x86_64-linux";

		pkgs = nixpkgs.legacyPackages.${system};

	in {

		homeConfigurations.vkarasen = home-manager.lib.homeManagerConfiguration {

			inherit pkgs;

			modules = [
			  ./home-manager
			  nix-index-database.hmModules.nix-index
			  { programs.nix-index-database.comma.enable = true; }
			];

		};
	};
}
