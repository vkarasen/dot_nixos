{config, lib, pkgs, ...}: {

	config = {
		home.packages = with pkgs; [
			nh
			nix-output-monitor
			nvd
			ripgrep
			curl
			wget
			bat
			gnused
			tig
			dua
			duf
		];

		programs = {
			fzf.enable = true;
			starship.enable = true;
			eza.enable = true;
			direnv = {
				enable = true;
				nix-direnv.enable = true;
			};
		};

	};

}
