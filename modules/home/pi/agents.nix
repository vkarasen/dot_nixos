# Dendritic aspect: pi-agents (home-manager class).
#
# Declares the subagent roster — model tiers, capability bundles, and the
# agents themselves — and pulls in ./_agents.nix, which renders them into
# ~/.pi/agent/agents/<name>.md plus the logical-name skill tree.
#
# This is a SEPARATE aspect from modules/home/pi/default.nix for exactly the
# reason policies.nix is: the standalone `packages.pi` build
# (modules/flake/wrapped-packages.nix) evaluates flake.modules.homeManager.pi
# in ISOLATION, without the generic my-options module. Any `my.*` DEFINITION
# inside that aspect therefore fails with "The option `my' does not exist"
# and breaks `nix flake check`, even though the full home configuration
# builds fine. Reads guarded with `or` are safe there; definitions are not.
#
# So: every my.pi.{modelTiers,capabilityBundles,agents} definition belongs
# here, never in default.nix. import-tree picks this file up automatically and
# home-configurations.nix folds it in with the rest.
{...}: {
  flake.modules.homeManager.pi-agents = {lib, ...}: let
    # Read-only tool baseline: no bash/write/edit. `--tools` is a strict
    # allowlist over all tools, so extension tools (pi-lens, pi-docparser,
    # web) come from their bundles and are unioned in by mkAgent.
    readOnly = ["read" "grep" "find" "ls"];

    # Per-FIELD mkDefault, and it has to be per-field.
    #
    # `lib.mkDefault` applied to a whole attrset lowers the priority of the
    # ENTIRE definition, so a consumer flake that defines a single key
    # discards every sibling. Measured with evalModules: with a whole-attrset
    # default, a corporate `modelTiers.orchestrator = {...}` silently dropped
    # worker/simple/vision/executive. For modelTiers and capabilityBundles
    # that fails loudly (_agents.nix throws `unknown tier`/`unknown bundle`),
    # but for `agents` it is SILENT — the other nine agents simply stop being
    # emitted, and the generated roster table shrinks to match, so the result
    # looks self-consistent.
    #
    # Per-key is also not enough: it makes the whole submodule value one
    # definition, so a partial override like `modelTiers.worker.thinking`
    # discards the sibling fields and `model` ends up with no value at all.
    # Pushing the default down to each field supports all four consumer
    # moves: replace a key, add a key, tweak one field, or repoint one field
    # across every key.
    #
    # Note the semantics this gives list-valued fields (skills, extensions,
    # bundles, tools): a consumer definition REPLACES the list rather than
    # appending to it. That is deliberate — corporate needs to drop
    # private-only skills, which additive merging cannot express. To extend,
    # restate the full list.
    # The guard keeps this idempotent: a field that already carries its own
    # priority wrapper (mkDefault / mkForce / mkIf) is passed through
    # untouched. Double-wrapping produces mkDefault (mkDefault x), and the
    # module system only unwraps one level, so the inner wrapper reaches the
    # type check as a bare attrset — "a definition for option `…' is not of
    # type `boolean'". Cheap guard, obscure failure.
    perField = lib.mapAttrs (
      _: entry:
        lib.mapAttrs (
          _: value:
            if lib.isAttrs value && value ? _type
            then value
            else lib.mkDefault value
        )
        entry
    );
  in {
    imports = [./_agents.nix];

    # ── Model tiers (phase 2 scaffolding) ─────────────────────────────
    # Referenced by my.pi.agents.*.tier. Private/deepseek ladder per §3 of
    # docs/pi-subagents-rollout.md; a consumer flake overrides any field of
    # any tier, or adds tiers, with a plain definition — no mkForce needed,
    # because `perField` above leaves each field individually defaultable.
    #
    # The `orchestrator` tier is special: it also drives the interactive
    # session's defaultModel/defaultProvider/defaultThinkingLevel (see
    # modules/home/pi/default.nix). You always drop into an orchestrator, so
    # the model you talk to and the tier that routes delegation are one knob.
    my.pi.modelTiers = perField {
      orchestrator = {
        model = "deepseek-v4-pro";
        provider = "deepseek";
        thinking = "high";
      };
      executive = {
        model = "deepseek-v4-pro";
        provider = "deepseek";
        thinking = "high";
      };
      worker = {
        model = "deepseek-v4-pro";
        provider = "deepseek";
        thinking = "medium";
      };
      simple = {
        model = "deepseek-v4-flash";
        provider = "deepseek";
        thinking = "low";
      };
      # Measured A/B on a synthetic ground-truth image (shapes + verbatim
      # text): deepseek-v4-flash-vision-exp and claude-haiku-4-5 were both
      # 100% correct, at $0.0019 vs $0.0228 — 12x. The gap is almost entirely
      # Anthropic cacheWrite: haiku billed 14,457 cacheWrite tokens to boot a
      # prompt a one-shot child never re-reads; deepseek bills none. Prompt
      # caching only pays back across many turns, and these children are
      # short-lived by design. Fall back to anthropic/claude-haiku-4-5 if
      # `-exp` (experimental upstream) starts refusing images or leaves the
      # model store.
      vision = {
        model = "deepseek-v4-flash-vision-exp";
        provider = "deepseek";
        thinking = null;
      };
    };

    # ── Capability bundles (phase 2 scaffolding, first cut) ─────────────
    # Repo-independent units of skills + extensions + tools + mcpTools.
    # `skills` are logical keys of programs.pi-coding-agent.skills, resolved
    # via the skillPath tree in _agents.nix. Extension/tool/MCP names are a
    # first guess — verify against the actual packages before phase 4/5
    # agents reference these (a wrong name fails the child closed).
    #
    # Verified semantics (pi-subagents child launch): a non-empty
    # `extensions:` list REPLACES ambient extensions (--no-extensions +
    # only listed), it does not add to them. So a bundle that needs MCP must
    # list pi-mcp-adapter itself, and the union of an agent's bundle
    # extensions must be complete for that agent. Entries are passed to
    # `pi --extension`, so packages need the `npm:` prefix (bare names are
    # resolved as filesystem paths and fail the child launch).
    #
    # Not yet representable here: package-provided skills (worktrunk,
    # parse-document, pi-lens-*, mcp-scripting) and repo-local skills
    # (pi-config, bundle-module, edit-private-skill) are not in the
    # skillPath tree; phase 4/5 must materialise them or drop the references.
    my.pi.capabilityBundles = perField {
      # Light code recon (ast-bro navigation). pi-lens is split into `lens`
      # because it is executor/reviewer-only (§5) and cheap scouts must not
      # pay its session_start cost.
      code = {skills = ["ast-bro"];};
      # LSP diagnostics + structural search (pi-lens read-only tools).
      lens = {
        extensions = ["npm:pi-lens"];
        tools = [
          "lens_diagnostics"
          "lsp_diagnostics"
          "symbol_search"
          "module_report"
          "read_symbol"
          "read_enclosing"
          "project_report"
        ];
      };
      # This bundle owns `bash` itself, and that is the point. Its value is
      # nix-search-tv, which is a CLI — a bundle whose skill needs a tool the
      # agent lacks is worse than no bundle: it spends prompt context
      # advertising a capability that cannot be exercised, and invites the
      # model to try anyway. Bundles carrying their own prerequisites is what
      # keeps "skill without its tool" unrepresentable, the mirror of the
      # "tool without its extension" rule the other bundles already follow.
      #
      # The tradeoff is accepted deliberately: authoritative option lookup is
      # worth more than the read-only posture, and pi-subagents cannot gate
      # bash, so the compensation is a more capable model (worker tier, not
      # simple) plus the scoping policy below. That policy is advisory — it
      # is prose, and prose does not enforce. The structural fix is to stop
      # needing the shell at all by wrapping nix-search-tv as a native pi tool
      # or MCP server; then this bundle drops `bash` and `policy` entirely.
      #
      # bundle-module / pi-config are repo-local, omitted until skillPath can
      # point at the repo's .pi/skills.
      nix = {
        skills = ["nix-search" "userspace-mounts"];
        tools = ["bash"];
        policy = ''
          ## Why you have `bash`

          `bash` is in your tool list for one reason: `nix-search-tv` is a
          command-line tool, and authoritative option and package lookup is
          the whole point of this capability. Use the shell for
          `nix-search-tv` queries and for cheap read-only inspection.

          Do not use it for anything else. No writing or editing files, no
          `git` operations, no `nix build` or other long-running builds, no
          installing or fetching. If the task appears to need any of those,
          that is a signal it belongs to a different agent — say so and stop
          rather than reaching for the shell.

          Never guess an option name, type, or default. If `nix-search-tv`
          does not return it, report that it is not in the index rather than
          inferring it from a similar option.
        '';
      };
      web = {
        extensions = ["npm:@juicesharp/rpiv-web-tools"];
        tools = ["web_search" "web_fetch"];
      };
      vault = {skills = ["obsidian-vault-read" "obsidian-vault-maintenance"];};
      workspace = {
        skills = ["google-workspace" "linkedin-profile"];
        extensions = ["npm:pi-mcp-adapter"];
        mcpTools = ["google-workspace"];
      };
      media = {
        skills = ["video-analyzer"];
        extensions = ["npm:pi-docparser" "npm:pi-mcp-adapter"];
        tools = ["document_parse" "document_search" "document_screenshot"];
        mcpTools = ["video-analyzer"];
      };
      vcs = {
        skills = ["worktrunk"];
        extensions = ["npm:pi-worktrunk"];
      };
    };

    # ── Phase 4: read-mostly agents ─────────────────────────────────────
    # Read-only posture = strict tool allowlist, no bash/write/edit. Roles
    # are separated by blast radius (§5b); none of these can mutate. toolBudget
    # hard caps bound runaway loops (read-only agents only — see §5).
    my.pi.agents = perField {
      scout = {
        description = "Fast codebase recon that returns compressed context for handoff";
        tier = "simple";
        bundles = ["code"];
        tools = readOnly;
        toolBudget = {hard = 40;};
        prompt = ''
          You are a scouting subagent. Move fast, do not guess. Map the area
          with grep/find/ls before diving deeper, then cite exact paths and
          line ranges. Return compressed context for handoff: entry points,
          key symbols, data flow, likely-change files, constraints, risks.
        '';
      };
      # Worker tier rather than simple: the `nix` bundle hands this agent a
      # shell, and flash-at-low-thinking is the wrong model to hold a prose
      # constraint about how to use one. toolTimeoutMs bounds a single hung
      # bash call (a first-run nix-search-tv index build, a command waiting on
      # input) in a way a read call cannot; timeoutMs is the whole-run window
      # — an hour, so a blocked supervisor ask is not truncated by the run
      # deadline (the effective wait is min(ask timeout, timeoutMs)).
      nix-scout = {
        description = "Nix/Home-Manager option lookup and config-tree recon";
        tier = "worker";
        bundles = ["nix"];
        tools = readOnly;
        toolBudget = {hard = 40;};
        toolTimeoutMs = 600000;
        timeoutMs = 3600000;
        prompt = ''
          You are a Nix recon scout with two jobs.

          First, authoritative lookup: use `nix-search-tv` to confirm option
          and package facts — attribute path, type, default, and whether the
          thing exists at all in the pinned nixpkgs. Report the index you
          found it in.

          Second, structure: trace how this repo's dendritic module tree is
          wired — which files declare which flake.modules.* keys, what
          imports what, and the fold order. Cite exact paths and line numbers.

          Confirm before asserting. An option name that looks plausible is not
          evidence that it exists.
        '';
      };
      researcher = {
        description = "Autonomous web researcher that returns a sourced brief";
        tier = "worker";
        bundles = ["web"];
        tools = readOnly;
        toolBudget = {hard = 80;};
        prompt = ''
          You are a research subagent. Run focused web research and produce a
          concise, well-sourced brief that answers the question directly.
          Prefer primary sources; flag uncertainty and stale information.
        '';
      };
      reviewer = {
        description = "Read-only review of code diffs, plans, and PRs";
        tier = "executive";
        bundles = ["code" "lens"];
        tools = readOnly;
        toolBudget = {hard = 60;};
        prompt = ''
          You are a disciplined review subagent. Inspect, evaluate, and report
          findings with evidence; do not guess. Verify against source, tests,
          docs, and requirements. Use lens_diagnostics / lsp_diagnostics for
          type and structural checks. You are read-only: report what should
          change, never edit.
        '';
      };
      oracle = {
        description = "High-context decision-consistency oracle that prevents drift";
        tier = "orchestrator";
        bundles = [];
        tools = ["read"];
        toolBudget = {hard = 20;};
        prompt = ''
          You are the oracle: a high-context decision-consistency subagent.
          Treat inherited forked context as the authoritative contract and
          reconstruct the key decisions, constraints, and open questions
          before answering. Flag conflicts and drift; do not make new
          decisions on the orchestrator's behalf.
        '';
      };
      media = {
        description = "Vision/media analyst for video and documents";
        tier = "vision";
        bundles = ["media"];
        tools = ["read"];
        toolBudget = {hard = 40;};
        prompt = ''
          You are a media analyst. For videos, use the video-analyzer MCP
          tools to transcribe and inspect frames; for documents, use
          document_parse / document_search / document_screenshot. Report with
          timestamps or page references.
        '';
      };

      # ── Phase 5: write agents ─────────────────────────────────────────
      # Writers re-allow write/edit via per-agent permission overrides and are
      # bounded by timeoutMs, not toolBudget (§5). None of these may commit.
      # NOTE: `worktree` is a launch param, not a frontmatter field — the
      # orchestrator must pass worktree: true when launching the investigator
      # (see docs/pi-subagents-rollout.md §5b).
      investigator = {
        description = "Disposable-worktree investigator that tests hypotheses and reports findings";
        tier = "worker";
        bundles = ["code" "lens"];
        tools = ["read" "grep" "find" "ls" "bash" "write" "edit"];
        permission = {
          write = "allow";
          edit = "allow";
        };
        timeoutMs = 3600000;
        prompt = ''
          You are an investigator in a disposable worktree. Experiment
          freely — write throwaway code, run it, and iterate — then report
          findings with evidence. Do not propose keeping your changes: the
          worktree is discarded. Escalate rather than guess when a stop
          condition is unclear.
        '';
      };
      executor = {
        description = "Implementation agent that changes project files but never commits";
        tier = "executive";
        bundles = ["code" "lens"];
        tools = ["read" "grep" "find" "ls" "bash" "write" "edit"];
        permission = {
          write = "allow";
          edit = "allow";
        };
        timeoutMs = 3600000;
        prompt = ''
          You are an executor. Implement the requested change in the project
          tree, run the verification commands (build/test/lint), and report
          the diff and results. Never commit, merge, push, or open a PR —
          leave the working tree for the orchestrator to review and commit.
        '';
      };
      workspace = {
        description = "Google Workspace operator (Gmail, Drive, Docs, Calendar)";
        tier = "worker";
        bundles = ["workspace"];
        tools = ["read" "write" "edit"];
        permission = {
          write = "allow";
          edit = "allow";
        };
        timeoutMs = 3600000;
        prompt = ''
          You are a workspace operator. Use the google-workspace MCP tools to
          act on Gmail, Drive, Docs, Sheets, Calendar, and Contacts. Follow
          the google-workspace skill's guidance (auth, scoping, idempotency)
          before any mutating operation.
        '';
      };
      twin = {
        description = "Digital-twin memory keeper for the Obsidian vault";
        tier = "worker";
        bundles = ["vault"];
        tools = ["read" "write" "edit"];
        permission = {
          write = "allow";
          edit = "allow";
        };
        timeoutMs = 3600000;
        # Optional: the corporate vault has no digital twin yet (§9).
        # `perField` supplies the mkDefault, so a consumer flake flips this
        # with a plain `my.pi.agents.twin.enable = true;`.
        enable = false;
        prompt = ''
          You are the digital twin: keep the Obsidian vault's identity and
          memory notes accurate. Read the vault for context and update notes
          only when the orchestrator explicitly asks. Never invent or
          embellish facts.
        '';
      };
    };
  };
}
