# Dendritic aspect: pi (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.pi = let
    # Close over flake inputs at flake-parts eval time so the HM module
    # function needs no inputs in extraSpecialArgs — consumers (corporate
    # flake etc.) don't have to thread them.
    astBroInput = inputs.ast-bro;
    agentStuffSrc = inputs.agent-stuff;
    herdrSrc = inputs.herdr; # source tree — gives us SKILL.md pinned to flake.lock
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
    # Herdr's own SKILL.md, read from the pinned source tree.
    # Teaches pi to drive Herdr (split panes, spawn agents, wait on status).
    herdrSkill = pkgs.writeTextDir "herdr/SKILL.md"
      (builtins.readFile (herdrSrc + "/SKILL.md"));
  in {
    imports = [./_module.nix];

    # Defaults: corporate (or any consumer) can override with lib.mkForce,
    # or extend lists (packages, skills) via normal module merging.
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
        "herdr" = herdrSkill;
      };
      # Role prompt templates — mkDefault so the corporate flake can override
      # any individual key with lib.mkForce.
      promptTemplates = {
        "reviewer" = lib.mkDefault ./prompts/reviewer.md;
        "investigator" = lib.mkDefault ./prompts/investigator.md;
        "planner" = lib.mkDefault ./prompts/planner.md;
      };
      settings = {
        theme = lib.mkDefault "catppuccin-mocha";
        quietStartup = lib.mkDefault true;
        defaultProvider = lib.mkDefault "github-copilot";
        defaultModel = lib.mkDefault "gpt-5.4-mini";
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
          "npm:@mohndoe/pi-atlas"
        ];
      };
    };

    xdg.configFile."rpiv-web-tools/config.json".text = builtins.toJSON {
      provider = "tavily";
      interceptors.github = true;
    };
  };
}
