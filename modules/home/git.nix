{lib, pkgs, ...}: {

	config = {

		home.packages = with pkgs; [
			git
		];

		programs.git = {

			enable = true;

			userEmail = "vkarasen@gmail.com";
			userName = "Vitali Karasenko";

			extraConfig = {
				pull = {
					rebase = true;
				};
				init = {
					defaultBranch = "main";
				};
			};

		};
	};
}

