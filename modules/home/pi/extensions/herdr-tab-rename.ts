/**
 * Herdr tab renaming extension.
 *
 * On every genuine new user turn, injects an ephemeral reminder (never
 * persisted to the transcript/session — same mechanism as recon-nudge.ts)
 * naming the tab's current label and asking the LLM to judge whether it
 * still matches the conversation, calling rename_herdr_tab if not. A single
 * before_agent_start note on session start was tried first but proved
 * unreliable: it fires once, at the point in context furthest from wherever
 * the topic eventually drifts to. Keying the check to user turns instead of
 * tool-call volume matches the actual cause of drift — topic shifts happen
 * because of what the human asks next, not because of how much recon the
 * agent does investigating the same topic — and is naturally much less
 * frequent than tool-call cadence, so it stays cheap without a threshold.
 *
 * Requires: HERDR_ENV=1 (injected automatically by herdr).
 * Uses:     HERDR_TAB_ID env var — no runtime pane discovery needed.
 *
 * NOT for subagents. A delegated child pi process is spawned by its parent and
 * therefore *inherits* HERDR_ENV and HERDR_TAB_ID even though it does not own
 * that tab. Without a guard every child would register this tool — and be told
 * to call it as its first action — renaming the orchestrator's tab to whatever
 * the child happens to be doing. isDelegatedChild() keeps the tool and its
 * per-turn reminder out of child sessions entirely, so children also pay no
 * context cost for it.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

/**
 * Best-effort detection of a delegated (non-interactive) pi session.
 *
 * Two independent signals, either of which disqualifies:
 *
 *   1. PI_SUBAGENT_PARENT_SESSION naming an actual different parent. Every
 *      session — including a top-level interactive one — carries this var for
 *      mission/lineage bookkeeping, self-referencing its own PI_SESSION_ID.
 *      Only a genuine delegated child has it point at a *different* session
 *      (its orchestrator's). Comparing presence alone false-positives on every
 *      top-level session and permanently disables this extension; verified
 *      empirically: a real subagent child's PI_SUBAGENT_PARENT_SESSION equals
 *      its parent's PI_SESSION_ID, never its own.
 *   2. A headless mode flag in argv. An interactive pi occupying a herdr pane
 *      always runs in TUI mode; json/rpc/print sessions never own a pane.
 *
 * A delegated runner that sets neither signal still hits the ctx.mode check in
 * execute(), so a miss here degrades to a refused call rather than a stolen tab.
 */
function isDelegatedChild(): boolean {
  const parentSession = process.env.PI_SUBAGENT_PARENT_SESSION;
  if (parentSession && parentSession !== process.env.PI_SESSION_ID) {
    return true;
  }
  const argv = process.argv.slice(2);
  if (argv.includes("-p") || argv.includes("--print")) return true;
  const modeIndex = argv.indexOf("--mode");
  if (modeIndex !== -1 && argv[modeIndex + 1] !== "tui") return true;
  return false;
}

export default function (pi: ExtensionAPI) {
  if (process.env.HERDR_ENV !== "1") return;
  if (isDelegatedChild()) return;

  const tabId = process.env.HERDR_TAB_ID;
  if (!tabId) return;

  // Best-known current tab label. Seeded from herdr at session start, then
  // kept in sync locally on every rename this extension performs — cheaper
  // than re-querying herdr on every turn, and this extension is the only
  // expected mutator (a rare manual rename by the human is the one case this
  // can miss, and it just self-heals on the next accurate rename).
  let currentLabel: string | undefined;

  // Set on a successful rename; consumed by the very next input event to
  // skip exactly one check cycle. Asking "still accurate?" one message after
  // a rename that just happened is pure noise.
  let skipNextCheck = false;

  // Set by a genuine new user turn, consumed by the following context build
  // for that same turn. A turn can rebuild context multiple times (once per
  // tool-calling round-trip); the boolean ensures the reminder is injected
  // at most once per turn, at the first context build.
  let pendingCheck = false;

  async function seedCurrentLabel(): Promise<void> {
    try {
      const result = await pi.exec("herdr", ["tab", "get", tabId], {
        timeout: 3000,
      });
      if (result.code !== 0) return;
      const parsed = JSON.parse(result.stdout);
      const label = parsed?.result?.tab?.label;
      if (typeof label === "string" && label.length > 0) {
        currentLabel = label;
      }
    } catch {
      // Best-effort only. An unset currentLabel just makes the next check
      // treat the tab as unlabeled and ask for an initial label — the same
      // behavior as a genuinely fresh tab, so failing open here is safe.
    }
  }

  // Reset per session so /new and /resume each start from a clean check
  // cycle, and re-seed the label from herdr in case a previous process (or
  // the human) set it since we last ran.
  pi.on("session_start", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    skipNextCheck = false;
    pendingCheck = false;
    await seedCurrentLabel();
  });

  // A genuine new user turn is the natural checkpoint — excludes
  // "extension"-sourced input (queued follow-ups, not a real new turn),
  // matching the turn-boundary filter recon-nudge.ts uses for its own reset.
  pi.on("input", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (event.source === "extension") return;
    if (skipNextCheck) {
      skipNextCheck = false;
      return;
    }
    pendingCheck = true;
  });

  // Append the reminder to the tail of the outgoing request only. Returning
  // a new `messages` array from the context hook changes just that one
  // provider call; pi never persists it back into the session (verified
  // pattern, see recon-nudge.ts).
  pi.on("context", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (!pendingCheck) return;
    pendingCheck = false;

    const text = currentLabel
      ? `⚑ Herdr tab label check: current label is "${currentLabel}". Does it` +
        " still match what this conversation is actually about now? If the" +
        " topic has moved on, call rename_herdr_tab with a fresh 2–4 word" +
        " label."
      : "⚑ Herdr tab: no label set yet for this session. Call rename_herdr_tab" +
        " now with a 2–4 word lowercase label for the actual task" +
        ' (e.g. "nixvim config", "flake inputs bump", "rootless fuse wsl2").';

    return {
      messages: [
        ...event.messages,
        {
          role: "user" as const,
          content: [{ type: "text" as const, text }],
          timestamp: Date.now(),
        },
      ],
    };
  });

  pi.registerTool({
    name: "rename_herdr_tab",
    label: "Rename Tab",
    description:
      "Rename the current herdr tab to reflect what is being worked on this session.",
    promptSnippet: "Rename the current herdr tab",
    promptGuidelines: [
      'Use rename_herdr_tab as the first tool call each session to label the task.' +
        " Also call it whenever the session topic shifts significantly.",
    ],
    parameters: Type.Object({
      label: Type.String({
        description:
          'Short tab label: 2–4 words, lowercase noun phrase' +
          ' (e.g. "nixvim config", "flake inputs bump", "pr review").' +
          ' Avoid generics like "chat", "session", "work", or the bare repo name.',
      }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      // Defence in depth: isDelegatedChild() runs at factory time on env and
      // argv heuristics, while ctx.mode is pi's own authoritative answer. Only
      // a TUI session can be the interactive agent occupying a herdr pane.
      if (ctx.mode !== "tui") {
        throw new Error(
          "rename_herdr_tab is only available to the interactive session that" +
            " owns the herdr tab, not to a delegated subagent.",
        );
      }
      await pi.exec("herdr", ["tab", "rename", tabId, params.label]);
      currentLabel = params.label;
      skipNextCheck = true;
      return {
        content: [{ type: "text", text: `Tab renamed to "${params.label}".` }],
        details: {},
      };
    },
  });
}
