{config, lib, pkgs, ...}: {

	config = {

		home.packages = with pkgs; [
			openssh
		];

		programs.ssh = {

			enable = true;

			matchBlocks = {
				github = {
					hostname = "github.com";
					user = "git";
					identityFile = "~/.ssh/id_ed25519";
				};
				gentian = {
					hostname = "zqnr.de";
					user = "vkarasen";
					identityFile = "~/.ssh/id_ed25519";
					forwardAgent = true;
					forwardX11 = true;
				};
			};
		};
	};
}
