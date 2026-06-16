{
  pkgs,
  lib,
  config,
  ast-bro,
  ...
}: let
  configDir = config.programs.pi-coding-agent.configDir;
  skillsLib = import ./skills.nix {inherit pkgs ast-bro;};
  astBroSkill = skillsLib.mkAstBroSkill;
in {
  config = {
    programs.pi-coding-agent = {
      enable = true;
      extraPackages = [
        pkgs.nodejs
        pkgs.bun
      ];
      settings = {
        theme = "catppuccin-mocha";
        quietStartup = true;
        defaultProvider = "github-copilot";
        defaultModel = "claude-haiku-4.5";
        packages = [
          "npm:pi-mcp-adapter"
          "npm:context-mode"
          "npm:rpiv-todo"
          "npm:@sherif-fanous/pi-catppuccin"
          "npm:@burneikis/pi-vim"
          "pi install npm:@burneikis/pi-fzfp"
        ];
      };
    };

    home.activation.install-ast-bro-for-pi = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p ${configDir}/skills/ast-bro
      $DRY_RUN_CMD cp ${astBroSkill}/SKILL.md ${configDir}/skills/ast-bro/SKILL.md
    '';
  };
}
