/**
 * Nudge, then gate, the interactive orchestrator into delegating investigation
 * instead of doing recon itself.
 *
 * WHY
 * ---
 * The orchestrator's main cost lever is its own context size, and every
 * read/bash/web-fetch it performs in-turn adds a round-trip that a cheap
 * read-only scout could absorb instead. The orchestrator's built-in surface
 * is already just `read` + `bash` (defaultTools), so this gate is the
 * backstop that keeps even those verification calls bounded: it counts recon
 * turns (model-request iterations that performed at least one recon call)
 * and escalates mechanically in two stages:
 *
 *   1. NUDGE (soft): once reconTurns crosses NUDGE_THRESHOLD, append a
 *      directive to the tail of the outgoing request telling the model to
 *      stop and delegate.
 *   2. GATE (hard): once reconTurns reaches GATE_THRESHOLD, block further
 *      recon-shaped tool calls at the `tool_call` hook (returning
 *      { block: true, reason }); the reason becomes an error the model sees,
 *      so the only way forward is to delegate or finalize.
 *
 * Counting TURNS instead of individual tool calls makes the gate graceful by
 * construction. A "turn" is one model-request iteration — the batch of tool
 * calls the model issued together, before it could see any of their results
 * or any warning about them. The counter is advanced only in the `context`
 * hook, i.e. at the boundary between iterations, never during a turn. The
 * gate therefore decides once per turn and stays constant for the whole
 * batch: a batch issued before any warning always runs to completion, and
 * the warning is always injected at a boundary before the gate can block the
 * next batch.
 *
 * The `subagent` tool is NOT recon-shaped, so the forced delegation always
 * goes through. A successful `subagent` call resets the budget, which is what
 * preserves the orchestrator's verification surface: after delegating, the
 * orchestrator can `read` the child's report or run one `bash` command to
 * check a claim before the counter climbs back to the gate again.
 *
 * The nudge is EPHEMERAL. It is appended on the `context` hook, which pi feeds
 * a structuredClone of the outgoing messages and whose return value is used
 * only for that one provider request. It is never written back to
 * ctx.sessionManager / the session transcript, so it does not pollute history
 * or context (verified against pi's ExtensionRunner.emitContext, which
 * structuredClone()s before dispatch and only consumes the returned array).
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
 *   - `/recon-gate 0`         → block-all: every recon-type tool call is
 *                               refused, regardless of the counter.
 *   - `/recon-gate off`       → disable the gate entirely (nudge and hard
 *     `/recon-gate-disable`      block both off).
 *   - `/recon-gate on` / bare → default: nudge, then hard block.
 *
 * The mode is module-scoped per session, resets to "on" on session_start,
 * and persists across turns and across successful delegations.
 */

