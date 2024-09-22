{config, lib, pkgs, ...}: {
	home.packages = with pkgs; [
		nh
		nix-output-monitor
		nvd
		ripgrep
		fzf
		curl
		wget
		bat
		delta
		gnused
		tig
	];


}
