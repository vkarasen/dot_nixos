# Pi subagents rollout — working notes

Status of the `pi-subagents` branch and the reasoning behind it. Written as a
handoff: the remaining phases are meant to be implemented *using* the subagent
system this describes, so anything a fresh session would otherwise have to
rediscover is recorded here.

Delete this file when the rollout lands.

---

## 0. Where to pick up

**Status:** phases 0, 0.5, 1 and the install are committed on branch
`pi-subagents`. `pi-subagents@0.62.0` and `pi-death-loop-guard@0.1.2` are
installed but **never exercised** — nothing here has been run even once.
`main` is untouched; merge with `wt merge` when satisfied.

### Bring it online

```bash
nh home switch . -c vkarasen     # from this worktree
exec $SHELL -l                   # PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS comes from
                                 # home.sessionVariables — an existing shell
                                 # will not have it
pi                               # new packages only load at startup
```

### Verify before trusting anything

```text
/subagents-doctor        installation health
/subagents-models        confirm deepseek/deepseek-v4-flash actually resolves
/subagents               list discovered agents
/subagents-watchdog check
```

If `deepseek-v4-flash` does not resolve, the watchdog silently has no model.
Fall back to `anthropic/claude-haiku-4-5` in
`modules/home/pi/default.nix` → `subagents.watchdog.main.model`.

### You are already the orchestrator — but nothing delegates on its own

There is no orchestrator mode to enter. `pi-subagents` registers a `subagent`
tool in the main session at startup, so the capability is present from the first
turn.

**But delegation is model-initiated, and no policy tells the model when to
delegate.** A frontier model holding full context will almost always just do the
work itself, because that is easier. So expect approximately zero spontaneous
delegation until the orchestrator policy lands (phase 1.5 + §4).

Until then, **ask explicitly**: *"use a scout to find where X is defined"*,
*"run three parallel scouts for A, B, C"*. That is the intended bootstrap mode —
manual delegation to learn what the agents are actually good at, before writing
policy that automates it.

### What will look different, and what will look broken but isn't

| | expect |
| --- | --- |
| Watchdog | a cheap review roughly every 10 tool results **in your own session**, arriving as a transcript-visible steer, plus an edit review at turn end. `/subagents-watchdog off` if noisy |
| Death-loop guard | silent unless a call repeats identically (warn 3 / block 5 / abort 3) |
| Builtin writers | **`worker`, `reviewer` and `delegate` will fail their edits** — global `write`/`edit` deny. Intended: bootstrap is retrieval-only. Not a bug |
| Read-only builtins | `scout`/`researcher`/`oracle` have no bash, so no `rg`, `git log` or `nix-search-tv` |
| Worktrees | `$XDG_CACHE_HOME/pi-subagents/worktrees`, unused until something requests `worktree: true` |

### First tasks, in order

