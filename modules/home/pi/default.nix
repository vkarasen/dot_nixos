# Dendritic aspect: pi (home-manager class).
{...}: {
  flake.modules.homeManager.pi = {
    pkgs,
    lib,
    ast-bro,
    ...
  }: let
    astBroSkill = (import ./_skills.nix {inherit pkgs ast-bro;}).mkAstBroSkill;
  in {
    imports = [./_module.nix];

    config = {
      home.packages = with pkgs; [
        ast-grep
      ];

      programs.pi = {
        skills = {
          "ast-bro" = astBroSkill;
        };
      };

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
            "npm:@burneikis/pi-fzfp"
            "git:github.com/DietrichGebert/ponytail"
            "npm:pi-worktrunk"
            "npm:@barlevalon/worktrunk-skill"
            "npm:@latentminds/pi-quotas"
            "npm:@juicesharp/rpiv-web-tools"
            "npm:pi-lens"
          ];
        };
      };

      xdg.configFile."rpiv-web-tools/config.json".text = builtins.toJSON {
        provider = "tavily";
        interceptors.github = true;
      };
    };
  };
}
