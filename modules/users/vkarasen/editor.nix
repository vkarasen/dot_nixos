# Editor configuration: nixvim (neovim), aggregating all nixvim aspects
# Exports: flake.modules.homeManager.editor
{ self, ... }: {
  flake.modules.homeManager.editor = { config, ... }:
    let
      nv = self.modules.nixvim;
    in
    {
      programs = {
        nixvim = {
          enable = true;
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
          vimdiffAlias = true;

          plugins.nixd.settings.options.home_manager.expr = ''(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName or "vkarasen"}.options'';

          imports = [
            nv.base
            nv.git
            nv.lsp
            nv.treesitter
            nv.telescope
            nv.markdown
            nv.lint
            nv.latex
            nv.mini
            nv."which-key"
            nv.dap
          ];
        };
      };
    };
}

