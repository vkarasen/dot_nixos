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
        the changes in this conversation, OR has given standing permission to
        commit freely for the current task.

        "It looks good" or "go ahead" counts as approval for the specific
        change just shown.  It does NOT carry over to future changes in the
        same session unless the user says something like "commit as you go" or
        "you don't need to ask".

        When work is ready, show the diff / summary and ask — don't assume a
        passing build is sufficient sign-off.

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

        ## 1. A single CLI invocation does the job → `nix run`, always
        If a tool exists in nixpkgs and one invocation is enough, just run it:
          nix run nixpkgs#jq -- '.foo' file.json
          nix run nixpkgs#ripgrep -- 'pattern' path/
        No script needed.  Do not write TS/JS just to shell out to a single CLI.

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
