# Reusable library functions exposed as flake.lib.pi.
# A corporate or other flake can call these to build skill derivations
# using the same builders as the private config, against its own pkgs.
{inputs, ...}: {
  flake.lib.pi = {
    # Build skill derivations with the private flake's builders.
    # Usage from a consumer flake:
    #   let skills = inputs.private.lib.pi.mkSkills { inherit pkgs; ast-bro = inputs.ast-bro; };
    #   in { "ast-bro" = skills.mkAstBroSkill; }
    # Returns the _skills.nix attrset: { mkAstBroSkill, mkSourceSkill }.
    # ponytail: ast-bro input passed explicitly so the consumer pins its own version;
    # follows = "private/ast-bro" is the recommended approach (see corporate wiring skill).
    mkSkills = {
      pkgs,
      ast-bro,
    }:
      import ../home/pi/_skills.nix {inherit pkgs ast-bro;};
  };
}
