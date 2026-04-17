# which-key: keybinding discovery
# Exports: flake.modules.nixvim."which-key"
{ ... }: {
  flake.modules.nixvim."which-key" = { ... }: {
    plugins = {
      which-key = {
        enable = true;
      };
    };
  };
}

