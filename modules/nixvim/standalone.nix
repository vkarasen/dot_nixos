# Standalone nixvim configuration — imports base + all aspect modules
# Used by the packages.nvim flake output for a self-contained neovim build
# Exports: flake.modules.nixvim.standalone
{ inputs, ... }: {
  flake.modules.nixvim.standalone = { ... }:
    let
      nv = inputs.self.modules.nixvim;
    in
    {
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
}

