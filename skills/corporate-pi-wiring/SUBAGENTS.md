# Corporate subagent wiring

Companion to `SKILL.md`. Read that first — it covers adding the private flake
as an input, `extraSpecialArgs`, and the modules list. This file covers only
the **subagent system**: model tiers, capability bundles, and agents.

Everything here is verifiable. Claims carry `file:line`; instructions carry a
command. Do not trust a statement in this document over what the repository
actually says — if they disagree, the repository is right and this file has
drifted.

---

## 0. Mental model

```text
agent  =  tier          ×  bundles                 ×  role
          (model +         (skills + extensions +     (prompt + posture +
           thinking)        tools + MCP + policy)      permissions + budget)
```

Three Nix options, all declared in `modules/options.nix`:

| Option | What it is |
|---|---|
| `my.pi.modelTiers` | Named model/thinking bands. Agents pick a whole price/capability band, never a raw model. |
| `my.pi.capabilityBundles` | Reusable units declaring skills, extensions, tools, MCP selections **and the policy prose that goes with them**, together — so "tool allowlisted but its provider not loaded" cannot be expressed. |
| `my.pi.agents` | tier × bundles + a role prompt. Rendered to `~/.pi/agent/agents/<name>.md`. |

Base values live in `modules/home/pi/agents.nix`. The renderer is
`modules/home/pi/_agents.nix`.

Two more options you may want, declared in the same place and defaulted in
`modules/home/pi/policies.nix`:

| Option | Behaviour on collision |
|---|---|
| `my.pi.agentInvariants` | Terse lines injected into **every** agent. Add keys freely. |
| `my.pi.globalAgentPolicies` | Named sections of `~/.pi/agent/AGENTS.md` (orchestrator). Keys sort alphabetically — use numeric prefixes. Strings merge additively; use `lib.mkForce` to replace a base section. |

### What ships in the base flake

Tiers: `orchestrator`, `executive`, `worker`, `simple`, `vision`.

Bundles: `code`, `lens`, `nix`, `web`, `vault`, `workspace`, `media`, `vcs`.

Agents (verify with the command in §6):

| agent | tier | bundles |
|---|---|---|
| `oracle` | orchestrator | — |
| `executor` | executive | code, lens |
| `reviewer` | executive | code, lens |
| `investigator` | worker | code, lens |
| `researcher` | worker | web |
| `nix-scout` | worker | nix |
| `workspace` | worker | workspace |
| `twin` | worker | vault |
| `media` | vision | media |
| `scout` | simple | code |

`twin` ships with `enable = false` (it needs an Obsidian vault). Enable it
with `my.pi.agents.twin.enable = true;`.

---

## 1. Where you may define these options — read this before writing any Nix

**Never define `my.*` inside `flake.modules.homeManager.pi`** (that is
`modules/home/pi/default.nix`).

The standalone `packages.pi` build (`modules/flake/wrapped-packages.nix:22`)
evaluates that one aspect **in isolation**, without
`flake.modules.generic.my-options`. A `my.*` *definition* there fails with

```text
error: The option `my' does not exist
```

and — this is the trap — it breaks `nix flake check` while
`nix build .#homeConfigurations.<name>.activationPackage` stays **green**,
because the full home assembly does include `my-options`. This shipped broken
once in the base repo for exactly this reason. See repo `AGENTS.md` pitfall #6.

Rules:

- *Reads* guarded with `or` are safe anywhere: `config.my.copilot.enable or false`.
- *Definitions* go in their own aspect. The base flake uses
  `modules/home/pi/agents.nix` and `modules/home/pi/policies.nix`.
- **Always run `nix flake check`, not just `nix build`.**

So: put your corporate subagent config in a **separate aspect file**, e.g.
`modules/home/pi-agents.nix`:

```nix
# Dendritic aspect: corporate subagent roster (home-manager class).
{...}: {
  flake.modules.homeManager.pi-agents-corp = {lib, ...}: {
    # my.pi.* definitions go here.
  };
}
```

---

## 2. Wire the copilot models into the tiers

### 2a. Find out what your provider actually offers

Do **not** copy model ids from any document, including this one. Enumerate
them:

```bash
pi --list-models github-copilot
```

Output columns are `provider · model · context · max-out · thinking · images`.
Two of those columns decide tier assignment:

- **`thinking`** — a tier with a non-null `thinking` needs a model where this
  is `yes`. `orchestrator`, `executive` and `worker` all set one.
- **`images`** — the `vision` tier requires `yes` here, or the `media` agent
  cannot do its job.

### 2b. Repoint the tiers

The `orchestrator` tier is special: it also sets the **interactive session's**
`defaultModel` / `defaultProvider` / `defaultThinkingLevel`
(`modules/home/pi/default.nix`). You always drop into an orchestrator and
delegate from there, so the model you type at and the tier that routes
delegation are one knob. Repoint that tier and both move.

