{...}: {
  plugins = {
    which-key = {
      enable = true;
      # Official which-key lazy recommendation. lz-n's equivalent of lazy.nvim's `VeryLazy`.
      lazyLoad.settings.event = "DeferredUIEnter";
    };
  };
}
