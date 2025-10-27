{pkgs, ...}: {
  programs.nixvim = {
    plugins = {
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
          incremental_selection = {
            enable = true;
            keymaps = {
              init_selection = "<c-s>";
              node_incremental = "<c-s>";
              node_decremental = "<bs>";
            };
          };
        };
      };
      treesitter-context.enable = true;
      treesitter-textobjects = {
        enable = true;
        settings = {
          select = {
            enable = true;
            lookahead = true;
            keymaps = {
              "a=" = "@assignment.outer";
              "i=" = "@assignment.inner";

              "l=" = "@assignment.lhs";
              "r=" = "@assignment.rhs";

              "aa" = "@parameter.outer";
              "ia" = "@parameter.inner";

              "ai" = "@conditional.outer";
              "ii" = "@conditional.inner";

              "al" = "@loop.inner";
              "il" = "@loop.inner";

              "af" = "@call.inner";
              "if" = "@call.inner";

              "am" = "@function.inner";
              "im" = "@function.inner";
            };
          };

          swap = {
            enable = true;
            swapNext = {
              "<leader>na" = "@parameter.inner";
              "<leader>nm" = "@function.outer";
            };
            swapPrevious = {
              "<leader>pa" = "@parameter.inner";
              "<leader>pm" = "@function.outer";
            };
          };

          move = {
            enable = true;
            gotoNextStart = {
              "]f" = "@call.outer";
              "]m" = "@function.outer";
              "]i" = "@conditional.outer";
              "]l" = "@loop.outer";
            };
            gotoNextEnd = {
              "]F" = "@call.outer";
              "]M" = "@function.outer";
              "]I" = "@conditional.outer";
              "]L" = "@loop.outer";
            };
            gotoPreviousStart = {
              "[f" = "@call.outer";
              "[m" = "@function.outer";
              "[i" = "@conditional.outer";
              "[l" = "@loop.outer";
            };
            gotoPreviousEnd = {
              "[F" = "@call.outer";
              "[M" = "@function.outer";
              "[I" = "@conditional.outer";
              "[L" = "@loop.outer";
            };
          };
        };
      };
    };
  };
}
