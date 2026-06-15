{config, ...}: {
  programs = {
    nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins.lsp.servers.nixd.settings.options.home_manager.expr = ''(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName}.options'';

      imports = [
        ../../nixvim
      ];
    };
  };
}
