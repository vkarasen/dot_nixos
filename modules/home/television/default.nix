# Dendritic aspect: television (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.television = let
    nixvimInput = inputs.nixvim;
  in {
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
          nixvim =
            nixvimInput.packages.${pkgs.stdenv.hostPlatform.system}.options-json
            + /share/doc/nixos/options.json;
        };
      };
    };
  };
}
