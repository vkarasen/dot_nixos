# Dendritic aspect: pi (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.pi = let
    # Close over private flake inputs at flake-parts eval time so the HM module
    # function needs no inputs/ast-bro in extraSpecialArgs — consumers (corporate
    # flake etc.) don't have to thread them.
    astBroInput = inputs.ast-bro;
    agentStuffSrc = inputs.agent-stuff;
  in {
    pkgs,
    lib,
    config,
    ...
  }: let
    skills = import ./_skills.nix { inherit pkgs; ast-bro = astBroInput; };
    astBroSkill = skills.mkAstBroSkill;
    # Consumed from the agent-stuff flake input (flake = false), not copied in.
    nixSearchSkill = skills.mkSourceSkill "nix-search" (agentStuffSrc + "/skills/nix-search");
  in {
    imports = [./_module.nix];

    # Personal settings only — corporate sets my.is_private = false (the default)
    # and declares its own programs.pi-coding-agent block.
    config = lib.mkIf config.my.is_private {
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
