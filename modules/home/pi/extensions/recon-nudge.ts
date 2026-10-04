/**
 * Orchestrator-surface gate.
 *
 * >>> NEVER restrict the orchestrator's tools with `--tools`, `--exclude-tools`,
 * >>> or `exposure: "hidden"` for anything this gate must be able to re-grant.
 * >>> `pi.setActiveTools()` silently drops `hidden` tools and unknown names, so
 * >>> a tool restricted that way can NEVER be restored by the `/recon-gate off`
 * >>> escape hatch — the hatch would "succeed" while silently failing to
 * >>> re-activate it. This gate is a *session-scoped active-set pin + tool_call
 * >>> block*, not a config restriction; keep it that way.
 *
 * WHAT THIS GATE DOES
 * -------------------
 * The interactive orchestrator (ctx.mode === "tui") runs against a minimal,
 * session-pinned set of declared tools. Everything else it might reach for —
 * MCP tools, codemode, tool_search, the pi-lens/docparser surface — is either
 * not declared to the model at all, or hard-blocked at the `tool_call` hook
 * when it tries. Investigation therefore routes through subagents, whose own
 * sessions are not gated (children report ctx.mode === "print").
 *
 *   1. MINIMAL TOOL SET — `before_agent_start` pins the declared surface to
 *      MINIMAL_TOOLS (filtered to what is actually registered) via a
 *      compare-and-write so `pi.setActiveTools()` is only called when the set
 *      actually differs. setActiveTools rebuilds the system prompt, so an
 *      unconditional per-turn call would cause a per-turn cache miss.
 *      `subagents_enable` is in the set because pi-subagents' own
 *      before_agent_start re-adds it every turn when absent — that would
 *      otherwise be a per-turn cache miss.
 *
 *   2. READ BUDGET — `read` is the one recon-shaped tool that stays declared.
 *      It is budgeted by turn: NUDGE_THRESHOLD soft-warns, GATE_THRESHOLD
 *      hard-blocks further reads until the orchestrator delegates.
 *
 *   3. HARD-BLOCK — `codemode`, `tool_search`, `list_mcp_resources`, and any
 *      `mcp__*` tool are refused at the `tool_call` hook regardless of the read
 *      budget. codemode (exposure "model-only") reaches every registered tool
 *      from a script and bypasses the active set; tool_search / MCP
 *      resource+direct tools are the deferred-MCP discovery path that the
 *      built-in MCP extension re-activates.
 *
 *   4. ESCAPE HATCH — `/recon-gate off` (or `/recon-gate-disable`) grants the
 *      full registered surface for the session: it captures the pre-hatch
 *      active set, activates every registered tool, disables nudge+block, and
 *      reports exactly which tools were newly granted.
 *
 * SCOPE
 * -----
 * Gated to ctx.mode === "tui" so it only fires for the interactive
 * orchestrator. Subagent children are in-process AgentSessions created by
 * pi-subagents and bound with `session.bindExtensions({ mode: "print" })`
 * (pi-subagents src/runs/shared/child-session.ts), so they report
 * ctx.mode === "print" and never cross the gate.
 *
 * COMMAND
 * -------
 * `/recon-gate` mutates a module-scoped, per-session gate mode:
 *
 *   - `/recon-gate 0`         → block-all: `read` is refused immediately, no
 *                               budget.
 *   - `/recon-gate off`       → ESCAPE HATCH: activate the full registered
 *     `/recon-gate-disable`      surface, disable nudge+block, report the grant.
 *   - `/recon-gate on` / bare → default: minimal set + read budget.
 *
 * The mode resets to "on" on session_start.
 */

