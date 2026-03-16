# Exposes all configuration modules for external consumption
#
# This follows the dendritic pattern by exposing modules via flake.modules.<class>.<aspect>
# External flakes can consume these modules like:
#   inputs.dot_nixos.modules.homeManager.aspects.git
#   inputs.dot_nixos.modules.homeManager.collections.development
#   inputs.dot_nixos.modules.nixvim.default
{ ... }:
{
  flake.modules = {
    # Home Manager modules
    homeManager = {
      # Base modules
      base = ./_home/base.nix;
      options = ./_home/options.nix;

      # Aspect modules - individual feature configurations
      aspects = {
        git = ./_home/aspects/git.nix;

        shell = {
          bash = ./_home/aspects/shell/bash.nix;
          packages = ./_home/aspects/shell/packages.nix;
        };

        terminal = {
          tmux = ./_home/aspects/terminal/tmux.nix;
          lf = ./_home/aspects/terminal/lf.nix;
        };

        editor = {
          nixvim = ./_home/aspects/editor/nixvim.nix;
        };

        security = {
          sops = ./_home/aspects/security/sops.nix;
          ssh = ./_home/aspects/security/ssh.nix;
        };
      };

      # Collection modules - grouped feature sets
      collections = {
        development = ./_home/collections/development.nix;
        editor = ./_home/collections/editor.nix;
        shell = ./_home/collections/shell.nix;
        terminal = ./_home/collections/terminal.nix;
        security = ./_home/collections/security.nix;
      };

      # User-specific configurations
      users = {
        vkarasen = ./_home/users/vkarasen.nix;
      };

      # Constants for reference
      constants = {
        users = ./_constants/users.nix;
        system = ./_constants/system.nix;
      };
    };

    # Nixvim modules
    nixvim = {
      # Complete nixvim configuration (all aspects combined)
      default = ./_nixvim/standalone.nix;

      # Base nixvim configuration
      base = ./_nixvim/base.nix;

      # Individual nixvim aspects for selective imports
      aspects = {
        git = ./_nixvim/git.nix;
        lsp = ./_nixvim/lsp.nix;
        treesitter = ./_nixvim/treesitter.nix;
        telescope = ./_nixvim/telescope.nix;
        markdown = ./_nixvim/markdown.nix;
        lint = ./_nixvim/lint.nix;
        latex = ./_nixvim/latex.nix;
        mini = ./_nixvim/mini.nix;
        which-key = ./_nixvim/which-key.nix;
        dap = ./_nixvim/dap.nix;
      };
    };
  };
}