import type {
  ExtensionAPI,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

/**
 * DRIFT RISK — keep this list in sync by hand.
 *
 * This is the set of "recon-type" (read-only / gathering) tools whose
 * execution counts toward the delegation deadline. There is NO automated
 * check that this list matches the orchestrator's actual tool surface: every
 * time a new read-only/gathering tool is added to the orchestrator — a
 * built-in, a pi-lens or pi-docparser tool, an MCP tool, or anything another
 * extension registers — this list must be revisited and the tool added here if
 * it is recon-shaped. Missing entries silently undercount; this is a known
 * drift risk.
 */
const RECON_TOOLS: readonly string[] = [
  "bash",
  "read",
  // mcp: direct calls to an MCP server the orchestrator could instead route
  // to a dedicated agent whose bundle wires that same server (e.g. `workspace`
  // for google-workspace) — treated as recon-shaped for the same reason
  // bash/read are.
  "mcp",
  "web_search",
  "web_fetch",
  "document_parse",
  "document_search",
  "document_screenshot",
  "symbol_search",
  "module_report",
  "read_symbol",
  "read_enclosing",
  "project_report",
  "effective_config",
  "lens_diagnostics",
  "lsp_navigation",
  "ast_grep_search",
  "ast_grep_outline",
];

// Thresholds are in RECON TURNS, not tool calls. A "turn" is one model-request
// iteration — the batch of tool calls the model issued together — which is the
// natural unit of "the orchestrator decided not to delegate." Counting turns
// means the counter only advances at a turn boundary (the `context` hook), so
// the hard gate can never trip mid-batch on calls the model issued before it
// could have seen a warning.
//
// Soften here (raise GATE_THRESHOLD, or delete the `tool_call` handler to drop
// the gate) if this proves too aggressive in practice.
const NUDGE_THRESHOLD = 2; // warn once this many recon turns deep
const GATE_THRESHOLD = 3; // hard-block recon tools at this many

type GateMode = "on" | "block-all" | "off";

export default function (pi: ExtensionAPI) {
  // Per-session state. `/reload`, `/new` and session switches re-run
  // session_start, which resets the counter (same pattern as
  // worktrunk-deferred.ts).
  let reconTurns = 0; // model-request iterations this user-turn that performed recon
  let turnHadRecon = false; // whether the iteration in progress performed recon

  // Per-session gate mode, mutated by the /recon-gate and /recon-gate-disable
  // commands. Resets to "on" on session_start (a new session starts with the
  // default gate); persists across turns and across successful delegations.
  let gateMode: GateMode = "on";

  const reset = () => {
    reconTurns = 0;
    turnHadRecon = false;
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

  // Hard gate: refuse recon-shaped tool calls once the budget is spent.
  // Fires after tool_execution_start, before the tool executes; returning
  // { block: true, reason } feeds the reason back to the model as an error.
  // `subagent` is never in RECON_TOOLS, so delegation always goes through.
  pi.on("tool_call", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (gateMode === "off") return;
    if (!RECON_TOOLS.includes(event.toolName)) return;
    if (gateMode === "block-all" || reconTurns >= GATE_THRESHOLD) {
      return {
        block: true,
        reason:
          gateMode === "block-all"
            ? "recon is fully gated this session (/recon-gate 0): hand all " +
              "investigation to a subagent (scout/researcher/investigator) or " +
              "finalize. Run /recon-gate off to disable the gate, /recon-gate " +
              "on to restore the default nudge+gate."
            : `recon budget exhausted: ${reconTurns} recon ` +
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
    // Errored (including gate-blocked) recon calls did not gather anything;
    // do not let them taint the turn toward the gate.
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

    // Close out the iteration that just finished: if it performed recon,
    // consume one unit of budget. This runs once per model request, so the
    // counter stays constant for the whole of the NEXT iteration — the hard
    // gate can therefore never trip mid-batch on calls the model issued
    // before it could have seen a warning.
    if (turnHadRecon) {
      reconTurns += 1;
      turnHadRecon = false;
    }

    if (reconTurns < NUDGE_THRESHOLD) return;

    const remaining = GATE_THRESHOLD - reconTurns;
    const text =
      remaining > 0
        ? `${reconTurns} recon ${reconTurns === 1 ? "turn" : "turns"} this ` +
          "request with no delegation " +
          `(${remaining} remaining before recon is blocked). Stop and hand ` +
          "the remaining investigation to a subagent " +
          "(scout/researcher/investigator) with a clear problem statement, " +
          "or finalize within that budget."
        : `${reconTurns} recon ${reconTurns === 1 ? "turn" : "turns"} this ` +
          "request with no delegation — recon budget exhausted. Hand the " +
          "remaining investigation to a subagent (scout/researcher/investigator), " +
          "or finalize now; further recon calls will be blocked.";

    const nudge = {
      role: "user" as const,
      content: [{ type: "text" as const, text }],
      timestamp: Date.now(),
    };

    return { messages: [...event.messages, nudge] };
  });

  const setGateMode = (mode: GateMode, ctx: ExtensionCommandContext) => {
    gateMode = mode;
    const msg =
      mode === "off"
        ? "Recon-gate disabled for this session — nudge and hard block are both " +
          "off. Run /recon-gate on to restore the default."
        : mode === "block-all"
          ? "Recon-gate set to block-all — every recon-type tool call is now " +
            "refused. Run /recon-gate off to disable, /recon-gate on to restore."
          : "Recon-gate restored to default (nudge then hard block).";
    ctx.ui.notify(msg, "info");
  };

  pi.registerCommand("recon-gate", {
    description:
      "Control the recon-gate for this session: /recon-gate 0 blocks all recon, " +
      "/recon-gate off disables the gate, /recon-gate on restores the default.",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") return;
      const arg = args.trim().toLowerCase();
      if (arg === "0") setGateMode("block-all", ctx);
      else if (arg === "off" || arg === "disable") setGateMode("off", ctx);
      else if (arg === "on" || arg === "") setGateMode("on", ctx);
      else
        ctx.ui.notify(
          `Unknown recon-gate mode "${args.trim()}". Use 0 (block all), ` +
            "off (disable), or on (default).",
          "error",
        );
    },
  });

  pi.registerCommand("recon-gate-disable", {
    description:
      "Disable the recon-gate for this session (same as /recon-gate off).",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") return;
      setGateMode("off", ctx);
    },
  });
}
