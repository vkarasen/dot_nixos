# Pi subagents rollout — working notes

Status of the `pi-subagents` branch and the reasoning behind it. Written as a
handoff: the remaining phases are meant to be implemented *using* the subagent
system this describes, so anything a fresh session would otherwise have to
rediscover is recorded here.

Delete this file when the rollout lands.

---

## 0. Where to pick up

**Status:** the system is live and exercised — 9 agents (3 writers), the
`05-delegation` orchestrator policy, per-field tier/bundle overrides, and an
hour-long escalation window. This is a working harness, not a rollout plan.
`main` is untouched; merge with `wt merge` when satisfied.

### Bring it online

```bash
nh home switch . -c vkarasen     # from this worktree
exec $SHELL -l                   # sessionVariables: PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS
                                 # and PI_INTERCOM_ASK_TIMEOUT_MS — a shell that
                                 # predates the switch will not have them
pi                               # new packages load only at startup
```

### You are already the orchestrator

There is no orchestrator mode to enter: the `subagent` tool is registered in
the main session at startup. Delegation is model-initiated, and the
`05-delegation` policy in your always-on context now tells the model when to do
it. If it still doesn't delegate spontaneously, the fix is a more concrete
trigger, not more prose. You can always ask explicitly ("three parallel scouts
for A, B, C").

### The current shape

Agent = tier × bundles × role. Tiers are `my.pi.modelTiers`; the `orchestrator`
tier *is* the interactive session's default model/thinking, so "the model I
talk to" and "the tier that routes delegation" are one knob. Bundles are
`my.pi.capabilityBundles` (skills + extensions + tools + mcp + policy prose,
together). Agents are `my.pi.agents`, rendered to `~/.pi/agent/agents/*.md` by
`_agents.nix`. Base values live in `modules/home/pi/agents.nix`. Defaults are
applied per FIELD (§3), so a consumer override of one key or field leaves the
rest intact — never wrap a whole attrset in `mkDefault`.

### Where each thing is documented

| need | go here |
| --- | --- |
| option semantics (the reference) | `modules/options.nix` — descriptions are current |
| wire tiers / add agents (mechanics) | `skills/corporate-pi-wiring/SUBAGENTS.md` |
| local recipes (skills, packages, policies, agents) | `.pi/skills/pi-config/SKILL.md` |
| why these decisions (principles) | §3 below |
| repo gotchas | §8 below |

### Verified working — do not re-test

Interrupt/resume (context survives the pause, revived under a new run id), the
escalation loop (`contact_supervisor` blocks → supervisor decides → child
resumes), per-agent model routing, npm:-prefixed extension bundles under a
strict tools allowlist, and per-launch re-read of agent definitions (edit
`agents.nix`, no pi restart needed).

### Still unverified — test before designing on them

- **Steer mid-turn** — the control plane exists; a live steer of a running
  child has never been exercised here.
- **The fleet inspector `H` → herdr pane** — only opens on an *active* async
  child, so it needs a live target; unconfirmed.
- **The `/subagents-fleet` hotkey (`Ctrl+Alt+F`)** — registered in code but not
  confirmed firing in your terminal; `/subagents-fleet` works.
- **`pi-herdr-fanout`** — the N-peer-session fan-out, unbuilt (§9.6).
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
re-sent on every subsequent turn.

### Correction: the driver is round-trips, not content (measured 2026-09-01)

The original claim here was that session cost is quadratic in *content
ingested*. Measurement says otherwise. From a live Opus session's own JSONL,
twelve consecutive requests:

```text
ctx  91k -> $0.103      ctx 103k -> $0.070
ctx  96k -> $0.088      ctx 105k -> $0.061
ctx  99k -> $0.072      ctx 108k -> $0.080
ctx 101k -> $0.059      ctx 111k -> $0.128
```

**Cost per request is a function of context size, not of what the request
does.** A request reading 200 bytes costs the same as one reading 20KB. So the
quantity to minimise is *frontier round-trips taken while context is large*,
not bytes ingested.

This inverts the intuition about what is worth delegating:

- **Best** target: many small tool calls (12 reads of 2KB each = 12 avoided
  $0.09 round-trips, near-zero content).
- **Worst** target: one big read (a single round-trip, and you probably want
  the content anyway).

Measured on this branch: 7 child runs / 23 child requests cost **$0.0196**
total. The same 23 round-trips inside an Opus session at ~115k context would
have been **≈$1.90** — about **95x** — before counting the permanent context
the orchestrator never took on.

**Second correction: Anthropic children pay a boot tax.** A one-shot `media`
child on `claude-haiku-4-5` billed 14,457 **cacheWrite** tokens — $0.018 of a
$0.023 run — to write a prompt cache it never re-read. Deepseek bills zero
cacheWrite. A/B on an identical vision task: `deepseek-v4-flash-vision-exp`
and `claude-haiku-4-5` were both 100% accurate at $0.0019 vs $0.0228. Prefer
deepseek for short-lived children; Anthropic caching only pays back across
many turns.

The original estimates below are left for the reasoning, but they undercount
by modelling content rather than round-trips.

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

## 2b. Current mechanisms (added after §2 was written)

| mechanism | where | one line |
| --- | --- | --- |
| per-field defaults | `agents.nix` `perField` | consumer overrides one key/field; whole-attrset `mkDefault` silently wipes siblings — for `agents` it was SILENT |
| session = orchestrator | `default.nix` | `defaultModel/Provider/ThinkingLevel` derive from `modelTiers.orchestrator` |
| escalation window | `default.nix` `PI_INTERCOM_ASK_TIMEOUT_MS=3600000` | effective wait = min(ask, agent `timeoutMs`); bounded agents raised to match |
| stop-on-expiry | `policies.nix` invariant `30-supervisor-expiry` | child stops and reports "no decision" instead of guessing on an expired ask |
| per-tool timeout | `my.pi.agents.<n>.toolTimeoutMs` | bounds one hung tool (bash) without shrinking the run window |
| persistent memory | `my.pi.agents.<n>.memory {scope,path}` | pi-subagents `memory` frontmatter; first 200 lines of MEMORY.md injected; twin is the intended first user (still disabled) |

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
- **A bundle owns its prerequisites, including `bash`.** The mirror of the rule
  above, and it was missed on the first pass: the `nix` bundle shipped the
  `nix-search` skill to a bash-less agent, so the skill was pure prompt tax for
  a capability that could not be exercised — and an invitation to try anyway.
  A bundle must carry every tool its skills require. Where that tool is `bash`,
  the bundle also carries a `policy` block scoping what the shell is for, and
  the agent moves up a tier: flash-at-low-thinking is the wrong model to hold a
  prose constraint about shell use. Both compensations are advisory — prose
  does not enforce — so this is a deliberate, priced trade, not a safe one.
  The structural exit is to stop needing a shell: wrap `nix-search-tv` as a
  native pi tool or MCP server, then the bundle drops `bash` and its policy.
  Verified after the change: nix-scout ran 8 `nix-search-tv` calls and nothing
  else, correctly reported three non-existent option paths as absent rather
  than inventing them, and volunteered the real attribute path — $0.007 for
  work that would have been ~10 Opus round-trips.
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

**Superseded 2026-09-01.** `agentOverridesByProvider` is not used at all. Tiers
are declared directly in `my.pi.modelTiers`, defaulting to the deepseek ladder;
the `hasCopilot`/`hasDeepseek`/`hasAnthropic` ladder in `default.nix` survives
only as the FALLBACK for when no orchestrator tier is readable — i.e. the
isolated `packages.pi` build.

**The `orchestrator` tier IS the session default.** You always drop into an
orchestrator and delegate from there, so `defaultModel` / `defaultProvider` /
`defaultThinkingLevel` are derived from that single tier instead of being
declared independently. Repointing it moves both the session you type into and
the routing for every delegation, so a consumer flake states "use copilot"
once rather than in two shapes that can silently disagree.

**Option defaults are applied per FIELD, not per attrset.** `lib.mkDefault` on
a whole attrset lowers the priority of the *entire* definition, so a consumer
flake defining one key discards every sibling. Measured with `evalModules`: a
corporate `modelTiers.orchestrator = {…}` dropped worker/simple/vision/
executive. For tiers and bundles that fails loudly (`_agents.nix` throws
`unknown tier` / `unknown bundle`), but for `my.pi.agents` it is **silent** —
the base roster simply stops being written, and the generated roster table in
AGENTS.md shrinks to match, so the result looks self-consistent. `perField` in
agents.nix pushes the default down to each field, and is idempotent so a field
that already carries its own `mkDefault` is not double-wrapped (that produces
`mkDefault (mkDefault x)`, and the module system unwraps only one level).

Verified against a simulated corporate flake that repointed the orchestrator
tier to copilot, tweaked one field of another tier, added a new tier, added a
new agent and enabled `twin`: 11 agents rendered, the session default followed
the tier to `github-copilot/claude-sonnet-5`, `worker` kept its inherited
model while taking the new thinking level, and agents on untouched tiers were
byte-identical.

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
or `subagentOnlyExtensions` (the latter loads only in children). A non-empty
`extensions:` list **replaces** ambient extensions (`--no-extensions` + only the
listed ones) rather than adding to them — so any bundle that needs MCP must
list `pi-mcp-adapter` itself (verified in the child launch arg builder,
`pi-args.ts`). And `--tools` is a **strict allowlist over all tools** —
built-in, extension, and custom alike — so an extension's tools must also be
named explicitly in `tools`; loading the extension alone does not surface them
(pi `usage.md`). `extensions` entries are passed to `pi --extension`, so npm
packages need the `npm:` prefix — bare names resolve as filesystem paths and
fail the child launch.

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
boundary is a filesystem location, with no pattern to evade. **Correction:**
`worktree` is a *launch param*, not a single-agent frontmatter field — a
frontmatter `worktree: true` is inert (verified: the child ran in the repo and
wrote there). The orchestrator must pass `worktree: true` in the launch, which
is a delegation-contract boundary (§4), not something `mkAgent` can emit.
`worktreeSetupHook`
returns `syntheticPaths` to keep helper files out of diff capture, which is what
that hook is for. The investigator agent's prompt (in `agents.nix` — the
prompt-template personas were removed) already carries this wording: "you are
in a disposable worktree — experiment freely, report findings, do not propose
keeping your changes".

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
- **`nix build` and `nix flake check` do not test the same thing, and phase 2
  shipped broken because of it.** Declaring `my.pi.modelTiers` /
  `capabilityBundles` / `agents` inside `modules/home/pi/default.nix` left
  `nix build .#homeConfigurations.vkarasen.activationPackage` green while
  `nix flake check` failed on ``The option `my' does not exist``:
  `modules/flake/wrapped-packages.nix` evaluates
  `flake.modules.homeManager.pi` in isolation for `packages.pi`, without the
  generic my-options module. Fixed by moving the roster into a sibling aspect,
  `modules/home/pi/agents.nix` — the same split, for the same reason, that
  `policies.nix` already uses. Now repo AGENTS.md pitfall #6. Run
  `nix flake check`, not just `nix build`.
- **Do not run `alejandra` over all of `modules/`.** `modules/_nixvim/lsp.nix`
  and `modules/home/neovim/default.nix` carry pre-existing drift that is out of
  scope (see below); a directory-wide format pulls them into the diff. Scope it
  to the files you touched.
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

> **Status (2026-09-01):** phases 1.5, 2, 3, 4 and 5 are DONE. Open: 6
> (`pi-herdr-fanout`, unbuilt) and 7 (re-measure cost/task — §1 has partial
> numbers). The `label` item under 3 is obsolete: `label` is workflow lane
> metadata, not a launch param, and a single-child launch cannot be named.
> `pi-intercom` was never installed — `contact_supervisor` turned out to be
> native to pi-subagents.

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

**1.5 — write the contract** into the orchestrator policy. **DONE** —
`my.pi.globalAgentPolicies."05-delegation"` in `modules/home/pi/policies.nix`.
Orchestrator-only by construction (children have no `subagent` tool, so it
would be pure attention tax, and it is procedure not prohibition).

The roster table inside it is **generated from `my.pi.agents`**, not written as
prose: a hand-written table is wrong by construction in any consumer flake that
adds agents additively, and it would drift the first time a tier changed. It
renders model, description, and the flags an orchestrator actually gets wrong
(`no bash`, `writes`, budget cap). Cost: AGENTS.md 13.6KB -> 18.8KB always-on,
about $0.08/session — bought back by the first delegated retrieval.

Two empirical findings drove the content, and neither was anticipated:

1. **A child may decline to escalate.** Told explicitly to `contact_supervisor`
   about a manufactured ambiguity, a scout evaluated the premise, judged it
   false, and answered anyway. Correct reasoning, but it means `ESCALATE IF` is
   advisory. Escalation is a convenience, never a safety net. (The mechanism
   itself is verified working against a *genuine* ambiguity: child blocked,
   supervisor decided, child resumed and honoured the decision.)
2. **Child output is a draft, not a fact.** A scout returned a nine-row
   capability table that was correct except for one column, wrong in three
   rows, unhedged, in the least conspicuous place. Hence the policy's rule to
   verify any load-bearing claim with one deterministic host command, and to
   always demand `file:line` citations — a citation makes verification a single
   `grep`.

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

**3 — install.** `pi-subagents` **done**. `pi-intercom` was NOT needed —
`contact_supervisor` is native to pi-subagents. The `label` convention is
obsolete (`label` is workflow lane metadata, not a launch param — a
single-child launch cannot be named). `toolDescriptionMode: compact` remains
tabled pending a re-measure of the orchestrator prompt.

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
`workspace` (worker/workspace), `twin` (worker/vault). `twin` ships
`enable = false` (perField supplies the mkDefault, so a consumer flips it with
a plain `my.pi.agents.twin.enable = true`). Per-agent memory is wired as
`my.pi.agents.<n>.memory = { scope, path }`, rendered to the `memory:`
frontmatter (first 200 lines of MEMORY.md injected; write-less agents get a
read-only block).

**6 — `pi-herdr-fanout`** (bespoke, ~150 lines over the herdr CLI): budding off N
independent *head* sessions in their own panes from one query ("run reviews on
all open PRs assigned to me"). `pi-subagents`' `project.open` is one-pane-per-cwd
and cannot inspect or steer subagents inside a peer session, so it is close but
not sufficient. Lowest priority — no third-party package does peer-session
fan-out properly.

**7 — re-measure.** Not the always-on payload (§1) — measure **cost per
completed task** and orchestrator context growth per task.

### Open questions for the user

Resolved since this was written: the always-open default in owned repos (§3),
the additive corporate `jira` bundle (verified via a simulated corporate
flake), and narrowing this repo's `AGENTS.md` for children (not needed yet —
`toolDescriptionMode` and context narrowing stay tabled until the orchestrator
prompt is measured again).
