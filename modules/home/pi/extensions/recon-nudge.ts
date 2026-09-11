/**
 * Nudge the interactive orchestrator to delegate when it keeps doing
 * recon-type tool calls itself instead of handing investigation to a subagent.
 *
 * WHY
 * ---
 * The orchestrator's main cost lever is its own context size, and every
 * read/grep/find/web-fetch it performs in-turn adds a round-trip that a cheap
 * read-only scout could absorb instead. The delegation policy
 * (05-delegation) already says "delegate after ~3 tool round-trips", but a
 * long turn can drift past that silently. This extension enforces the
 * deadline mechanically: it counts recon-shaped tool calls per turn and, once
 * the count crosses a threshold, appends a directive nudge to the tail of the
 * outgoing request telling the model to stop and delegate.
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

const THRESHOLD = 8;
const INTERVAL = 5;

export default function (pi: ExtensionAPI) {
  // Per-session state. `/reload`, `/new` and session switches re-run
  // session_start, which resets the counter (same pattern as
  // worktrunk-deferred.ts).
  let reconCount = 0;
  let nextNudgeAt = THRESHOLD;

  const reset = () => {
    reconCount = 0;
    nextNudgeAt = THRESHOLD;
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

  pi.on("tool_execution_end", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (event.toolName === "subagent" && !event.isError) {
      // A successful delegation clears the deadline — the orchestrator did
      // the right thing.
      reset();
      return;
    }
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
            " unless you can name the final answer in <=2 more calls.",
        },
      ],
      timestamp: Date.now(),
    };

    nextNudgeAt = reconCount + INTERVAL;
    return { messages: [...event.messages, nudge] };
  });
}
