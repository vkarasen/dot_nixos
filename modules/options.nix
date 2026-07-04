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
    options.my.pi.globalAgentPolicies = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
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
        The lib.types.lines type lets multiple modules extend the same key
        additively; use lib.mkForce to override a section entirely.
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