import type {
  ExtensionAPI,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

/**
 * The minimal declared tool surface for the interactive orchestrator, frozen
 * per session. `worktrunk` is ALWAYS-ON: an always-on tool keeps a
 * byte-identical prompt prefix (cache-stable), whereas on-demand activation
 * goes through `pi.setActiveTools()` → the system prompt is rebuilt → cache
 * miss. So it belongs in the active set from turn one and must never move.
 * The gate tolerates unregistered names because `pi.setActiveTools()` silently
 * drops unknown names, so a name that is not registered yet is filtered out
 * harmlessly.
 *
 * `subagents_enable` MUST stay: pi-subagents' own before_agent_start re-adds it
 * every turn when it is absent from the active set, which would otherwise be a
 * per-turn system-prompt rebuild.
 */
const MINIMAL_TOOLS: readonly string[] = [
  "read",
  "subagent",
  "subagent_supervisor",
  "subagents_enable",
  "todo",
  "bg_wait",
  "recall",
  "rename_herdr_context",
  "relocate_herdr_tab",
  "worktrunk",
];

/**
 * The recon-shaped tools whose execution counts toward the delegation budget.
 * Only `read` remains in the minimal set; everything else investigation-shaped
 * is undeclared or hard-blocked, so it cannot accumulate budget.
 */
const RECON_TOOLS: readonly string[] = ["read"];

/**
 * Active-set bypass + MCP auto-activation surface, hard-blocked at the
 * `tool_call` hook regardless of the read budget:
 *   - `codemode` (exposure "model-only") reaches every registered tool from a
 *     script and does not respect the active set.
 *   - `tool_search` is auto-activated by the built-in MCP extension for
 *     `deferred`-exposure servers.
 *   - `list_mcp_resources` and `mcp__*` are the MCP resource + direct-tool
 *     surface the orchestrator should route to a subagent.
 */
const BYPASS_TOOLS: readonly string[] = [
  "codemode",
  "tool_search",
  "list_mcp_resources",
];

// Thresholds are in READ TURNS, not tool calls. A "turn" is one model-request
// iteration — the batch of tool calls the model issued together, before it
// could see any of their results or any warning about them. The counter only
// advances at a turn boundary (the `context` hook), so the hard gate can never
// trip mid-batch on calls the model issued before it could have seen a warning.
const NUDGE_THRESHOLD = 2; // warn once this many read turns deep
const GATE_THRESHOLD = 3; // hard-block read at this many

type GateMode = "on" | "block-all" | "off";

export default function (pi: ExtensionAPI) {
  // Per-session state. `/reload`, `/new` and session switches re-run
  // session_start, which resets the counter and gate mode.
  let reconTurns = 0; // model-request iterations this user-turn that performed a read
  let turnHadRecon = false; // whether the iteration in progress performed a read

  let gateMode: GateMode = "on";

  const reset = () => {
    reconTurns = 0;
    turnHadRecon = false;
  };

  // Compare-and-write: set the active surface to the minimal set only when it
  // actually differs (any missing name OR any extra name). setActiveTools
  // rebuilds the system prompt, so an unconditional per-turn call would cause
  // a per-turn cache miss.
  const pinMinimalSet = () => {
    const registered = new Set(pi.getAllTools().map((t) => t.name));
    const target = MINIMAL_TOOLS.filter((name) => registered.has(name));
    const active = pi.getActiveTools();
    const activeSet = new Set(active);
    const differs =
      target.some((name) => !activeSet.has(name)) ||
      active.some((name) => !target.includes(name));
    if (differs) pi.setActiveTools(target);
  };

  pi.on("session_start", () => {
    reset();
    gateMode = "on";
  });

  // A new user message starts a new turn, so the per-turn counter resets.
  // Extension-generated messages (source "extension", e.g. queued follow-ups)
  // are continuations of the current turn and must NOT reset the counter.
  pi.on("input", (event) => {
    if (event.source !== "extension") reset();
  });

  // Pin the minimal declared surface each new turn. When the escape hatch is
  // open (gateMode "off"), leave the granted full surface alone.
  pi.on("before_agent_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (gateMode === "off") return;
    pinMinimalSet();
  });

  // Hard gate. Fires before the tool executes; returning { block: true, reason }
  // feeds the reason back to the model as an error. `subagent` is never in
  // RECON_TOOLS, so delegation always goes through.
  pi.on("tool_call", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (gateMode === "off") return;

    // Active-set bypass + MCP auto-activation race: refuse regardless of the
    // read budget. Delegation is the only path through these.
    if (
      BYPASS_TOOLS.includes(event.toolName) ||
      event.toolName.startsWith("mcp__")
    ) {
      return {
        block: true,
        reason:
          `${event.toolName} is blocked by the orchestrator-surface gate. ` +
          "Hand the underlying work to a subagent (scout/researcher/investigator) " +
          "with a clear brief instead of reaching these tools directly; the " +
          "child's session is not gated. (Run /recon-gate off to grant the full " +
          "surface for this session.)",
      };
    }

    if (!RECON_TOOLS.includes(event.toolName)) return;
    if (gateMode === "block-all" || reconTurns >= GATE_THRESHOLD) {
      return {
        block: true,
        reason:
          gateMode === "block-all"
            ? "read is fully gated this session (/recon-gate 0): hand all " +
              "investigation to a subagent (scout/researcher/investigator) or " +
              "finalize. Run /recon-gate off to disable the gate, /recon-gate " +
              "on to restore the default minimal set + read budget."
            : `read budget exhausted: ${reconTurns} read ` +
              `${reconTurns === 1 ? "turn" : "turns"} this request with no ` +
              "delegation. Hand the remaining investigation to a subagent " +
              "(scout/researcher/investigator) with a clear brief, or finalize " +
              "now. A successful delegation resets this budget. (User command: " +
              "/recon-gate off disables this gate for the session, /recon-gate " +
              "on restores it.)",
      };
    }
  });

  pi.on("tool_execution_end", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (gateMode === "off") return;
    if (event.toolName === "subagent" && !event.isError) {
      // A successful delegation clears the deadline — the orchestrator did
      // the right thing.
      reset();
      return;
    }
    // Errored (including gate-blocked) reads did not gather anything; do not
    // let them taint the turn toward the gate.
    if (event.isError) return;
    if (RECON_TOOLS.includes(event.toolName)) {
      turnHadRecon = true;
    }
  });

  // Append the nudge to the tail of the outgoing request. Returning a new
  // `messages` array from the context hook only changes THIS provider call;
  // pi never persists it back into the session.
  pi.on("context", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (gateMode !== "on") return;

    // Close out the iteration that just finished: if it performed a read,
    // consume one unit of budget. This runs once per model request, so the
    // counter stays constant for the whole of the NEXT iteration — the hard
    // gate can therefore never trip mid-batch.
    if (turnHadRecon) {
      reconTurns += 1;
      turnHadRecon = false;
    }

    if (reconTurns < NUDGE_THRESHOLD) return;

    const remaining = GATE_THRESHOLD - reconTurns;
    const text =
      remaining > 0
        ? `${reconTurns} read ${reconTurns === 1 ? "turn" : "turns"} this ` +
          "request with no delegation " +
          `(${remaining} remaining before read is blocked). Stop and hand ` +
          "the remaining investigation to a subagent " +
          "(scout/researcher/investigator) with a clear problem statement, " +
          "or finalize within that budget."
        : `${reconTurns} read ${reconTurns === 1 ? "turn" : "turns"} this ` +
          "request with no delegation — read budget exhausted. Hand the " +
          "remaining investigation to a subagent (scout/researcher/investigator), " +
          "or finalize now; further reads will be blocked.";

    const nudge = {
      role: "user" as const,
      content: [{ type: "text" as const, text }],
      timestamp: Date.now(),
    };

    return { messages: [...event.messages, nudge] };
  });

  const setGateMode = (mode: GateMode, ctx: ExtensionCommandContext) => {
    if (mode === "off") {
      // ESCAPE HATCH: capture the pre-hatch surface, grant the full registered
      // surface, and report exactly what was newly activated.
      const before = new Set(pi.getActiveTools());
      const all = pi.getAllTools().map((t) => t.name);
      pi.setActiveTools(all);
      gateMode = "off";
      const delta = all.filter((name) => !before.has(name));
      const deltaText =
        delta.length === 0
          ? "no tools were newly activated (the full surface was already active)"
          : `granted ${delta.length} tool${delta.length === 1 ? "" : "s"}: ` +
            `${delta.join(", ")}`;
      ctx.ui.notify(
        "Orchestrator-surface gate disabled for this session — full autonomy " +
          `granted (all ${all.length} registered tools). ${deltaText}. Run ` +
          "/recon-gate on to restore the minimal set + read budget.",
        "info",
      );
      return;
    }

    gateMode = mode;
    // Restoring on/block-all re-pins the minimal declared surface now (not on
    // the next turn), so a grant from a prior /recon-gate off is revoked.
    pinMinimalSet();
    const msg =
      mode === "block-all"
        ? "Orchestrator-surface gate set to block-all — every read is now " +
          "refused. Run /recon-gate off to disable, /recon-gate on to restore."
        : "Orchestrator-surface gate restored to default (minimal tool set + " +
          "read budget: nudge then hard block).";
    ctx.ui.notify(msg, "info");
  };

  pi.registerCommand("recon-gate", {
    description:
      "Control the orchestrator-surface gate: /recon-gate 0 blocks all reads, " +
      "/recon-gate off grants the full surface (escape hatch), /recon-gate on " +
      "restores the minimal set + read budget.",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") return;
      const arg = args.trim().toLowerCase();
      if (arg === "0") setGateMode("block-all", ctx);
      else if (arg === "off" || arg === "disable") setGateMode("off", ctx);
      else if (arg === "on" || arg === "") setGateMode("on", ctx);
      else
        ctx.ui.notify(
          `Unknown recon-gate mode "${args.trim()}". Use 0 (block all), ` +
            "off (full surface), or on (minimal set + read budget).",
          "error",
        );
    },
  });

  pi.registerCommand("recon-gate-disable", {
    description:
      "Disable the orchestrator-surface gate for this session (same as /recon-gate off).",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") return;
      setGateMode("off", ctx);
    },
  });
}
