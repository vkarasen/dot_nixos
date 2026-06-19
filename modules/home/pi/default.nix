# Dendritic aspect: pi (home-manager class).
{...}: {
  flake.modules.homeManager.pi = {
    pkgs,
    lib,
    ast-bro,
    inputs,
    ...
  }: let
    skills = import ./_skills.nix {inherit pkgs ast-bro;};
    astBroSkill = skills.mkAstBroSkill;
    # Consumed from the agent-stuff flake input (flake = false), not copied in.
    nixSearchSkill = skills.mkSourceSkill "nix-search" (inputs.agent-stuff + "/skills/nix-search");
  in {
    imports = [./_module.nix];

    config = {
      home.packages = with pkgs; [
        ast-grep
      ];

      programs.pi-coding-agent = {
        enable = true;
        extraPackages = [
          pkgs.nodejs
          pkgs.bun
        ];
        skills = {
          "ast-bro" = astBroSkill;
          "nix-search" = nixSearchSkill;
        };
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
            "npm:pi-fzfp"
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
