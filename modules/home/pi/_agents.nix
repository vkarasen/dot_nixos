# Library module: renders my.pi.agents into ~/.pi/agent/agents/<name>.md files
# and materialises a logical-name skill tree so agent `skills` can reference
# skills by their key (not their store basename). Import this from default.nix;
# declare tiers/bundles/agents there (or in the corporate flake). The leading
# underscore keeps it out of the import-tree auto-import set.
#
# The skill tree exists because pi-subagents resolves `skills`/`skillPath` by
# *directory basename* (see docs/pi-subagents-rollout.md §7), so a flat
# /nix/store/<hash>-<name> path never matches the logical name `name`. A
# linkFarm keyed by logical name gives `skillPath: ../subagent-skills` +
# `skills: [name]` stable, rebuild-proof resolution. The tree lives OUTSIDE
# ~/.pi/agent/agents/ because agent discovery is ~/.pi/agent/agents/**/*.md —
# a SKILL.md under that path would be parsed as an agent definition.
{
  pkgs,
  lib,
  config,
  ...
}: let
  tiers = config.my.pi.modelTiers or {};
  bundles = config.my.pi.capabilityBundles or {};
  agents = config.my.pi.agents or {};
  invariants = config.my.pi.agentInvariants or {};
  publicSkills = config.programs.pi-coding-agent.skills or {};

  # Replicated from _module.nix so the tree can name skills by their logical
  # key rather than the store basename. Keep in sync with _module.nix.
  mkSkillDrv = name: content:
    if lib.isPath content || lib.isDerivation content
    then content
    else
      pkgs.writeTextFile {
        name = "${name}-skill";
        destination = "/SKILL.md";
        text = content;
      };

  # <name>/SKILL.md for every public skill, under logical names. Package-
  # provided skills (worktrunk, parse-document, pi-lens-*, …) are discovered
  # from their package.json -> pi.skills and are NOT in this tree — see the
  # note in default.nix where bundles are declared.
  skillsTree =
    pkgs.linkFarm "pi-agent-skill-tree"
    (lib.mapAttrsToList (name: content: {
        name = name;
        path = mkSkillDrv name content;
      })
      publicSkills);

  # Same header/format as policies.nix so a child's invariants block is
  # byte-for-byte the block a human session sees at the top of AGENTS.md.
  invariantBlock = ''
    # Invariants

    These rules always apply — every context, every stage, no exceptions.

    ${lib.removeSuffix "\n" (lib.concatStringsSep "\n" (lib.attrValues invariants))}
  '';

  # Frontmatter scalars must not span lines; descriptions are prose so collapse
  # any newlines rather than emit a broken block scalar.
  oneline = v: lib.replaceStrings ["\n"] [" "] v;

  renderAgent = name: spec: let
    tier = tiers.${spec.tier} or (throw "pi agent `${name}`: unknown tier `${spec.tier}`");
    resolvedBundles = map (b: bundles.${b} or (throw "pi agent `${name}`: unknown bundle `${b}`")) spec.bundles;

    skillNames = lib.unique (lib.concatMap (b: b.skills or []) resolvedBundles);
    extensionNames = lib.unique (lib.concatMap (b: b.extensions or []) resolvedBundles);
    bundleTools = lib.unique (lib.concatMap (b:
      if b.tools == null
      then []
      else b.tools)
    resolvedBundles);
    agentTools =
      if spec.tools == null
      then []
      else spec.tools;
    mcpNames = lib.unique (lib.concatMap (b: b.mcpTools or []) resolvedBundles);
    # `--tools` is a strict allowlist over ALL tools (builtin + extension +
    # custom), so extension tools (pi-lens, pi-docparser, rpiv-web-tools) must
    # be named explicitly. Agent tools + bundle tools union, and mcpTools are
    # rendered as mcp:-prefixed entries in the same list.
    allTools = lib.unique (agentTools ++ bundleTools ++ map (t: "mcp:${t}") mcpNames);
    bundlePolicy = lib.concatMapStrings (b:
      if b.policy or "" == ""
      then ""
      else b.policy + "\n\n")
    resolvedBundles;

    model =
      if tier.provider != null
      then "${tier.provider}/${tier.model}"
      else tier.model;

    frontmatter =
      [
        "---"
        "name: ${name}"
        "description: ${oneline spec.description}"
        "model: ${model}"
        "systemPromptMode: replace"
        "inheritProjectContext: ${lib.boolToString spec.inheritProjectContext}"
        "inheritGlobalContext: ${lib.boolToString spec.inheritGlobalContext}"
        "inheritSkills: ${lib.boolToString spec.inheritSkills}"
      ]
      ++ lib.optional (tier.thinking != null) "thinking: ${tier.thinking}"
      ++ lib.optional (skillNames != []) "skills: ${lib.concatStringsSep ", " skillNames}"
      ++ lib.optional (skillNames != []) "skillPath: ../subagent-skills"
      ++ lib.optional (extensionNames != []) "extensions: ${lib.concatStringsSep ", " extensionNames}"
      ++ lib.optional (allTools != []) "tools: ${lib.concatStringsSep ", " allTools}"
      ++ (
        if spec.toolBudget == null
        then []
        else [
          "toolBudget: ${builtins.toJSON ({hard = spec.toolBudget.hard;} // lib.optionalAttrs (spec.toolBudget.soft != null) {soft = spec.toolBudget.soft;})}"
        ]
      )
      ++ (
        if spec.permission == {}
        then []
        else ["permission:"] ++ lib.mapAttrsToList (k: v: "  ${k}: ${v}") spec.permission
      )
      ++ lib.optional (spec.timeoutMs != null) "timeoutMs: ${toString spec.timeoutMs}"
      ++ ["---"];

    body =
      lib.optionalString (invariants != {}) (invariantBlock + "\n\n")
      + spec.prompt
      + lib.optionalString (bundlePolicy != "") ("\n\n" + lib.removeSuffix "\n" bundlePolicy);
  in
    lib.concatStringsSep "\n" (frontmatter ++ [""] ++ lib.optional (body != "") body);

  enabledAgents = lib.filterAttrs (_: spec: spec.enable or true) agents;
in {
  config.home.file = lib.mkMerge (
    [
      (lib.mkIf (publicSkills != {}) {
        ".pi/agent/subagent-skills".source = skillsTree;
      })
    ]
    ++ lib.mapAttrsToList
    (name: spec: {
      ".pi/agent/agents/${name}.md" = {
        force = true;
        text = renderAgent name spec;
      };
    })
    enabledAgents
  );
}
