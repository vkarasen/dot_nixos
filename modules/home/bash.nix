{lib, pkgs, ...}: {

	config = {

		home.packages = with pkgs; [
			bash
		];

		programs = {

			bash = {
				enable = true;
				enableCompletion = true;
				historySize = 10000;

				initExtra = ''
					set -o vi
					HISTCONTROL='ignoreboth'
				'';

				shellAliases = {
					cat = "bat";

					grep = "rg";

					#lists only directories (no files)
					ld = "eza -lD";

					#lists only files (no directories)
					lf = "eza -lF --color=always | rg -v /";

					#lists only hidden files (no directories)
					lh = "eza -dl .* --group-directories-first";

					#lists everything with directories first
					ll = "eza -al --group-directories-first";

					#lists only files sorted by size
					ls = "eza -alF --color=always --sort=size | rg -v /";

					#lists everything sorted by time updated
					lt = "eza -al --sort=modified";
				};
			};

			fzf = {
				enableBashIntegration = true;
			};

			starship = {
				enableBashIntegration = true;
				settings = {
					add_newline = true;
				};
			};

			eza = {
				enableBashIntegration = true;
				git = true;
			};

			direnv = {
				enableBashIntegration = true;
			};
		};
	};
}

