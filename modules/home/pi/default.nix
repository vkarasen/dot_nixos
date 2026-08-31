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

      # pi-subagents extension config (distinct from the settings.json keys
      # below — upstream splits them: runtime/config knobs live here, while
      # watchdog/agentOverrides/model routing live in Pi settings).
      subagentConfig = {
        # Disposable worktrees for `worktree: true` runs. Deliberately NOT
        # under the repo's own .worktrees/ — that namespace belongs to
        # worktrunk, and agent scratch worktrees would clutter `wt list`.
        #
        # Layout is flat and not repo-namespaced (worktree.ts builds
        # <base>/pi-worktree-<runId>-<index>), but runId is a randomUUID, so
        # worktrees from different repos coexist without collision. The cost
        # is that an orphan left by a crash has an opaque name; living under
        # XDG_CACHE_HOME makes wiping the directory a legitimate recovery,
        # followed by `git worktree prune` in the affected repos.
        worktreeBaseDir = "${config.xdg.cacheHome}/pi-subagents/worktrees";

        # Native child tool permissions — pi-subagents' own gate, not a
        # third-party one. Applies ONLY to Pi child runtimes, never this
        # interactive session, and is not registered at all when no ask/deny
        # rule is present. `deny` refuses outright instead of prompting, so
        # there is no approval-fatigue surface to get wrong.
        #
        # Note this does NOT cover bash — pi-subagents passes bash through
        # ungated by design. Read-only children therefore get no bash at all
        # (see agentOverrides below) rather than a bash policy.
        #
        # Bootstrap posture: retrieval only. The builtin writers (`worker`,
        # `reviewer`, `delegate`) will fail their edits under this rule —
        # intended while only scout/researcher/oracle are in use. Custom
        # agents override it per-agent with a `permission:` frontmatter block;
        # the investigator role gets write access inside its own disposable
        # worktree that way.
        permissions.rules = {
          read = "allow";
          write = "deny";
          edit = "deny";
        };
      };
    in {
      imports = [./_module.nix ./_agents.nix];

      # ── Model tiers (phase 2 scaffolding) ─────────────────────────────
      # Referenced by my.pi.agents.*.tier. Private/deepseek ladder per §3 of
      # docs/pi-subagents-rollout.md; corporate flake overrides keys with
      # lib.mkForce or adds its own tiers additively.
      my.pi.modelTiers = lib.mkDefault {
        orchestrator = {
          model = "deepseek-v4-pro";
          provider = "deepseek";
          thinking = "high";
        };
        executive = {
          model = "deepseek-v4-pro";
          provider = "deepseek";
          thinking = "high";
        };
        worker = {
          model = "deepseek-v4-pro";
          provider = "deepseek";
          thinking = "medium";
        };
        simple = {
          model = "deepseek-v4-flash";
          provider = "deepseek";
          thinking = "low";
        };
        vision = {
          model = "claude-haiku-4-5";
          provider = "anthropic";
          thinking = null;
        };
      };

      # ── Capability bundles (phase 2 scaffolding, first cut) ─────────────
      # Repo-independent units of skills + extensions + tools + mcpTools.
      # `skills` are logical keys of programs.pi-coding-agent.skills, resolved
      # via the skillPath tree in _agents.nix. Extension/tool/MCP names are a
      # first guess — verify against the actual packages before phase 4/5
      # agents reference these (a wrong name fails the child closed).
      #
      # Not yet representable here: package-provided skills (worktrunk,
      # parse-document, pi-lens-*, mcp-scripting) and repo-local skills
      # (pi-config, bundle-module, edit-private-skill) are not in the
      # skillPath tree; phase 4/5 must materialise them or drop the references.
      my.pi.capabilityBundles = lib.mkDefault {
        code = {
          skills = ["ast-bro"];
          extensions = ["pi-lens"];
          tools = null;
        };
        nix = {
          skills = ["nix-search" "userspace-mounts"];
          # bundle-module / pi-config are repo-local, omitted until skillPath
          # can point at the repo's .pi/skills.
          tools = null; # nix agents need bash for nix-search-tv / nix build
        };
        web = {
          extensions = ["@juicesharp/rpiv-web-tools"];
          tools = ["web_search" "web_fetch"];
        };
        vault = {
          skills = ["obsidian-vault-read" "obsidian-vault-maintenance"];
          tools = null;
        };
        workspace = {
          skills = ["google-workspace" "linkedin-profile"];
          mcpTools = ["google-workspace"];
        };
        media = {
          skills = ["video-analyzer"];
          extensions = ["pi-docparser"];
          mcpTools = ["video-analyzer"];
        };
        vcs = {
          skills = ["worktrunk"];
          extensions = ["pi-worktrunk"];
          tools = null;
        };
      };

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
          "video-analyzer" = ./skills/video-analyzer;
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
            "npm:pi-subagents"
            # Pinned: 3 releases in its first week and a single author. Small,
            # dependency-free and deterministic (no model calls), so it is
            # cheap to audit — but not yet a package to track latest on.
            "npm:pi-death-loop-guard@0.1.2"
          ];

          # ── Anti-spiral, not anti-adversary ────────────────────────────
          # The failure mode being defended against is an agent that drifts
          # into unrequested debugging and "fixing", not a malicious command.
          # Command-pattern gating does not see that — a drifting agent runs
          # perfectly ordinary commands — and prompting on each one only buys
          # approval fatigue. So: observe and bound, never ask.
          subagents = {
            watchdog = {
              enabled = true;
              # One model serves every watchdog check, so this trades
              # adversarial-review depth for cheap frequent monitoring.
              # Frequent monitoring is the point here. Thinking is left off
              # (omitted = off upstream). Raise to a stronger model if the
              # scope-drift calls turn out to be poor.
              main.model = "deepseek/deepseek-v4-flash";
              # Reviews work against a scope artifact built from real user
              # prompts, flagging work that no longer serves the request.
              scope.enabled = true;
              # Scopey-style: a non-blocking review every N tool results,
              # delivered as a transcript-visible steer rather than a prompt.
              cadence.everyNTools = 10;
              # Bounded so the correction cannot itself loop.
              autoFollow = {
                blockers = true;
                maxAttempts = 3;
                stalemateRepeats = 3;
              };
            };

            # Read-only builtins get no bash. pi-subagents cannot gate bash,
            # so withholding it is the only structural way to keep a recon
            # child from mutating the repo it is reading. Matching pi's own
            # read-only example (`pi --tools read,grep,find,ls`).
            #
            # This is a real capability cut: no rg, git log or nix-search-tv.
            # It is the line between roles rather than an oversight — work
            # that needs to run something belongs to an investigator agent
            # with its own disposable worktree, added in a later phase.
            agentOverrides = let
              readOnly = {tools = ["read" "grep" "find" "ls"];};
            in {
              scout = readOnly;
              researcher = readOnly;
              oracle = readOnly;
            };
          };
        };
      };

      # Wide fan-out contends on a single status.json; the default retry
      # ladder parks the thread synchronously for ~7.9s and presents as a hung
      # process at 0% CPU.
      home.sessionVariables.PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS = "1000";

      home.file.".pi/agent/extensions/subagent/config.json".text =
        builtins.toJSON subagentConfig;

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
