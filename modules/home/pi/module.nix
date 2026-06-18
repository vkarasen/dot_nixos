# Library module: declares programs.pi.{skills,promptTemplates} options and
# wires them into programs.pi-coding-agent.settings.{skills,prompts}.
# Import this from default.nix; put actual skill/template declarations there.
{ pkgs, lib, config, ... }:
let
  cfg = config.programs.pi;

  # String content  → store dir with <name>/SKILL.md  (pi discovers recursively)
  # Path / derivation → pass through (must be a dir containing SKILL.md)
  mkSkillDrv = name: content:
    if lib.isPath content || lib.isDerivation content
    then content
    else pkgs.writeTextDir "${name}/SKILL.md" content;

  # String content  → store file <name>.md
  # Path / derivation → pass through
  mkPromptDrv = name: content:
    if lib.isPath content || lib.isDerivation content
    then content
    else pkgs.writeText "${name}.md" content;
in
{
  options.programs.pi = {
    skills = lib.mkOption {
      type = lib.types.attrsOf
        (lib.types.either lib.types.lines (lib.types.either lib.types.path lib.types.package));
      default = { };
      description = ''
        Skills to install into pi.
        Key   = skill directory name (lowercase, hyphens only).
        Value = inline SKILL.md content (string) or a path / derivation
                pointing at a directory that already contains SKILL.md.
      '';
      example = lib.literalExpression ''
        {
          "my-skill" = '''
            ---
            name: my-skill
            description: Does X. Use when working on Y.
            ---
            ## Instructions
            Run `./script.sh` to do X.
          ''';
          "big-skill" = ./skills/big-skill; # dir with SKILL.md
        }
      '';
    };

    promptTemplates = lib.mkOption {
      type = lib.types.attrsOf
        (lib.types.either lib.types.lines (lib.types.either lib.types.path lib.types.package));
      default = { };
      description = ''
        Prompt templates (slash-commands) to install into pi.
        Key   = template name, becomes the /name command (no .md suffix).
        Value = inline template content (string) or a path / derivation
                pointing at a .md file.
      '';
      example = lib.literalExpression ''
        {
          review = '''
            ---
            description: Review staged changes for bugs and security issues
            ---
            Review `git diff --cached`. Focus on bugs, security, error handling.
          ''';
        }
      '';
    };
  };

  config = {
    programs.pi-coding-agent.settings =
      lib.optionalAttrs (cfg.skills != { }) {
        skills = lib.mapAttrsToList
          (name: v: toString (mkSkillDrv name v))
          cfg.skills;
      }
      // lib.optionalAttrs (cfg.promptTemplates != { }) {
        prompts = lib.mapAttrsToList
          (name: v: toString (mkPromptDrv name v))
          cfg.promptTemplates;
      };
  };
}
