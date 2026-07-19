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
    options.my.pi.globalAgentPolicies = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
      default = {};
      description = ''
        Named policy sections merged into ~/.pi/agent/AGENTS.md, which pi
        loads as global always-on instructions at startup (not opt-in like
        a skill). Keys are sorted alphabetically before concatenation, so
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
