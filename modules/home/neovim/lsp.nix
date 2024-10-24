{pkgs, ...}: let
  nodepkgs = with pkgs.nodePackages; [
    bash-language-server
  ];
in {
  home.packages = with pkgs;
    [
      nil
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
            nil_ls = {
              enable = true;
              settings.formatting.command = ["alejandra" "-qq"];
            };
          };
        };
      };
    };
  };
}
