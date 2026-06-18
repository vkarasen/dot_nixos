{
  pkgs,
  ast-bro,
}: {
  mkAstBroSkill =
    pkgs.runCommand "ast-bro-skill" {
      buildInputs = [ast-bro.packages."x86_64-linux".default];
    } ''
            mkdir -p $out
            {
              cat << 'EOF'
      ---
      name: ast-bro
      description: Fast, AST-based code navigation and structural analysis. Explore codebases via signatures, call graphs, and import analysis. Use for understanding unfamiliar code, finding callers/callees, and token-budgeted context.
      user-invocable: true
      ---

      EOF
              ${ast-bro.packages."x86_64-linux".default}/bin/ast-bro prompt
            } > $out/SKILL.md
    '';

  # Wrap an external skill source directory (one that already contains
  # SKILL.md, e.g. from a flake input) into a skill derivation. Lets us consume
  # a skill from another repo without copying its contents into this one: the
  # source of truth stays the pinned flake input and updates on `nix flake update`.
  mkSourceSkill = name: src:
    pkgs.runCommandLocal "${name}-skill" {} ''
      mkdir -p "$out"
      cp -r ${src}/. "$out/"
    '';
}
