{...}: {
  programs = {
    nixvim = {
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
  };
}
