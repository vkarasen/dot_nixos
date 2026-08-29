# Dendritic aspect: pi (home-manager class).
{inputs, ...}: {
  flake.modules.homeManager.pi = let
    # Close over flake inputs at flake-parts eval time so the HM module
    # function needs no inputs in extraSpecialArgs — consumers (corporate
    # flake etc.) don't have to thread them.
    astBroInput = inputs.ast-bro;
    agentStuffSrc = inputs.agent-stuff;
  in
    {
      pkgs,
      lib,
      config,
      ...
    }: let
      skills = import ./_skills.nix {
        inherit pkgs;
        ast-bro = astBroInput;
      };
      astBroSkill = skills.mkAstBroSkill;
      # Consumed from the agent-stuff flake input (flake = false), not copied in.
      nixSearchSkill = skills.mkSourceSkill "nix-search" (agentStuffSrc + "/skills/nix-search");
      # Companion guidance for the Google Workspace MCP server.
      googleWorkspaceSkill = ./skills/google-workspace;

      # pi-blackhole: algorithmic compaction (zero LLM) + observational memory.
      # Scaled for 1M context windows. Worker models are unset — workers fall
      # back to the session model. Set PI_BLACKHOLE_PASSIVE=1 to disable OM
      # workers in standalone/non-HM environments.
      blackholeConfig = {
        compaction = "auto";
        compactionEngine = "blackhole";
        tailBehavior = "minimal";
        midRunCompaction = "off";
        compactAfterTokens = 650000;
        memory = true;
        sessionFallback = true;
        observeAfterTokens = 30000;
        reflectAfterTokens = 60000;
        observationsPoolMaxTokens = 40000;
        observationsPoolTargetTokens = 10000;
        reflectorInputMaxTokens = 200000;
        dropperInputMaxTokens = 200000;
        observerChunkMaxTokens = 120000;
        observerPreambleMaxTokens = 0;
        dropperPressureThreshold = 0.70;
        agentMaxTurns = 16;
        debug = false;
        debugLog = false;
      };
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
      home.activation.rtkInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init --agent pi --global
      '';

      programs.pi-coding-agent = {
        enable = true;
        extraPackages = [
          pkgs.nodejs
          pkgs.poppler-utils # pdftoppm/pdftocairo — manual PDF→PNG fallback for visual inspection
        ];
        skills = {
          "ast-bro" = astBroSkill;
          "nix-search" = nixSearchSkill;
          "herdr" = builtins.readFile (pkgs.herdr.src + "/skills/herdr/SKILL.md");
          "google-workspace" = googleWorkspaceSkill;
          "linkedin-profile" = ./skills/linkedin-profile;
          "profile-sync" = ./skills/profile-sync;
          "obsidian-vault-bootstrap" = ./skills/obsidian-vault-bootstrap;
          "obsidian-vault-maintenance" = ./skills/obsidian-vault-maintenance;
          "obsidian-vault-read" = ./skills/obsidian-vault-read;
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
        settings = let
          hasCopilot = config.my.copilot.enable or false;
          sopsSecrets = config.sops.secrets or {};
          hasDeepseek = sopsSecrets ? deepseek_api_key;
          hasAnthropic = sopsSecrets ? anthropic_api_key;
          resolved =
            if hasCopilot
            then {
              provider = "github-copilot";
              model = "claude-sonnet-5";
            }
            else if hasDeepseek
            then {
              provider = "deepseek";
              model = "deepseek-v4-pro";
            }
            else if hasAnthropic
            then {
              provider = "anthropic";
              model = "claude-sonnet-5";
            }
            else null;
        in {
          theme = lib.mkDefault "catppuccin-mocha";
          quietStartup = lib.mkDefault true;
          defaultProvider = lib.mkIf (resolved != null) (lib.mkDefault resolved.provider);
          defaultModel = lib.mkIf (resolved != null) (lib.mkDefault resolved.model);
          packages = [
            "npm:pi-mcp-adapter"
            "npm:rpiv-todo"
            "npm:pi-docparser"
            "npm:@sherif-fanous/pi-catppuccin"
            "npm:pi-vim"
            "npm:pi-fzfp"
            "npm:pi-worktrunk"
            "npm:@barlevalon/worktrunk-skill"
            "npm:@zaganjade/pi-usage"
            "npm:@juicesharp/rpiv-web-tools"
            "npm:pi-lens"
            "npm:@latentminds/pi-quotas"
            "npm:pi-blackhole"
          ];
        };
      };

      xdg.configFile."rpiv-web-tools/config.json".text = builtins.toJSON {
        provider = "tavily";
        interceptors.github = true;
      };

      home.file.".pi/agent/pi-blackhole/pi-blackhole-config.json".text =
        builtins.toJSON blackholeConfig;

      # pi-lens mutation controls off by default: no autoformat (deferred format
      # at agent_end would reformat every edited file) and no autofix (no auto-applied
      # Biome/Ruff/ESLint fixes). Both would add whitespace/fix noise to PRs; the
      # agent formats/fixes deliberately instead. Diagnostics (LSP, lint dispatch,
      # actionable warnings) are NOT disabled by these keys — only the mutations.
      # A project's own .pi-lens.json can re-enable per-repo.
      home.file.".pi-lens/config.json".text = builtins.toJSON {
        format = {enabled = false;};
        autofix = {enabled = false;};
      };
    };
}
