# Dendritic aspect: pi-private (home-manager class).
#
# Materializes private skills and private AGENTS.md policy sections from
# sops-encrypted files at activation time.  This is a SEPARATE aspect
# (like pi-policies) because it references config.my.* options that don't
# exist in the standalone package build context.
#
# ── What this does ──────────────────────────────────────────────────────────
#  • Auto-generates sops.secrets entries for:
#      - path-valued entries in my.pi.globalAgentPolicies  (private policies)
#      - entries in my.pi.privateSkills                    (private skills)
#  • At activation time (after writeBoundary):
#      1. Wipes and repopulates ~/.pi/agent/skills-private/<name>/SKILL.md
#      2. Reads the public AGENTS.md base (written by pi-policies),
#         appends the decrypted private policy sections in key order,
#         and writes the final AGENTS.md as a regular file (overwriting
#         the Nix-store symlink).
#  • Registers ~/.pi/agent/skills-private/ in pi's settings.skills so
#    skills are auto-discovered at startup.
#
# ── Adding a private skill ──────────────────────────────────────────────────
#  1. sops modules/home/pi/skills-private/<name>.md
#  2. Add to my.pi.privateSkills below:
#       my.pi.privateSkills."<name>" = ./skills-private/<name>.md;
#
# ── Adding a private policy section ─────────────────────────────────────────
#  1. sops modules/home/pi/skills-private/<name>.md
#  2. Add to my.pi.globalAgentPolicies below:
#       my.pi.globalAgentPolicies."<order>-<name>" = ./skills-private/<name>.md;
{...}: {
  flake.modules.homeManager.pi-private = {
    pkgs,
    lib,
    config,
    ...
  }: lib.mkIf config.my.is_private (let
    # ── Private policies: path-valued entries in globalAgentPolicies ────
    allPolicies = config.my.pi.globalAgentPolicies;
    isPrivatePolicy = v: !builtins.isString v;
    privatePolicies = lib.filterAttrs (_: isPrivatePolicy) allPolicies;
    privatePolicyList = lib.mapAttrsToList (key: _file: {
      inherit key;
      secretName = "pi-policy-${key}";
    }) privatePolicies;
    # Resolve secret paths eagerly so shell fragments are clean.
    privatePolicyListWithPaths = map (entry: entry // {
      secretPath = config.sops.secrets.${entry.secretName}.path;
    }) privatePolicyList;

    # ── Private skills ──────────────────────────────────────────────────
    privateSkills = config.my.pi.privateSkills;
    privateSkillList = lib.mapAttrsToList (key: _file: {
      inherit key;
      secretName = "pi-skill-${key}";
    }) privateSkills;
    privateSkillListWithPaths = map (entry: entry // {
      secretPath = config.sops.secrets.${entry.secretName}.path;
    }) privateSkillList;

    hasPrivateSkills = privateSkillList != [];
    hasPrivatePolicies = privatePolicyList != [];
  in {
    # ── sops secrets ────────────────────────────────────────────────────
    sops.secrets = lib.mkMerge [
      (lib.mkIf hasPrivatePolicies (
        builtins.listToAttrs (map (entry: {
          name = entry.secretName;
          value = {
            sopsFile = privatePolicies.${entry.key};
            format = "binary";
          };
        }) privatePolicyList)
      ))
      (lib.mkIf hasPrivateSkills (
        builtins.listToAttrs (map (entry: {
          name = entry.secretName;
          value = {
            sopsFile = privateSkills.${entry.key};
            format = "binary";
          };
        }) privateSkillList)
      ))
    ];

    # ── Activation ──────────────────────────────────────────────────────
    home.activation.installPrivatePiAssets = lib.hm.dag.entryAfter ["sops-nix"] (
      let
        coreutils = pkgs.coreutils;
      in ''
        AGENTS_MD="$HOME/.pi/agent/AGENTS.md"
        SKILLS_DIR="$HOME/.pi/agent/skills-private"

        # ── Private skills ──────────────────────────────────────────────
        $DRY_RUN_CMD rm -rf "$SKILLS_DIR"
      ''
      + lib.optionalString hasPrivateSkills ''
        $DRY_RUN_CMD mkdir -p "$SKILLS_DIR"
      ''
      + lib.concatStringsSep "\n" (map (entry: ''
        if [ -f "${entry.secretPath}" ]; then
          $DRY_RUN_CMD mkdir -p "$SKILLS_DIR/${entry.key}"
          $DRY_RUN_CMD ${coreutils}/bin/install -Dm600 \
            "${entry.secretPath}" \
            "$SKILLS_DIR/${entry.key}/SKILL.md"
        else
          echo "pi-private: sops secret not available for skill '${entry.key}' — skipping" >&2
        fi
      '') privateSkillListWithPaths)
      + ''

        # ── AGENTS.md assembly ──────────────────────────────────────────
        # The public base is a Nix-store symlink written by pi-policies.
        # We copy it, append private sections, and replace the symlink.
        TMP_AGENTS="$(${coreutils}/bin/mktemp)"
        if [ -f "$AGENTS_MD" ]; then
          ${coreutils}/bin/cat "$AGENTS_MD" > "$TMP_AGENTS"
        fi
      ''
      + lib.concatStringsSep "\n" (map (entry: ''
        if [ -f "${entry.secretPath}" ]; then
          echo "" >> "$TMP_AGENTS"
          ${coreutils}/bin/cat "${entry.secretPath}" >> "$TMP_AGENTS"
        else
          echo "pi-private: sops secret not available for policy '${entry.key}' — skipping" >&2
        fi
      '') privatePolicyListWithPaths)
      + ''

        $DRY_RUN_CMD ${coreutils}/bin/install -Dm600 "$TMP_AGENTS" "$AGENTS_MD"
        ${coreutils}/bin/rm -f "$TMP_AGENTS"
      ''
    );

    # ── Pi settings: register private skills path ───────────────────────
    programs.pi-coding-agent.settings.skills = lib.mkIf hasPrivateSkills [
      "${config.home.homeDirectory}/.pi/agent/skills-private/"
    ];
  });
}
