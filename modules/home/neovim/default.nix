{...}: {
  imports = [
    ./git.nix
    ./lsp.nix
    ./treesitter.nix
    ./telescope.nix
    ./markdown.nix
    ./lint.nix
    ./latex.nix
  ];

  programs = {
    nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      colorschemes.catppuccin = {
        enable = true;
        settings.flavor = "mocha";
      };

      globals = {
        mapleader = ";";
        maplocalleader = " ";
      };

      opts = {
        number = true;
        cursorline = true;
        list = true;
        clipboard = "";
        showbreak = "↪ ";
        listchars = {
          trail = "␣";
          extends = "⟩";
          precedes = "⟨";
          nbsp = "·";
          tab = "→ ";
        };

        sw = 4;
        ts = 4;
        shiftround = true;
        smartindent = true;

        infercase = true;
        ignorecase = true;
        smartcase = true;
        gdefault = true;
        linebreak = true;
      };

      keymaps = [
        {
          mode = "n";
          key = "j";
          action = "gj";
        }
        {
          mode = "n";
          key = "k";
          action = "gk";
        }
        {
          mode = "n";
          key = "H";
          action = "<c-w>h";
        }
        {
          mode = "n";
          key = "L";
          action = "<c-w>l";
        }
        {
          mode = "n";
          key = "<c-i>";
          action = "<c-]>";
        }
        {
          mode = "n";
          key = "<CR>";
          action = "@=\"m`o<C-V><Esc>``\"<CR>>";
        }
        {
          mode = "n";
          key = "U";
          action = "<c-r>";
        }
        {
          mode = "n";
          key = "<leader>nt";
          action = ":Neotree<cr>";
        }
      ];

      filetype.pattern = {
        "Snakefile.*" = "snakemake";
      };

      plugins = {
        lualine.enable = true;
        indent-blankline.enable = true;
        bufferline.enable = true;
        neo-tree = {
          enable = true;
          sources = ["filesystem"];
        };
      };
    };
  };
}