1. **Scout sufficiency test.** Run a `scout` against a bounded question in this
   repo (e.g. *"which files wire the pi aspect into the home configuration, and
   what is the fold order?"*). The question being answered is whether
   `read,grep,find,ls` is enough for recon without bash. If it is not, that is
   evidence to add the `investigator` tier sooner — **not** to loosen the scout.
2. **Resolve §7 items 1–4 empirically.** Item 1 (does a `skill:` deny prune the
   catalog?) is the highest-value unknown; it decides whether children can be
   narrowed in repos we do not own.
3. **Re-measure the always-on payload.** The `subagent` tool description is now
   in every prompt; `toolDescriptionMode: "compact"` is available and unset.
   Method is in §2 — a probe extension capturing at `before_agent_start`.
4. **Then** phase 5, leading with `investigator` (§9).

Read §1 before optimising anything, §5b before adding a guardrail, and §8
before running `nix build` or `git stash`.

---

## 1. Why this exists — and the metric that was wrong

The goal is **cost reduction and better task performance**, not a smaller
context window. That distinction was arrived at the hard way, and it matters
enough to state first.

The first two phases measured and optimised the **always-on** payload (system
prompt + tool schemas). That is the wrong target:

- it is a **fixed** cost, and prompt caching makes it nearly free after turn one
- the whole 27KB saved by deferring the `worktrunk` tool is worth ≈ **$0.40 per
  session**

The real cost is **recurring**: anything read into the orchestrator's context is
re-sent on every subsequent turn. Session cost is therefore roughly quadratic in
content ingested, not linear, and *when* something is read matters as much as
whether it is read.

Estimated with Anthropic list prices, 30 orchestrator turns following the read:

| task | in-situ (Opus) | delegated | ratio |
| --- | ---: | ---: | ---: |
| web research, 40k → 600 | $2.400 | $0.165 (Sonnet) | 14.5x |
| 3× repo recon, 90k → 1.5k | $5.400 | $0.116 (Deepseek) | 46.6x |
| doc/PDF parse, 25k → 400 | $1.500 | $0.046 (Haiku) | 32.9x |
| **total** | **$9.300** | **$0.327** | **28.5x** |

The same set at 10 following turns is 18.5x — **the saving compounds with
session length**, because the summary a child returns is small and permanent
while the raw content it read is discarded.

Second failure mode, priced separately: one confused side quest (12 extra turns,
25k more read) costs ≈ **$2.49** in Opus versus ≈ **$0.30** inside a Sonnet
child. The saving is not just the cheaper model — a child's wreckage is
*thrown away*, whereas confusion in the orchestrator poisons every later turn.

**Consequences for design.** Optimise for (a) content never entering the
orchestrator, and (b) confusion being contained and discardable. Prompt size is
an attention concern, not a cost concern — worth managing, but never at the
expense of (a) or (b).

---

## 2. Shipped on this branch

| commit | change |
| --- | --- |
| `ee22ced` | `herdr-tab-rename.ts`: guard so delegated children never register `rename_herdr_tab`. Children inherit `HERDR_ENV`/`HERDR_TAB_ID` and would rename the *parent's* tab. Guards at factory time (`PI_SUBAGENT_*` env, headless argv) and again on `ctx.mode !== "tui"`. |
| `7219854` | `worktrunk-deferred.ts`: deactivate pi-worktrunk's tool at `before_agent_start`, re-activate via `activate_worktrunk`. −26,854 bytes always-on (−24.1%). |
| `c2e6082` | alejandra pass on `policies.nix` + `private.nix` (pre-existing drift; formatted up front so later diffs stay semantic). Output store path unchanged — provably no-op. |
| `878a464` | `my.pi.agentInvariants`: prohibitions-only block at the top of `AGENTS.md`, separately reusable for child prompts. |

Measured baseline before/after the worktrunk change, captured with a throwaway
probe extension at `before_agent_start` (exiting before any provider request):

```text
                        BEFORE     AFTER
system prompt           45,253    45,378
active tool schemas     66,000    39,021
                       ─────────────────
TOTAL always-on        111,253    84,399
```

System prompt composition: repo `AGENTS.md` 13,799 · global `AGENTS.md` 13,002 ·
skills catalog 9,203 (22 skills) · pi base 8,834.

Tool schema bytes by source, before: `pi-worktrunk` 27,410 (1 tool!) ·
`pi-lens` 17,228 (8) · `pi-docparser` 5,939 (3) · `pi-mcp-adapter` 4,301 (3) ·
builtins 3,201 (4) · `rpiv-todo` 3,106 (1) · `rpiv-web-tools` 2,640 (2) ·
`pi-blackhole` 1,676 (1) · `herdr-tab-rename` 499 (1).

**The skills catalog is not a viable target.** 9,124 bytes = 51% descriptions,
22% nix-store `<location>` paths, 27% XML scaffolding. Descriptions average 211
bytes and the best ones carry negative triggers (`herdr`'s "Do not use merely
because a task could benefit from a background terminal") which are exactly what
prevents misfires. Trimming attacks the routing signal. The only real lever is
*which skills are present per agent* — a phase 4/5 concern.

---

## 3. Locked decisions

- **Delegate retrieval and execution. Never delegate synthesis.** Synthesis —
  deciding what to do — stays in the frontier orchestrator. That is where
  confusion would compound.
- **Verification is a host-run command, never a model.** A confused agent cannot
  fake `nix build`.
- **Do not delegate work whose answer shape is unknown.** Delegation is a reward
  for having already reduced uncertainty, not a tool for reducing it. Debugging
  a broken flake bump is not delegable; answering "which files define X" is.
- **Three parallel read-only scouts** for retrieval, not one sequential scout.
- **No workflow engine.** `pi-extensible-workflows` evaluated and dropped — the
  need is context management, not deterministic orchestration.
- **Agent = tier × capabilities × role**, not "brain regions" grouped by either
  capability or task. Tier = model + thinking. Capabilities = a bundle declaring
  skills + extensions + tools + MCP *together*, so "tool allowlisted but its
  provider not loaded" is unrepresentable. Role = posture + policy prompt.
- **Two axes, decoupled** — this is the answer to "the structured approach can't
  be the whole solution":
  - **Capabilities** are repo-independent (a read-only scout is read-only
    anywhere) → *always* scoped.
  - **Context** is repo-dependent → *default open*, narrowed only where the repo
    is owned. The zero-config path must be the unowned one, because that is
    where adding files is not permitted.
- **Policy triage is prohibition vs procedure**, not by audience:
  - *prohibition* → enforce structurally if possible, else one always-on line
  - *procedure* → progressive: agent prompt, capability bundle, or skill — and
    it gets *longer* there, not trimmed
  Upfront specificity is cheap; stage-irrelevant guidance competing for
  attention is not.

### Model tiering

Private: Opus orchestrator · Sonnet / Deepseek-pro executive · Deepseek-flash
simple · Haiku where vision is involved. Corporate: `github-copilot` only.
Orchestrator tier must itself be configurable — not every session needs Opus.
Resolve via the existing `hasCopilot`/`hasDeepseek`/`hasAnthropic` ladder into
`agentOverridesByProvider`.

---

## 4. The delegation contract

**Invented here, not a pi API.** Three prose fields written per call, three
structured fields supplied by `mkAgent`:

| field | kind | mechanism |
| --- | --- | --- |
| GOAL | prose | the `task` string — an outcome, not an activity |
| FACTS | prose | `task` + `defaultReads` (files read before the first turn) |
| ESCALATE IF | prose | named stop conditions; `contact_supervisor` guidance is auto-injected by the intercom bridge |
| BOUNDARY | structured | `tools` allowlist, `cwd`, `permission:` rules |
| DONE WHEN | structured | `acceptance.criteria[]` |
| VERIFY | structured | `gate: "cmd"` — host-run, memoized per tree state |

**If VERIFY cannot be filled in, do not delegate.** That is the test.

FACTS exists so the child never rediscovers what the orchestrator already
established. Underspecified *exploration* is the thing to forbid.

Four points where a child can seek guidance rather than guess: blocking
`contact_supervisor` with `need_decision` (exempt from tool timeouts, 10-min
default); the structured acceptance report's residual-risks field; a fresh
context-free reviewer child; and the orchestrator's own final decision.

---

## 5. Verified mechanisms

Citations are to `nicobailon/pi-subagents` `docs/` unless noted.

**Control plane** (satisfies observe/steer/abort without kill):
`status` (`view: fleet|transcript`, ≤500 lines) · `steer`
(`steer|follow_up|auto`, FIFO of 20) · `interrupt` (cancels the turn, session
survives) · `stop` (terminal, `childId` stops one child, siblings continue) ·
`resume` (revives from persisted `.jsonl`, exclusive cross-process lease).
Missions under `~/.pi/agent/missions/projects/<project-hash>/` survive reboot.

**Agent discovery** (`agents.md`), lowest → highest priority: builtin ·
installed package · **user `~/.pi/agent/agents/**/*.md`** · project
`.pi/agents/**/*.md`. Project wins name collisions. `agentScope:
user|project|both` (default `both`).
→ *home-manager generates the user tier; the corporate flake just adds keys to
`my.pi.agents` / `my.pi.capabilityBundles`. Additive merge, no coordination.*

**Context inheritance defaults are already the graceful fallback:**
`inheritProjectContext` defaults **true** for builtins (children follow repo
`AGENTS.md`/`CLAUDE.md` out of the box); `inheritGlobalContext` defaults
**false** and only takes effect when project context is on. So prose you don't
own is inherited wholesale; prose you own is excluded and curated. **The shared
work repo needs no changes at all.** Custom agents start clean, so `mkAgent`
must set these explicitly.

**Per-repo override without redefining an agent:** `settings.json` →
`subagents.agentOverrides.<name>`; project beats user. Fields: `description`,
`output`, `outputMode`, `defaultReads`, `model`, `defaultProvider`,
`fallbackModels`, `thinking`, `systemPromptMode`, `inheritProjectContext`,
`inheritGlobalContext`, `inheritSkills`, `defaultContext`, `acceptanceRole`,
`disabled`, `skills`, `tools`, `systemPrompt`. Anchored to the git worktree root
(`projectRootResolution: "git-root"`), so it composes with `wt` worktrees.
There is **no** path-keyed override stored outside the repo — per-repo config
means a file in the repo. For an unowned repo, `.git/info/exclude` keeps it
local.

**Tools allowlist:** omitted = normal builtins; empty = `--no-tools`; `mcp:`
entries forwarded as direct MCP selections; path-like entries treated as tool
extension paths. **Allowlisting a name does not load its provider** — before the
first model turn the child diffs declared names against the filtered registry
and **fails closed**, naming the missing tools. Load providers via `extensions`
or `subagentOnlyExtensions` (the latter loads only in children).

**MCP:** requires `pi-mcp-adapter` *and* explicit `mcp:` frontmatter entries —
global `directTools: true` is insufficient. Metadata is cached at startup, so
**restart pi after adding a server**. Servers spawn **per child** via `npx`, so
MCP must never land on a fan-out agent.

**`bash` is not gateable by pi-subagents** (`watchdog.md`): "Bash rules are
rejected rather than parsed, gated, denied, or audited." Non-bash tools do have
a real `allow`/`ask`/`deny` gate arbitrated by a watchdog model. A headless
child cannot answer `ask`. → **This is why `pi-permission-system` is in the
plan** (§6); `pi-guard` was the alternative and is dropped.

**`toolBudget` hard caps block read/search tools too** and can strand
half-applied edits — read-only agents only. Bound writers with `timeoutMs`.

**Skills discovery** is project-first over 7 levels, starting at
`.pi/skills/{name}/SKILL.md`. `skills` selects specific skills regardless of
`inheritSkills`; `skillPath` adds invocation-private candidates that never enter
the parent catalog.

**Set `PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS=1000`.** Wide fan-out contends on a
single `status.json`; the default retry ladder parks the thread synchronously
for ~7.9s and presents as a hung process at 0% CPU.

**Package verdicts** (children inherit all 13 installed packages unless
allowlisted): `pi-lens` heaviest (LSP + knip/jscpd/madge/gitleaks/trivy at
`session_start`) → executor/reviewer only · `pi-worktrunk` can merge/push → vcs
bundle only · `rpiv-web-tools` burns Tavily credits → researcher only ·
`pi-mcp-adapter` only where `mcp:` entries exist · `pi-docparser` media only ·
`rpiv-todo` and the pure-TUI packages (`pi-catppuccin`, `pi-vim`, `pi-fzfp`,
`pi-usage`, `pi-quotas`) excluded. `pi-blackhole` is fine —
`observeAfterTokens: 30000` means short scouts never trigger observation;
`PI_BLACKHOLE_PASSIVE=1` disables observer workers if needed.

---

## 5b. Design corrections that arrived late

Both of these reversed an earlier decision on this branch. They are recorded
because the reasoning is not obvious from the resulting config, and both would
otherwise be re-litigated. Operational state is in §0.

### The threat model, and why one obvious package is absent

The risk being managed is **drift** — an agent spiraling into unrequested
debugging and "fixing" — not malicious input. That distinction decided the
tooling.

`@gotgenes/pi-permission-system` was evaluated and **rejected**; §6 keeps the
research so it is not redone. It gates *syntax*, and drift is *semantic*: a
drifting agent runs perfectly ordinary commands. `git commit` is not dangerous
as a command, only as a decision at the wrong moment. It also floors `timeout`,
`env` and `sudo` to `ask` regardless of rules, so the cost would be approval
fatigue — which makes catastrophic approvals *more* likely.

**Nothing in the current setup asks. Keep it that way.** If a future guardrail
needs a prompt to work, that is a strong signal it is aimed at the wrong threat.

### Roles are separated by blast radius, not by read vs. write

"Read-only" was an early framing error. An agent that cannot write cannot test a
hypothesis, and hypothesis-testing is what separates an investigator from a
guesser — the two highest-value results on this branch (the context-baseline
probe, the 11-case shim harness) both required writing and running throwaway
code. Worse, write-run-read-fix-rerun is the most token-heavy loop there is, so
a taxonomy with nowhere to put it forces exactly that loop back into the
frontier model, defeating §1.

| Role | reads | writes | blast radius |
| --- | --- | --- | --- |
| `scout` | project | — | none |
| `investigator` | project | scratch + own worktree | **discarded** |
| `executor` | project | project files, bounded | gated by VERIFY + review |
| `reviewer` | project + diff | — | none |

The investigator is enforced by `worktree: true`, not by a path rule — the
boundary is a filesystem location, with no pattern to evade. `worktreeSetupHook`
returns `syntheticPaths` to keep helper files out of diff capture, which is what
that hook is for. `modules/home/pi/prompts/investigator.md` already exists and
needs rewording for this: not "avoid edits" but "you are in a disposable
worktree — experiment freely, report findings, do not propose keeping your
changes".

The wider direction is *sandbox the environment, not the tool list* — tool
allowlists are brittle because capability is fungible; filesystem boundaries are
not. A worktree is the cheap 90%. The strong local version would be `bwrap` with
a read-only project bind and a writable `/tmp`, wired through a
`PI_SUBAGENT_PI_BINARY` wrapper. Do not build that speculatively.

---

## 6. `@gotgenes/pi-permission-system` — evaluated and rejected

Closes the bash gap and replaces `pi-guard`. Two-layer model, no code coupling:
layer 1 (pi-subagents `tools:`) controls *visibility*, layer 2 (`permission:`
frontmatter) controls *policy* — `allow`/`ask`/`deny` per tool, bash pattern,
MCP op, skill, and path. Their author guide's compatibility example is literally
`nicobailon/pi-subagents`. Most-restrictive-wins across both layers.

Denied tools are **hidden before the agent starts** — not a cheap failure, an
absent tool: zero wasted turns *and* a smaller child prompt.

**The largest win is in the interactive session, not the children.** `bash: {
"git commit *": "ask", "git push *": "ask" }` turns the top-priority policy
("never commit without approval") into a prompt that cannot be deprioritised —
and lets the prose be **deleted** rather than relocated. `ask` needs a UI, which
the orchestrator has.

`path_write: { "*": "deny" }` is the documented read-only-agent posture. This
supersedes the earlier plan of stripping `bash` from scouts, which would also
have cost them `rg` and `nix-search-tv`.

Handshake with nicobailon: child **detection works** (it accepts
`PI_SUBAGENT_CHILD_AGENT` and `PI_SUBAGENT_RUN_ID`, both of which nicobailon
sets). `ask`-**forwarding likely does not** — nicobailon sets
`PI_SUBAGENT_ORCHESTRATOR_TARGET`, which is not among the accepted parent-session
vars (`PI_SUBAGENT_PARENT_SESSION`, `PI_SUBAGENT_SESSION`,
`PI_SUBAGENT_SESSION_ID`, `PI_AGENT_ROUTER_PARENT_SESSION_ID`). **Use
`allow`/`deny` only in children**; a child should escalate via
`contact_supervisor`, not block on a permission prompt.

Risks:

- **194 releases, 30 majors, 121 days — a breaking release every ~4 days.** An
  outlier against the ecosystem's usual backwards-compatibility record. Repo
  policy is currently unpinned pi packages (accepted deliberately, pending a
  nixvim-style pi flake); this is the one worth pinning explicitly and watching.
  Mitigation: generate **all** policy from Nix (global `config.json` via
  `home.file`, per-agent `permission:` via `mkAgent`) so a config migration is
  one Nix edit.
- **Issue #815** — a surface catch-all `deny` can hide `bash` entirely even with
  more permissive nested patterns. **Write allow-with-denies, never
  deny-with-allows.**
- **Issue #840** — an unparsed bash subtree is matched as an ordinary unit
  instead of failing closed. Complex compound commands may evade a pattern.
- **Not a sandbox** (says so itself). This is a guardrail against drift and
  accident — an agent that commits because it forgot — not against an adversary.
  Matches the threat model; keep the throwaway-worktree idea as cheap defence in
  depth rather than making it load-bearing.

---

## 7. Unverified — test before designing on these

1. ~~`skill:` deny surface~~ **RESOLVED** — there is no per-skill deny surface.
   Narrowing works via the `skills` allowlist + `inheritSkills` flag, and both
   *prune* (remove from the child prompt) — no "blocked loading" state exists.
   But the allowlist resolves skill names by **directory basename**, not the
   SKILL.md frontmatter `name`, so store-path skills resolve only under their
   hash-prefixed basename. Details + design fix below.
2. ~~`tools: "inherit"`~~ **RESOLVED** — an *override-surface* value only
   (`settings.json agentOverrides`), not a frontmatter value. It reaches builtins
   always, and custom agents only when their frontmatter omits `tools` (the
   `agentHasFrontmatterField` guard). In a custom agent's own frontmatter,
   `tools: "inherit"` is parsed as a literal tool name `inherit` and fails closed.
   The escape hatch for `mkAgent` is to **omit `tools`** (omitted = ambient tools).
3. ~~`ask` forwarding~~ **MOOT** — the permission system (§6) was dropped, the
   current `permissions.rules` are allow/deny only (no `ask`), and §5b says keep
   it that way. Children escalate via `contact_supervisor`, not permission
   prompts.
4. ~~merge or replace~~ **RESOLVED** — independent channels, so they **merge**
   (union). All 12 builtins set `inheritSkills: false` (and
   `defaultInheritSkills()` returns `false`), so builtin children inherit **no
   skills catalog at all** — the "unowned repo's catalog" hole does not exist for
   skills. Details below.
5. **Does pi honour `npm:<pkg>@<version>`** in `my.pi.packages`?
6. **Is `PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS` actually needed** at our fan-out
   width (3–5), or only at much wider ones?

### Resolved: skill wiring (items 1 & 4)

Verified empirically (pi-subagents@0.62.0) and against `src/agents/skills.ts`:

- **No per-skill deny surface exists.** `excludeSkills` / negative selection:
  absent. The only controls are `skills` (explicit allowlist) and
  `inheritSkills` (bool). Both *prune* what appears in the child prompt; there
  is no mechanism that lists a skill but blocks reading it.
- **`skills` names skills by directory basename, never the frontmatter `name`.**
  `settings.json skills` are `/nix/store/…` paths, so their resolvable name is
  the hash-prefixed basename (`f7qq33xlc71s9bcfa64v9rxhi7kkzmlv-nix-search-skill`),
  not the logical name (`nix-search`). Live test: `skill: "nix-search"` injected
  nothing; `skill: "<store-basename>"` injected one correctly-loadable entry.
  pi-core (the parent session) names the *same* skill `nix-search` from its
  frontmatter, so parent and child naming disagree.
- **`inheritSkills` and `skills` are independent → they merge, not replace.**
  `inheritSkills: false` (the universal builtin default) sends `--no-skills`;
  `skills: [a,b]` injects a *separate* `<available_skills>` block. Both set →
  union. But since builtins default to `inheritSkills: false`, children start
  with zero skills and nothing from an unowned repo leaks in.

**Design consequence for phase 2:** a bundle's `skills: [nix-search, …]` will
silently no-op under store-path naming. Fix by pairing it with **`skillPath`**
pointing at a Nix-materialised tree of logical-name dirs
(`~/.pi/agent/agents/skills/<name>/SKILL.md`), so `skillPath: ./skills` +
`skills: [nix-search]` resolves by logical name and is rebuild-stable (store
basenames change every rebuild; logical dir names do not). `skillPath` already
exists for exactly this (§5: "local matches take precedence"). Alternatives:
inject always-needed skill content via `defaultReads`/system prompt (drops
on-demand loading), or `inheritSkills: true` (drops narrowing). Not a redesign —
a wiring detail.

---

## 8. Repo gotchas hit during this work

- **`git add -NA` before `nix build`.** Untracked files do not exist to the
  flake (repo AGENTS.md pitfall #1). Bit this once.
- **Never `git stash` with intent-to-add entries present** — the stash silently
  fails to create. Nearly lost three changes; verify with `git stash list`.
- **`modules/_nixvim/lsp.nix` and `modules/home/neovim/default.nix` have
  pre-existing alejandra drift.** Left alone deliberately — out of scope. Do not
  bundle a reformat into an unrelated commit; it cost 644 lines of churn on
  `policies.nix` before being reverted.
- **TS files under `modules/` show LSP warnings** (`Cannot find module 'pi'`,
  `process` undefined). Environmental: no tsconfig covers `modules/**`, and the
  files are loaded by pi's jiti runtime, not compiled here. 12 such warnings
  exist on `main`. Not cascade errors.
- **pi-worktrunk registers its tool inside its own `session_start` handler,
  after an `await`.** Hooking `session_start` to modify it is racy — use
  `before_agent_start`.
- Verify generated-file changes by **store path**, not by eye:
  `nix build --out-link` then compare
  `result/home-files/.pi/agent/AGENTS.md`. An identical hash is proof a
  refactor was content-neutral.

---

## 9. Remaining phases

### Why the numbering is not the running order

These are dependency phases, not an execution order — **§0 is the running
order.** The inversion is deliberate: the rest is meant to be built *using*
subagents, and the **builtin** agents need none of the scaffolding below
(`inheritProjectContext` already defaults true, so a builtin scout follows this
repo's `AGENTS.md` on day one). So the install came first and the custom layer
is built with its help.

When delegating that work: do not delegate the scaffolding *design* (§3 — never
delegate synthesis). Delegate reading upstream docs, enumerating option names,
and drafting per-agent frontmatter from a settled spec.

**1.5 — write the contract** into the orchestrator policy, annotated with which
fields are prose and which are real parameters (§4).

**2 — Nix scaffolding.** `my.pi.modelTiers`, `my.pi.capabilityBundles` (each
declaring skills + extensions + tools + mcpTools + `policy` prose together),
`my.pi.agents`, and `mkAgent` in `modules/home/pi/_agents.nix` (underscore-
prefixed: helper, not a flake-parts module). `mkAgent` emits one markdown file
per agent into `~/.pi/agent/agents/`, injects `my.pi.agentInvariants` verbatim,
and sets `inheritProjectContext`/`inheritGlobalContext`/`inheritSkills`
explicitly. Proposed bundles: `code` (pi-lens, ast-bro) · `nix` (nix-search,
userspace-mounts, bundle-module, pi-config) · `web` (rpiv-web-tools) · `vault`
(obsidian-read/-maintenance) · `workspace` (google-workspace MCP,
linkedin-profile) · `media` (video-analyzer MCP, pi-docparser) · `vcs`
(worktrunk, gh, git). Bundle `skills` must be wired via `skillPath` + a
materialised logical-name tree, not bare logical names — see §7 (resolved,
items 1 & 4).

**2.5 — permissions.** ~~Install a permission system.~~ **Dropped** — see §5b.
The replacement is already in place: native child `write`/`edit` denies, no bash
for read-only roles, and worktree isolation for anything that writes. `mkAgent`
still gains a `permission` attr, since custom agents override the global rules
per-agent with a `permission:` frontmatter block — that is how the investigator
gets write access inside its worktree.

The commit-approval prose therefore does **not** get deleted yet. It was going
to be retired by a gate that no longer exists; retiring it now would remove the
only thing covering the orchestrator, which is the one agent with no capability
restrictions at all. Revisit once drift monitoring has a track record.

**3 — install.** `pi-subagents` **done**. Still outstanding: `pi-intercom` for
`contact_supervisor` escalation; making `label` mandatory in the spawn
convention (the orchestrator names a child's herdr pane — the child must never
name its own, and cannot: see `ee22ced`); `toolDescriptionMode: compact`.
**Resolve §7 items 1–4 here**, empirically.

**4 — read-mostly agents:** `scout` (cheap/code), `nix-scout` (cheap/nix),
`researcher` (worker/web), `reviewer` (executive/code, read-only — note this
deliberately *shadows* the builtin `reviewer`, which does "small fixes"; user
agents win name collisions), `oracle` (orchestrator tier, no tools), `media`
(vision/media). All `readOnly`, all with
`toolBudget` hard caps. Measure a real scout run before narrowing this repo's
context — do not guess the narrowing up front.

**5 — write agents + twin:** `investigator` (worker tier, `worktree: true`, full
tools inside it, `permission:` frontmatter re-allowing write/edit, bounded by
`timeoutMs` not `toolBudget` — see §5b; this is the highest-value one and should
probably come first), `executor` (executive/code+vcs, cannot commit),
`workspace` (worker/workspace), `twin` (worker/vault). `twin` needs
`enable = mkDefault false` — the corporate vault has no digital twin yet, so it
must be optional rather than a stub. Per-agent memory: frontmatter
`memory: { scope: project|user, path }`, first 200 lines of `MEMORY.md` injected;
agents without write tools get a read-only memory block.

**6 — `pi-herdr-fanout`** (bespoke, ~150 lines over the herdr CLI): budding off N
independent *head* sessions in their own panes from one query ("run reviews on
all open PRs assigned to me"). `pi-subagents`' `project.open` is one-pane-per-cwd
and cannot inspect or steer subagents inside a peer session, so it is close but
not sufficient. Lowest priority — no third-party package does peer-session
fan-out properly.

**7 — re-measure.** Not the always-on payload (§1) — measure **cost per
completed task** and orchestrator context growth per task.

### Open questions for the user

- Is the always-open default acceptable in repos he *does* own, pending the
  phase-4 measurement?
- Corporate flake will need its own `jira` bundle (MCP + skills). Base flake
  should not know about it — confirm the additive-keys approach is enough.
- Once §7 item 1 resolves, decide whether to narrow this repo's 13.8KB
  `AGENTS.md` for children, or leave it inherited whole.
