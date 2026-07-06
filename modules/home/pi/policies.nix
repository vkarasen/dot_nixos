# Dendritic aspect: pi-policies (home-manager class).
#
# Generates ~/.pi/agent/AGENTS.md from my.pi.globalAgentPolicies — the
# global always-on context file that pi loads at startup unconditionally
# (not opt-in like a skill).
#
# This is intentionally a SEPARATE aspect from modules/home/pi/default.nix
# because the standalone packages.pi build evaluates homeManager.pi in
# isolation (without the generic my.* option modules), so any reference to
# config.my.* inside that module breaks the build.  Keeping this here means
# the standalone package build stays clean while the full home configuration
# picks up both aspects automatically via import-tree.
#
# To add policies from another aspect or from the corporate flake, just set
# additional keys on my.pi.globalAgentPolicies — the module system merges
# them.  Keys are sorted alphabetically before concatenation; use numeric
# prefixes to control order ("00-", "10-", "90-", …).
{...}: {
  flake.modules.homeManager.pi-policies = {
    lib,
    config,
    ...
  }: {
    # -----------------------------------------------------------------------
    # Base policy sections
    # -----------------------------------------------------------------------
    my.pi.globalAgentPolicies = {
      "00-nix-workspace" = ''
        # Nix workspace exploration policy

        Whenever a `flake.nix` is present in the workspace root, or the repo
        contains NixOS / home-manager / nixvim configuration, apply this policy:

        ## Lookup order — always prefer indexed / semantic sources
        1. **`nix-search` skill** for packages, Home Manager options, NixOS options,
           nixvim options.  Run this *before* touching any file path.
        2. **`nix-locate` / `nix-index`** to map a filename or binary to its package
           without scanning the store.
        3. **`lsp_navigation`** (definition, references, hover) for in-repo code.
        4. **`module_report` / `read_symbol` / `read_enclosing`** for Nix module
           structure and individual symbols.
        5. **`ast_grep_search`** scoped to the repo for structural queries.
        6. **Repo-local `rg` / `find`** when the above are insufficient.

        ## Hard rule — never brute-force the Nix store
        - Do NOT run `find /nix/store ...` for discovery.
        - Do NOT `grep -r` over `/nix/store`.
        - `/nix/store` is only inspectable by **exact, already-known path**.
        - The store is large; blind traversal will time out or exhaust context.

        ## Pi documentation
        Pi docs live at a pinned store path provided in the system prompt.
        Read those files directly by their known path — do not search the store
        for them.
      '';

      "20-git-workflow" = ''
        # Git workflow policy

        ## Commit approval — default: always wait
        Never commit, merge, or push unless the user has explicitly approved
        the exact final change set in this conversation, OR has given standing
        permission to commit freely for the current task.

        A plan, critique, or early draft does not count as commit approval. If
        the implementation changes after discovery, the earlier approval stops
        applying until the updated final diff or a precise summary of the actual
        edits has been shown and approved.

        "It looks good" or "go ahead" counts as approval for the specific
        change set just shown. It does NOT carry over to future changes in the
        same session unless the user says something like "commit as you go" or
        "you don't need to ask".

        When work is ready, show the final diff / summary and ask — don't
        assume a passing build is sufficient sign-off.

        ## Commit-making behavior
        If the user asks you to "make the commits" or something similar, first
        inspect the actual staging area and working tree (`git status`, staged
        vs. unstaged diff, and any file boundaries) and decide whether the
        changes should be split into atomic commits before doing anything.

        Default to a commit plan that mirrors real logical units of work.
        Do not bundle unrelated edits together.

        Use `git add -A` only when the whole working tree is clearly one
        commit-worthy unit or the user has explicitly asked for that scope.
        Never use `git add -A` as a reflex.

        If you can reasonably infer from the previous conversation that several
        changes belong to separate logical commits, do not ask for approval just
        because you are about to split them. Only ask if you encounter
        uncommitted changes that you have no memory of making or that do not fit
        the current task context.

        If implementation work discovers additional edits beyond the originally
        discussed draft, stop before committing, present the revised final diff
        or a precise summary of the actual changes, and wait for confirmation.

        When working inside any git repository, default to this toolset:

        - **`gh`** for all GitHub operations (PRs, issues, CI checks, releases).
        - **`wt`** (Worktrunk) for branch and worktree lifecycle — creating task
          branches, switching contexts, stacking work, merging, and cleanup.
          Prefer `wt` over raw `git worktree add/remove`, `git switch`, or
          `git checkout` for these operations.

        ## Worktree default
        For any non-trivial or exploratory piece of work, prefer a dedicated
        worktree over working directly on the default branch:
          wt switch --create <task-branch>
        Worktrees are cheap.  A separate worktree keeps the default branch
        clean and makes it easy to abandon, compare, or parallelise work.
        Skip the worktree only for genuinely trivial fixes (typos, one-liner
        config tweaks) where the overhead outweighs the benefit.

        ## When to raise a PR vs. merge locally
        Default to opening a PR (`gh pr create`) so there is a review record.
        Use `wt merge` for a local merge only when the repo or task context
        explicitly says PRs are not needed (e.g. a personal config repo).

        Load the **`worktrunk` skill** at the start of any task that involves
        branch creation, worktree management, PR workflows, parallel agents, or
        merge/cleanup.  The skill contains the full command reference and
        preferred patterns.
      '';

      "10-scripting" = ''
        # Scripting runtime policy

        Follow this decision tree in order — stop at the first match.

        ## 0. Check for an active devshell first
        A devshell may already provide project-specific tools and runtimes.
        Check before reaching for nix run or writing a script:
          echo $DIRENV_DIR      # non-empty → direnv is active (use flake / use nix)
          echo $IN_NIX_SHELL    # "impure" or "pure" → inside nix develop / nix-shell
        If a devshell is active:
        - For **project tasks** (tests, builds, project CLI tools): use whatever
          the devshell provides directly — no need for nix run wrappers.
        - For **auxiliary scripting**: the devshell informs what is available, but
          does not dictate what to use. A quick TypeScript snippet may be faster
          and cleaner than writing in the project language even if that runtime is
          on PATH. Use best judgment — optimise for clarity and speed of writing,
          not for consistency with the project language.

        ## 1. Prefer the common system CLI toolbox first
        This environment usually has a broad set of everyday engineering
        command-line tools installed system-wide and already on PATH. Use those
        directly when they are present.

        Do not wrap a command in `nix run` just because it exists in nixpkgs.
        Reach for `nix run` when the tool is missing locally, is niche or
        specialized, or is unlikely to be installed here.

        No script needed. Do not write TS/JS just to shell out to a single CLI.

        ## 2. Glue logic is needed → Node.js / TypeScript / JavaScript
        Use Node.js when the task requires:
        - conditionals, loops, or multi-step orchestration
        - JSON/text transformation beyond a single pipeline
        - filesystem operations across multiple paths
        - calling several tools and combining their output
        Pi is always wrapped with a Node.js instance available.

        ## 3. A specific runtime or library is needed → `nix run`
        Use `nix run nixpkgs#runtime -- script` to access Python, Ruby, etc.
        The Nix daemon is always accessible so this always works.

        ## Never mutate the environment
        Do not `npm install -g`, `pip install`, or otherwise modify the system
        environment to obtain a runtime.  Use `nix run` or a project devshell instead.
      '';

      "15-collaboration" = ''
        # Collaboration and problem-solving policy

        Assume the user is an experienced engineer and intends requests precisely.
        Do not guess missing intent or expand scope just because something seems
        plausible. If the request is underspecified, conceptually incomplete, or
        appears to imply a much larger change than stated, pause and confirm before
        proceeding.

        When a task involves code changes or other implementation work:

        1. Start in planning mode.
        2. Gather only the context needed to understand the request.
        3. Present a short game plan.
        4. Wait for confirmation before implementing, unless the user explicitly
           grants full autonomy for that task.

        If the user gives you free rein or says to just solve the problem, you may use
        broader judgment. Even then, prefer caution over exploration and do not chase
        side quests unless they are clearly necessary to solve the stated problem.

        When a likely fix does not resolve the issue, first consider whether the
        current environment, session, or devshell may be stale and need to be
        reloaded or re-entered. Surface that possibility to the user instead of
        automatically digging deeper.

        If a task starts to feel like it is expanding into a tangential investigation,
        stop and explain clearly:
        - what problem you encountered,
        - what you think is needed to proceed,
        - and why that may be outside the original scope.

        Prefer to come back early when:
        - the requested change seems much larger than stated,
        - the obvious fix did not take effect,
        - the environment may need a reload,
        - or additional conceptual clarification is needed.

        The goal is to collaborate carefully and explicitly, not to infer extra intent.
      '';

      "25-herdr-tab-naming" = ''
        # Herdr tab naming

        When running inside herdr (`HERDR_ENV=1`), a `rename_herdr_tab` tool is
        available. The first prompt of each session injects an instruction to
        call it before starting work. Also call it whenever the session topic
        shifts significantly.

        ## Label style
        - 2–4 words, lowercase noun phrase
        - Concrete and specific: `nixvim config`, `flake inputs bump`, `pr review`
        - Avoid generics like `chat`, `session`, `work`, or the bare repo name
      '';

      "18-documentation-drift" = ''
        # Documentation drift check

        Before completing a change that is likely to be committed, do a fast,
        high-signal pass for documentation drift.

        Prioritize:
        - nearby comments, docstrings, and inline notes
        - likely affected call sites or references to changed symbols, using cheap
          structural tools when available
        - README/docs/examples and other user-facing or workflow-facing
          documentation when the change could plausibly affect them
        - local skills, prompt templates, and repository-specific guidance
        - always-loaded policy or instruction files such as `AGENTS.md` and
          equivalent operational notes

        Keep the pass opportunistic, not exhaustive. Do not perform a repo-wide
        documentation hunt unless the change is broad enough to justify it.

        If documentation may be stale but you do not update it, explicitly flag
        that as follow-up work in the handoff.

        If the change is unlikely to affect documentation, you may skip the pass,
        but if there is any plausible drift, call it out.
      '';
    };

    # -----------------------------------------------------------------------
    # Herdr tab-rename extension + companion tsconfig.
    # The tsconfig uses paths relative to the deployed location
    # (~/.pi/agent/extensions/) so the LSP resolves pi's runtime modules.
    # -----------------------------------------------------------------------
    home.file.".pi/agent/extensions/herdr-tab-rename.ts".source =
      ./extensions/herdr-tab-rename.ts;
    home.file.".pi/agent/extensions/tsconfig.json".text = builtins.toJSON {
      compilerOptions = {
        target = "ES2022";
        module = "commonjs";
        strict = true;
        types = [ "node" ];
        paths = {
          "@earendil-works/pi-coding-agent" =
            [ "../npm/node_modules/@earendil-works/pi-coding-agent" ];
          "typebox" = [ "../npm/node_modules/typebox" ];
        };
      };
    };

    # -----------------------------------------------------------------------
    # Wire the merged sections into the pi global context file.
    # attrValues sorts alphabetically, so numeric key prefixes control order.
    # mkIf avoids creating an empty file when no policies are defined.
    # -----------------------------------------------------------------------
    home.file.".pi/agent/AGENTS.md" = lib.mkIf (config.my.pi.globalAgentPolicies != {}) {
      text = lib.concatStringsSep "\n\n" (lib.attrValues config.my.pi.globalAgentPolicies);
    };
  };
}
