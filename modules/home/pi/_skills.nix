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
}
