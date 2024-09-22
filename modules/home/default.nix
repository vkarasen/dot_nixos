{
	lib,
	config,
	...
}: {

	imports = [
		./shellPackages.nix
		./ssh.nix
		./git.nix
	];

	config = {
		home.stateVersion = "24.05";
		home.username = "vkarasen";
		home.homeDirectory = "/home/vkarasen";
	};

}
