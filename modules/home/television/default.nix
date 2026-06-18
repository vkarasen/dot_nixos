# Dendritic aspect: television (home-manager class).
{...}: {
  flake.modules.homeManager.television = {
    nixvimOptions,
    pkgs,
    ...
  }: {
    imports = [];

    programs.television = {
      enable = true;

      enableBashIntegration = true;
      channels = {
        files = {
          metadata = {
            name = "files";
            description = "A channel to select files and directories";
          };
          preview.command = "bat -n --color=always '{}'";
          source.command = "fd -L -t f";
        };
      };

      settings = {
      };
    };

    programs.nix-search-tv = {
      enable = true;
      enableTelevisionIntegration = true;

      settings = {
        experimental.options_file = {
          nixvim = nixvimOptions;
        };
      };
    };
  };
}