**Do not set `defaultProvider` / `defaultModel` / `defaultThinkingLevel` in
`settings`.** They would win on priority and silently decouple the session
from the tier, reintroducing the two-sources-of-truth bug this design removes.

```nix
my.pi.modelTiers = {
  orchestrator = {
    model = "<from --list-models>";
    provider = "github-copilot";
    thinking = "high";
  };
  executive = { model = "<…>"; provider = "github-copilot"; thinking = "high"; };
  worker    = { model = "<…>"; provider = "github-copilot"; thinking = "medium"; };
  simple    = { model = "<…>"; provider = "github-copilot"; thinking = "low"; };
  vision    = { model = "<…>"; provider = "github-copilot"; thinking = null; };
};
```

No `lib.mkForce`. Plain definitions win, because base defaults are applied
per field (§3).

Smaller edits work too:

```nix
# just move one tier
my.pi.modelTiers.worker = { model = "…"; provider = "github-copilot"; };

# just change one field, inheriting model and provider from the base
my.pi.modelTiers.worker.thinking = "high";

# add a tier the base flake never declared
my.pi.modelTiers.corp-cheap = { model = "…"; provider = "github-copilot"; thinking = "low"; };
```

---

## 3. Merge semantics — the one thing that will surprise you

Base defaults are applied **per field** (`perField` in
`modules/home/pi/agents.nix`). This is deliberate and load-bearing:

| You write | Result |
|---|---|
| a whole tier/bundle/agent | replaces that key; **siblings survive** |
| one field of one key | overrides that field; other fields inherited |
| a brand-new key | added; base keys survive |
| a **list** field (`skills`, `extensions`, `tools`, `bundles`) | **replaces the list.** Restate the full list to extend. |

List-replaces-rather-than-appends is intentional — corporate must be able to
*drop* base skills (the vault skills, for instance, have no corporate
equivalent), which additive merging cannot express.

> **Historical note, in case you are reading an older checkout.** These
> defaults used to be a single `lib.mkDefault` around the whole attrset. Under
> that scheme, defining one key discarded **every** sibling. For tiers and
> bundles it failed loudly (`unknown tier`); for `my.pi.agents` it was
> **silent** — your new agent would be the only one emitted, and the generated
> roster table in `AGENTS.md` would shrink to match, so nothing looked wrong.
> If adding one agent makes the others vanish, you are on a pre-fix checkout.

---

## 4. Add an agent

```nix
my.pi.agents.jira-scout = {
  description = "Corporate ticket recon";   # required, one line
  tier = "worker";                          # must exist in my.pi.modelTiers
  bundles = ["jira"];                       # must exist in my.pi.capabilityBundles
  tools = ["read" "grep" "find" "ls"];      # see the warning below
  toolBudget = {hard = 40;};                # READ-ONLY agents only
  timeoutMs = 3600000;                      # >= PI_INTERCOM_ASK_TIMEOUT_MS so a
                                            #   blocked ask is not cut short
  toolTimeoutMs = 600000;                   # optional per-tool cap (hung bash)
  memory = {scope = "user"; path = "...";};  # optional persistent memory
  prompt = ''
    You are a ticket scout. Answer with file/ticket citations and stop.
  '';
};
```

A bad `tier` or `bundles` entry is a **hard error** from
`modules/home/pi/_agents.nix:65-66` (`unknown tier` / `unknown bundle`). That
is the intended fast failure — prefer it to a silently degraded agent.

### `tools` is a strict allowlist, and it is easy to get wrong

- Omitting `tools` (`null`) means **inherit ambient tools**. That is *not*
  read-only.
- A list is a strict allowlist over built-in **and extension** tools. If you
  want `symbol_search`, name it — and the extension providing it must also be
  in some bundle's `extensions`. Allowlisting a tool whose provider is not
  loaded **fails the child launch**.
- Bundle `tools` are unioned into the agent's list, so a bundle can add the
  tool its own skills need. That is why the `nix` bundle carries `bash`.

### Writers need an explicit permission block

Children inherit a global `write = "deny"` / `edit = "deny"`
(`subagentConfig.permissions.rules` in `modules/home/pi/default.nix`). A
default-deny floor means a new agent is read-only until someone opts out —
the right direction to fail. Writers opt out:

```nix
permission = { edit = "allow"; write = "allow"; };
```

Verify what actually rendered:

```bash
grep -A2 '^permission:' ~/.pi/agent/agents/*.md
```

**`bash` is never gated** — pi-subagents passes it through, and the permission
rules do not cover it. The only way to deny a shell is to leave `bash` out of
`tools`.

### `toolBudget` vs `timeoutMs` vs `toolTimeoutMs`

