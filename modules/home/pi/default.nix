# Dendritic aspect: pi (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.pi = let
    # Close over flake inputs at flake-parts eval time so the HM module
    # function needs no inputs in extraSpecialArgs — consumers (corporate
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
    # Companion guidance for the Google Workspace MCP server.
    googleWorkspaceSkill = ./skills/google-workspace;
  in {
    imports = [./_module.nix];

    # Defaults: corporate (or any consumer) can override with lib.mkForce,
    # or extend lists (packages, skills) via normal module merging.
    home.packages = with pkgs; [
      ast-grep
      rtk
    ];

    # Run `rtk init --agent pi --global` on every activation.
    # The hook content is compiled into the binary (include_str!), so this
    # is fully hermetic — no network access. Idempotent by design.
    home.activation.rtkInit =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init --agent pi --global
      '';

    programs.pi-coding-agent = {
      enable = true;
      extraPackages = [
        pkgs.nodejs
      ];
      skills = {
        "ast-bro" = astBroSkill;
        "nix-search" = nixSearchSkill;
        "herdr" = builtins.readFile (pkgs.herdr.src + "/SKILL.md");
        "google-workspace" = googleWorkspaceSkill;
        "oss-contrib" = ./skills/oss-contrib;
        "userspace-mounts" = ./skills/userspace-mounts;
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
          "npm:rpiv-todo"
          "npm:@sherif-fanous/pi-catppuccin"
          "npm:pi-vim"
          "npm:pi-fzfp"
          "npm:pi-worktrunk"
          "npm:@barlevalon/worktrunk-skill"
          "npm:@zaganjade/pi-usage"
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
}
