{...}: {
  imports = [
    ./git.nix
    ./lsp.nix
    ./treesitter.nix
    ./telescope.nix
    ./markdown.nix
    # also getting rid of this for now because of codeberg issues
    # ./lint.nix
    ./latex.nix
    ./mini.nix
    ./which-key.nix
    # temporarily removing this because of codeberg issues
    # ./dap.nix
  ];

  colorschemes.catppuccin = {
    enable = true;
    settings.flavor = "mocha";
  };

  # Startup performance: byte-compile Lua to cut cold-start parse/compile time.
  performance.byteCompileLua = {
    enable = true;
    plugins = true;
  };

  # Merge plugins into a single pack to cut runtimepath scanning (the `access`/
  # `readlink`/`statx` storm over ~50 symlinked plugin dirs that dominates cold start).
  # friendly-snippets must stay standalone so luasnip's from_vscode loader finds its snippet files.
  performance.combinePlugins = {
    enable = true;
    standalonePlugins = ["friendly-snippets"];
  };

  globals = {
    mapleader = ";";
    maplocalleader = " ";
  };

  diagnostic.settings = {
    virtual_lines = true;
    virtual_text = false;
  };

  opts = {
    updatetime = 100; # Faster completion
    hidden = true; # Keep closed buffer open in the background

    mouse = "a"; # Enable mouse control
    mousemodel = "extend"; # Mouse right-click extends the current selection
    swapfile = false; # Disable the swap file
    undofile = false; # Automatically save and restore undo history
    backup = false; # Automatically save and restore undo history
    incsearch = true; # Incremental search: show match for partly typed search command
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
    softtabstop = 4;
    shiftround = true;
    smartindent = true;
    autoindent = true; # Do clever autoindenting
    smarttab = true;

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
    lz-n.enable = true;
    lualine.enable = true;
    indent-blankline.enable = true;
    bufferline.enable = true;
    guess-indent.enable = true;
    ts-comments = {
      enable = true;
      lazyLoad.settings.event = "DeferredUIEnter";
      settings.lang = {
        snakemake = "# %s";
      };
    };
    neo-tree = {
      enable = true;
      settings.sources = ["filesystem"];
      lazyLoad.settings.cmd = "Neotree";
    };
  };
}