- `toolBudget.hard` → **read-only agents only.** After the cap, blocking tools
  include `read`/`grep`, so a mutation-capable agent can be stranded with a
  half-applied edit.
- Writers → bound with `timeoutMs` instead.
- `timeoutMs` is the **whole-run wall-clock kill**, and it also caps how long a
  child can wait on a `contact_supervisor` ask: the effective wait is
  `min(ask timeout, timeoutMs)`. Keep it >= `PI_INTERCOM_ASK_TIMEOUT_MS`
  (1 hour in the base flake) for any agent that may block on a decision.
- `toolTimeoutMs` → a hard per-tool deadline, distinct from `timeoutMs`, so one
  hung tool (a `bash` call waiting on input) is cut short without shrinking the
  run window. `contact_supervisor` is exempt from this, not from `timeoutMs`.
- `memory` → opt-in persistent memory: `{scope = "project"|"user"; path = "...";}`
  renders the `memory:` frontmatter; the first 200 lines of MEMORY.md are
  injected each run. The twin agent is the intended first user (still disabled).

---

## 5. Add a capability bundle

Declare it corporate-side only; the base flake stays site-agnostic.

```nix
my.pi.capabilityBundles.jira = {
  skills = ["jira-workflows"];          # logical keys — see below
  extensions = ["npm:pi-mcp-adapter"];  # note the npm: prefix
  tools = ["bash"];                     # unioned into consuming agents
  mcpTools = ["jira"];                  # rendered as mcp:-prefixed tools
  policy = ''
    ## Why you have `bash`
    …scope it explicitly. A bundle owns its own prerequisites.
  '';
};
```

Any agent referencing this bundle must also be declared corporate-side, since
an unknown bundle key throws.

**Two rules that cause launch failures:**

1. **`extensions` entries need the `npm:` prefix.** Bare names are passed to
   `pi --extension` and resolved as *filesystem paths*; the child dies with
   `Extension path does not exist`. Pin versions with `npm:<pkg>@<version>`.
2. **`skills` are logical keys, not store basenames.** `_agents.nix`
   materialises a `linkFarm` at `~/.pi/agent/subagent-skills` and emits
   `skillPath: ../subagent-skills`. Only skills declared in
   `programs.pi-coding-agent.skills` are in that tree —
   **package-provided** skills (worktrunk, `pi-lens-*`, parse-document, …) are
   discovered from their `package.json` and are *not*. Do not list those here.

---

## 6. Pitfalls inherited from the base setup

- **Never put MCP on a fan-out agent.** MCP servers spawn **per child** via
  `npx`. Direct MCP tools also need `pi-mcp-adapter` loaded *and* explicit
  `mcp:` entries — a global `directTools = true` is not sufficient. The
  adapter caches metadata at startup, so **restart pi after adding a server**.
- **Set the fan-out retry bound.** Wide fan-out contends on a single
  `status.json`; the default retry ladder parks the thread synchronously for
  ~7.9s and presents as a hung process at 0% CPU. The base flake sets
  `home.sessionVariables.PI_SUBAGENT_FS_RETRY_MAX_TOTAL_MS = "1000"`. It is a
  login-shell variable — a fresh login is needed the first time.
- **Nix ignores untracked files.** `git add -NA` before building, or your new
  aspect silently does not exist (repo `AGENTS.md` pitfall #1).
- **Child output is a draft.** Verify any load-bearing claim from a subagent
  with one deterministic command. Require `file:line` citations in briefs so
  verification is a single `grep`.
- **Escalation is advisory.** `contact_supervisor` works end to end, but a
  child that judges your stop condition unwarranted will answer anyway. Never
  rely on a child choosing to ask.
- **A blocked ask expires.** The ask timeout is `PI_INTERCOM_ASK_TIMEOUT_MS`
  (1 hour in the base flake), and on expiry the child is released to continue —
  so an agentInvariants line tells it to stop and report "no decision" rather
  than guess. The effective wait is `min(ask timeout, agent timeoutMs)`.

---

## 7. Verification

```bash
git add -NA                     # pitfall #1
nix flake check                 # NOT just nix build — see §1
nix build .#homeConfigurations.<name>.activationPackage --out-link /tmp/hm

# Every agent rendered, and nothing vanished:
ls /tmp/hm/home-files/.pi/agent/agents/

# Tiers resolved as intended:
for f in /tmp/hm/home-files/.pi/agent/agents/*.md; do
  printf '%-16s ' "$(basename "$f" .md)"
  awk '/^---$/{n++;next} n==1 && /^(model|thinking):/{printf "%s ", $2}' "$f"; echo
done

# Session default followed the orchestrator tier:
node -e 'const s=require("/tmp/hm/home-files/.pi/agent/settings.json");
  console.log(s.defaultProvider, s.defaultModel, s.defaultThinkingLevel)'
```

The count check is the important one. If adding an agent reduced the total,
re-read §3.
