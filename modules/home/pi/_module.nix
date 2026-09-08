# Library module: declares the programs.pi-coding-agent.skills option and wires
# it into programs.pi-coding-agent.settings.skills.
# Import this from default.nix; put actual skill declarations there.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.pi-coding-agent;

  # String content  → store dir named "<name>-skill" with SKILL.md at root
  # Path / derivation → pass through (must be a dir containing SKILL.md at root)
  mkSkillDrv = name: content:
    if lib.isPath content || lib.isDerivation content
    then content
    else
      pkgs.writeTextFile {
        name = "${name}-skill";
        destination = "/SKILL.md";
        text = content;
      };
in {
  options.programs.pi-coding-agent = {
    skills = lib.mkOption {
      type =
        lib.types.attrsOf
        (lib.types.either lib.types.lines (lib.types.either lib.types.path lib.types.package));
      default = {};
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
  };

  config = {
    programs.pi-coding-agent.settings = lib.optionalAttrs (cfg.skills != {}) {
      skills =
        lib.mapAttrsToList
        (name: v: toString (mkSkillDrv name v))
        cfg.skills;
    };
  };
}
