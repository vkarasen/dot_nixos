{pkgs, ...}: let
  nodepkgs = with pkgs.nodePackages; [
    bash-language-server
  ];
in {
  home.packages = with pkgs;
    [
      nixd
      alejandra
      shfmt
    ]
    ++ nodepkgs;

  programs = {
    nixvim = {
      plugins = {
        lsp = {
          enable = true;
          keymaps = {
            lspBuf = {
              "<leader>cf" = "format";
              "<leader>ca" = "code_action";
            };
          };
          servers = {
            bashls = {
              enable = true;
              settings.formatting.command = ["shfmt"];
            };
            nixd = {
              enable = true;
              settings = {
                formatting.command = ["alejandra" "-qq"];
                nixpkgs.expr = "import <nixpkgs> {}";
              };
            };
          };
        };
      };
    };
  };
}
