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
