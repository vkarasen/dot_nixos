
{
  lib,
  pkgs,
  config,
  ...
}: {
	config = {
		programs = {
			opencode = {
				enable = true;
			};
		};
	};
}
