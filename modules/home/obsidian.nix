# Dendritic aspect: obsidian (home-manager class).
#
# Configures local tooling for the environment-global Obsidian vault.  The
# vault itself is mutable user state, so this aspect deliberately does not
# create or overwrite vault contents during activation.
{...}: {
  flake.modules.homeManager.obsidian = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.obsidian;
    globalVault = cfg.globalVault;
    globalVaultDir =
      if globalVault.dir == null
      then "${config.home.homeDirectory}/${globalVault.name}"
      else globalVault.dir;
  in {
    config = lib.mkIf cfg.enable {
      programs.obsidian = {
        enable = true;
        package = pkgs.obsidian;
        cli.enable = true;
      };

      home.sessionVariables = {
        OBSIDIAN_GLOBAL_VAULT_NAME = globalVault.name;
        OBSIDIAN_GLOBAL_VAULT_DIR = globalVaultDir;
      };

      programs.nixvim = {
        keymaps = [
          {
            mode = "n";
            key = "<leader>oo";
            action = "<cmd>Obsidian quick_switch<cr>";
          }
          {
            mode = "n";
            key = "<leader>os";
            action = "<cmd>Obsidian search<cr>";
          }
          {
            mode = "n";
            key = "<leader>on";
            action = "<cmd>Obsidian new<cr>";
          }
          {
            mode = "n";
            key = "<leader>od";
            action = "<cmd>Obsidian today<cr>";
          }
          {
            mode = "n";
            key = "<leader>ob";
            action = "<cmd>Obsidian backlinks<cr>";
          }
          {
            mode = "n";
            key = "<leader>ol";
            action = "<cmd>Obsidian links<cr>";
          }
          {
            mode = "n";
            key = "<leader>oT";
            action = "<cmd>Obsidian template<cr>";
          }
        ];

        plugins.obsidian = {
          enable = true;
          settings = {
            legacy_commands = false;
            workspaces = [
              {
                name = globalVault.name;
                path = globalVaultDir;
              }
            ];
            picker.name = "telescope.nvim";
            link = {
              style = "wiki";
              format = "shortest";
              auto_update = false;
            };
            note_id_func.__raw = ''
              require("obsidian.builtin").title_id
            '';
            templates = {
              folder = globalVault.templatesDir;
              date_format = "YYYY-MM-DD";
              time_format = "HH:mm";
            };
            daily_notes = {
              enabled = true;
              folder = globalVault.dailyDir;
              date_format = "YYYY-MM-DD";
              template = "daily.md";
              default_tags = ["daily"];
              workdays_only = false;
            };
            attachments.folder = globalVault.attachmentsDir;
            ui.enable = false;
            callbacks.enter_note.__raw = ''
              function(note)
                local api = require("obsidian.api")
                vim.keymap.set("n", "<leader>oa", api.smart_action, {
                  buffer = true,
                  desc = "Obsidian smart action",
                })
                vim.keymap.set("n", "<leader>ox", "<cmd>Obsidian toggle_checkbox<cr>", {
                  buffer = true,
                  desc = "Obsidian toggle checkbox",
                })
              end
            '';
          };
        };
      };
    };
  };
}
