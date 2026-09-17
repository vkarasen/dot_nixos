/**
 * Nudge, then gate, the interactive orchestrator into delegating investigation
 * instead of doing recon itself.
 *
 * WHY
 * ---
 * The orchestrator's main cost lever is its own context size, and every
 * read/grep/find/web-fetch it performs in-turn adds a round-trip that a cheap
 * read-only scout could absorb instead. The delegation policy
 * (05-delegation) says "delegate after ~3 tool round-trips", but a long turn
 * can drift past that silently. This extension enforces the deadline
 * mechanically in two escalating stages:
 *
 *   1. NUDGE (soft): once reconCount crosses NUDGE_THRESHOLD, append a
 *      directive to the tail of the outgoing request telling the model to
 *      stop and delegate. Repeated every NUDGE_INTERVAL calls.
 *   2. GATE (hard): once reconCount reaches GATE_THRESHOLD, block further
 *      recon-shaped tool calls at the `tool_call` hook (returning
 *      { block: true, reason }); the reason becomes an error the model sees,
 *      so the only way forward is to delegate or finalize.
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
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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
  "grep",
  "find",
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
  "lsp_diagnostics",
  "lens_diagnostics",
];

// Hardcoded thresholds for the strict experiment. Soften here (raise
// GATE_THRESHOLD, or delete the `tool_call` handler to drop the gate) if this
// proves too aggressive in practice.
const NUDGE_THRESHOLD = 3; // soft warning once this many recon calls deep
const NUDGE_INTERVAL = 3; // re-warn every N more recon calls
const GATE_THRESHOLD = 6; // hard-block recon tools at this many

export default function (pi: ExtensionAPI) {
  // Per-session state. `/reload`, `/new` and session switches re-run
  // session_start, which resets the counter (same pattern as
  // worktrunk-deferred.ts).
  let reconCount = 0;
  let nextNudgeAt = NUDGE_THRESHOLD;

  const reset = () => {
    reconCount = 0;
    nextNudgeAt = NUDGE_THRESHOLD;
  };

  pi.on("session_start", () => {
    reset();
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
    if (RECON_TOOLS.includes(event.toolName) && reconCount >= GATE_THRESHOLD) {
      return {
        block: true,
        reason:
          `recon budget exhausted: ${reconCount} recon-type tool calls this turn ` +
          "with no delegation. Hand the remaining investigation to a subagent " +
          "(scout/researcher/investigator) with a clear brief, or finalize now. " +
          "A successful delegation resets this budget.",
      };
    }
  });

  pi.on("tool_execution_end", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (event.toolName === "subagent" && !event.isError) {
      // A successful delegation clears the deadline — the orchestrator did
      // the right thing.
      reset();
      return;
    }
    // Errored (including gate-blocked) recon calls did not gather anything;
    // do not let them advance the counter toward the gate.
    if (event.isError) return;
    if (RECON_TOOLS.includes(event.toolName)) {
      reconCount += 1;
    }
  });

  // Append the nudge to the tail of the outgoing request. Returning a new
  // `messages` array from the context hook only changes THIS provider call;
  // pi never persists it back into the session.
  pi.on("context", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (reconCount < nextNudgeAt) return;

    const nudge = {
      role: "user" as const,
      content: [
        {
          type: "text" as const,
          text:
            `${reconCount} recon-type tool calls this turn with no delegation. ` +
            "Stop and hand remaining investigation to a subagent" +
            " (scout/researcher/investigator) with a clear problem statement" +
            " unless you can name the final answer in <=2 more calls." +
            ` (recon calls will be blocked at ${GATE_THRESHOLD}.)`,
        },
      ],
      timestamp: Date.now(),
    };

    nextNudgeAt = reconCount + NUDGE_INTERVAL;
    return { messages: [...event.messages, nudge] };
  });
}
