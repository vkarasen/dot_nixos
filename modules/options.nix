# Class-agnostic custom options (my.*). Declared under the `generic` class so
# the same option set is reusable by future nixos/darwin configs, not just home.
{
  flake.modules.generic.my-options = {lib, ...}: {
    options.my.is_private = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    options.my.git.email = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "vkarasen@gmail.com";
    };
    options.my.portable = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      path = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "~/nix/nix-portable";
      };
    };
    options.my.gdrive.mountPoint = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "/home/vkarasen/mnt/gdrive";
      description = ''
        Canonical filesystem path for the mounted Google Drive. Use this for
        persistent private data that should be available across sessions and
        machines without going through the Google Workspace MCP server.
      '';
    };
    options.my.obsidian = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Obsidian tooling and configure a singular environment-global
          vault for the current user/profile. The global vault is private to
          the current privilege domain; project-local vaults are discovered from
          repository-local instructions instead of enumerated here.
        '';
      };
      globalVault = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "vkarasen-vault";
          description = "Name of the environment-global Obsidian vault.";
        };
        dir = lib.mkOption {
          type = lib.types.nullOr lib.types.nonEmptyStr;
          default = null;
          description = ''
            Canonical filesystem path to the environment-global Obsidian vault.
            When null, the home-manager aspect resolves this to a local vault
            under the user's home directory using globalVault.name. Override
            this in an environment-specific flake to place the vault on synced
            storage such as Google Drive, SharePoint, or Azure.
          '';
        };
        dailyDir = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "daily";
          description = "Vault-relative directory for daily scratchpad notes.";
        };
        templatesDir = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "templates";
          description = "Vault-relative directory for Obsidian templates.";
        };
        attachmentsDir = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "attachments";
          description = "Vault-relative directory for screenshots and attachments.";
        };
      };
    };
    options.my.copilot.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GitHub Copilot integration (neovim, CLI, pi provider).";
    };
    options.my.pi.agentInvariants = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = ''
        Non-negotiable rules that apply in every context and at every stage,
        rendered as a single "# Invariants" block at the top of
        ~/.pi/agent/AGENTS.md.

        This is deliberately separate from globalAgentPolicies. Delegated
        subagents do not inherit the operator's global context file
        (pi-subagents defaults inheritGlobalContext to false), so anything a
        child must never get wrong has to be injected into the child's own
        prompt. Keeping invariants in their own option makes that block
        reusable instead of requiring the whole policy file to be re-read.

        Admission is strict, because everything here competes for attention in
        every session:

        - It must be a PROHIBITION, not a procedure. "How to do X well" is
          stage-specific and belongs in globalAgentPolicies, a capability
          bundle, or a skill, where it is loaded only when X is happening.
        - It must not be enforceable structurally. A rule a guardrail can
          enforce (a permission gate, a withheld tool) should be enforced
          there and deleted from prose entirely.
        - It must be terse. Full sections belong in globalAgentPolicies.

        Values are string-only: unlike globalAgentPolicies these are also
        destined for subagent prompts, where a sops path decrypted at
        activation time is not available. Keys are sorted alphabetically;
        use numeric prefixes.
      '';
      example = lib.literalExpression ''
        {
          "00-nix-store" = "**Never brute-force the Nix store.** ...";
        }
      '';
    };

    options.my.pi.globalAgentPolicies = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
      default = {};
      description = ''
        Named policy sections merged into ~/.pi/agent/AGENTS.md, which pi
        loads as global always-on instructions at startup (not opt-in like
        a skill).

        These sections are for the interactive/orchestrating session. They may
        be long and may exercise judgment. Rules that must reach a delegated
        subagent as well belong in my.pi.agentInvariants instead, which is
        rendered ahead of these and is separately reusable.

        Keys are sorted alphabetically before concatenation, so
        use numeric prefixes to control order:
          "00-nix-workspace"       – base Nix exploration policy (defined here)
          "10-scripting"           – scripting runtime preference (defined here)
          "15-collaboration"       – collaboration / scope-control policy (defined here)
          "18-documentation-drift" – quick documentation-adoption reminder (defined here)
          "90-corporate"           – add in the corporate flake for site-specific rules

        Each value can be either:
        - A string (lib.types.lines): public inline policy section, merged
          additively when multiple modules set the same key.
        - A path: points to a sops-encrypted markdown file whose decrypted
          content becomes the section body at activation time. Path values
          are ignored when my.is_private is false.
      '';
    };

    options.my.pi.privateSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = ''
        Private pi skills whose content must not appear in plaintext in the
        public git repository. Each key is the skill name (lowercase, hyphens
        only); each value is a path to a sops-encrypted file containing the
        full SKILL.md content.

        At activation time (only when my.is_private is true), the encrypted
        content is decrypted and materialized into
        ~/.pi/agent/skills-private/<name>/SKILL.md.
      '';
    };

    options.my.pi.mcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.raw);
      default = {};
      description = ''
        MCP servers exposed to pi via ~/.pi/agent/mcp.json. Each key is a
        server name; each value is a stdio server definition in the
        pi-mcp-adapter mcpServers shape (type, command, args, env, ...).
        Multiple modules merge additively by server name; a single
        aggregation aspect folds the result into the mcp.json file.
      '';
    };
    options.my.pi.modelTiers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          model = lib.mkOption {
            type = lib.types.nonEmptyStr;
            description = "Model id for this tier (bare, or provider-qualified).";
          };
          provider = lib.mkOption {
            type = lib.types.nullOr lib.types.nonEmptyStr;
            default = null;
            description = "Provider id. When set, mkAgent emits provider/model.";
          };
          thinking = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum ["off" "minimal" "low" "medium" "high" "xhigh" "max"]);
            default = null;
            description = "Thinking level for agents on this tier (null = omit).";
          };
        };
      });
      default = {};
      description = ''
        Model tiers referenced by my.pi.agents.*.tier. Each tier bundles a
        model, optional provider, and optional thinking level so an agent
        selects a whole capability/price band at once instead of a raw model.

        Resolve the values from the hasCopilot/hasDeepseek/hasAnthropic ladder
        (§3 of docs/pi-subagents-rollout.md); the corporate flake overrides or
        adds tiers additively.
      '';
    };

    options.my.pi.capabilityBundles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          skills = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Skill names (logical keys, resolved via skillPath).";
          };
          extensions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Extension/package names to load for the child.";
          };
          tools = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "Tool allowlist; null = omit (inherit ambient tools).";
          };
          mcpTools = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "MCP tools to select, rendered as mcp:-prefixed tools.";
          };
          policy = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Bundle policy prose injected into the agent prompt.";
          };
        };
      });
      default = {};
      description = ''
        Capability bundles: repo-independent units that declare skills,
        extensions, tools, and MCP selections together with the policy prose
        that goes with them. Agents compose bundles via my.pi.agents.*.bundles.

        Each axis maps onto a pi-subagents frontmatter field; mkAgent in
        modules/home/pi/_agents.nix renders them. See
        docs/pi-subagents-rollout.md §7 for the skill-naming caveat that makes
        the skillPath tree necessary.
      '';
    };

    options.my.pi.agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.nonEmptyStr;
            description = "One-line agent description (frontmatter description).";
          };
          tier = lib.mkOption {
            type = lib.types.str;
            description = "Key into my.pi.modelTiers for model/thinking.";
          };
          bundles = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Keys into my.pi.capabilityBundles to compose.";
          };
          tools = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = ''
              Baseline tool allowlist for this agent. null = omit the field and
              inherit ambient tools (NOT read-only). A list is a strict
              allowlist over built-in AND extension tools — name extension
              tools explicitly (their provider must also be in a bundle's
              extensions). Bundle `tools` are unioned into this list.
            '';
          };
          toolBudget = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                hard = lib.mkOption {
                  type = lib.types.int;
                  description = "Hard tool-call cap; after this, tools are blocked.";
                };
                soft = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Optional soft cap that nudges before hard.";
                };
              };
            });
            default = null;
            description = ''
              Per-agent tool-call budget (read-only agents only — hard caps can
              strand half-applied edits). null = no budget.
            '';
          };
          permission = lib.mkOption {
            type = lib.types.attrsOf (lib.types.enum ["allow" "ask" "deny"]);
            default = {};
            description = ''
              Per-agent tool permission overrides. These override the global
              write/edit deny (subagentConfig.permissions.rules), which is how
              the investigator/executor re-allow write/edit inside their
              boundary. Bash is never gated (pi-subagents passes it through).
            '';
          };
          timeoutMs = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = ''
              Runtime deadline for this agent in milliseconds. Writers are
              bounded by this, not toolBudget (§5).
            '';
          };
          prompt = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Role prompt body, after frontmatter and invariants.";
          };
          inheritProjectContext = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Keep inherited repo AGENTS.md/CLAUDE.md.";
          };
          inheritGlobalContext = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Also keep the operator's global AGENTS.md.";
          };
          inheritSkills = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Let the child see pi's full discovered skills catalog.";
          };
          worktree = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Launch in a disposable worktree (worktree: true).";
          };
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "When false, the agent file is not emitted.";
          };
        };
      });
      default = {};
      description = ''
        Subagents to generate into ~/.pi/agent/agents/<name>.md. Each is a
        tier × bundle composition plus a role prompt. mkAgent injects
        my.pi.agentInvariants verbatim and sets inherit* explicitly.

        Built by phases 4/5 of docs/pi-subagents-rollout.md; this option is
        declared here so the corporate flake can add agents additively.
      '';
    };
    options.my.homeConfigurationName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = let
        user = builtins.getEnv "USER";
      in
        if user != ""
        then user
        else "vkarasen";
      description = "Name of the home configuration to use for LSP settings";
    };
  };
}
