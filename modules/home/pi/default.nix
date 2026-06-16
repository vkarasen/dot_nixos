{pkgs, ...}: {
	config.programs.pi-coding-agent = {
		enable = true;
		extraPackages = [
			pkgs.nodejs
			pkgs.bun
		];
		settings = {
			theme = "catppuccin-mocha";
			quietStartup = true;
			defaultProvider = "github-copilot";
			defaultModel = "claude-haiku-4.5";
			packages = [
				"npm:pi-mcp-adapter"
				"npm:context-mode"
				"npm:rpiv-todo"
				"npm:@sherif-fanous/pi-catppuccin"
				"npm:@burneikis/pi-vim"
				"pi install npm:@burneikis/pi-fzfp"
			];
		};
	};
}
