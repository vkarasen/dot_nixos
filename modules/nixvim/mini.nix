# mini.nvim: icons, files, hipatterns
# Exports: flake.modules.nixvim.mini
{ ... }: {
  flake.modules.nixvim.mini = { ... }: {
    plugins = {
      mini = {
        enable = true;
        mockDevIcons = true;
        modules = {
          icons.style = "glyph";
          files = {
          };
          hipatterns = {
          };
        };
      };
    };
  };
}

