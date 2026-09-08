/**
 * Herdr tab renaming extension.
 *
 * On the first prompt of each session, injects a one-time system-prompt note
 * asking the LLM to call rename_herdr_tab before starting work. The tool
 * remains available throughout the session so the LLM can update the label
 * when the topic shifts significantly.
 *
 * Requires: HERDR_ENV=1 (injected automatically by herdr).
 * Uses:     HERDR_TAB_ID env var — no runtime pane discovery needed.
 *
 * NOT for subagents. A delegated child pi process is spawned by its parent and
 * therefore *inherits* HERDR_ENV and HERDR_TAB_ID even though it does not own
 * that tab. Without a guard every child would register this tool — and be told
 * to call it as its first action — renaming the orchestrator's tab to whatever
 * the child happens to be doing. isDelegatedChild() keeps the tool and its
 * system-prompt note out of child sessions entirely, so children also pay no
 * context cost for it.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

/**
 * Best-effort detection of a delegated (non-interactive) pi session.
 *
 * Two independent signals, either of which disqualifies:
 *
 *   1. PI_SUBAGENT_* env markers, set by subagent extensions when spawning a
 *      child (run id, agent name, child index, orchestrator target). Matched by
 *      prefix rather than by exact name so the check does not depend on which
 *      subset of those variables a given version happens to export.
 *   2. A headless mode flag in argv. An interactive pi occupying a herdr pane
 *      always runs in TUI mode; json/rpc/print sessions never own a pane.
 *
 * A delegated runner that sets neither signal still hits the ctx.mode check in
 * execute(), so a miss here degrades to a refused call rather than a stolen tab.
 */
function isDelegatedChild(): boolean {
  if (Object.keys(process.env).some((k) => k.startsWith("PI_SUBAGENT_"))) {
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

  // Reset per session so /new and /resume each get a fresh injection.
  let injected = false;
  pi.on("session_start", async () => {
    injected = false;
  });

  // First prompt only: append a one-time note to the system prompt asking
  // the LLM to label the tab before starting work. The note is intentionally
  // brief to minimise token overhead and does not repeat on subsequent turns.
  pi.on("before_agent_start", async (event) => {
    if (injected) return;
    injected = true;
    return {
      systemPrompt:
        event.systemPrompt +
        '\n\n⚑ Herdr tab: call rename_herdr_tab as your first tool call this' +
        ' session with a 2–4 word lowercase label for the actual task' +
        ' (e.g. "nixvim config", "flake inputs bump", "rootless fuse wsl2").',
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
      return {
        content: [{ type: "text", text: `Tab renamed to "${params.label}".` }],
        details: {},
      };
    },
  });
}
