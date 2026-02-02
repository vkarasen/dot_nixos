# Flake-parts module that exposes all configuration modules for external consumption
#
# This follows the dendritic pattern by exposing modules via flake.modules.<class>.<aspect>
# External flakes can consume these modules like:
#   inputs.dot_nixos.modules.homeManager.git
#   inputs.dot_nixos.modules.homeManager.collections.development
#   inputs.dot_nixos.modules.nixvim.default
{ ... }:
{
  flake.modules = {
    # Home Manager modules
    homeManager = {
      # Base modules
      base = ../base/home-base.nix;

      # Aspect modules - individual feature configurations
      aspects = {
        # Git configuration
        git = ../aspects/git/default.nix;

        # Shell configurations
        shell = {
          bash = ../aspects/shell/bash.nix;
          packages = ../aspects/shell/packages.nix;
        };

        # Terminal configurations
        terminal = {
          tmux = ../aspects/terminal/tmux.nix;
          lf = ../aspects/terminal/lf.nix;
        };

        # Editor configurations
        editor = {
          nixvim = ../aspects/editor/nixvim.nix;
        };

        # Security configurations
        security = {
          sops = ../aspects/security/sops.nix;
          ssh = ../aspects/security/ssh.nix;
        };
      };

      # Collection modules - grouped feature sets
      collections = {
        development = ../collections/development.nix;
        editor = ../collections/editor.nix;
        shell = ../collections/shell.nix;
        terminal = ../collections/terminal.nix;
        security = ../collections/security.nix;
      };

      # User-specific configurations
      users = {
        vkarasen = ../users/vkarasen/default.nix;
      };

      # Constants for reference
      constants = {
        users = ../constants/users.nix;
        system = ../constants/system.nix;
      };
    };

    # Nixvim modules
    nixvim = {
      # Complete nixvim configuration (all aspects combined)
      default = ../../legacy-modules/nixvim/default.nix;

      # Base nixvim configuration
      base = ../base/nixvim-base.nix;

      # Individual nixvim aspects for selective imports
      aspects = {
        git = ../aspects/editor/nixvim/git.nix;
        lsp = ../aspects/editor/nixvim/lsp.nix;
        treesitter = ../aspects/editor/nixvim/treesitter.nix;
        telescope = ../aspects/editor/nixvim/telescope.nix;
        markdown = ../aspects/editor/nixvim/markdown.nix;
        lint = ../aspects/editor/nixvim/lint.nix;
        latex = ../aspects/editor/nixvim/latex.nix;
        mini = ../aspects/editor/nixvim/mini.nix;
        which-key = ../aspects/editor/nixvim/which-key.nix;
        dap = ../aspects/editor/nixvim/dap.nix;
      };
    };
  };
}

