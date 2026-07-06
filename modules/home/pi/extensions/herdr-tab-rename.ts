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
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  if (process.env.HERDR_ENV !== "1") return;

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
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      await pi.exec("herdr", ["tab", "rename", tabId, params.label]);
      return {
        content: [{ type: "text", text: `Tab renamed to "${params.label}".` }],
        details: {},
      };
    },
  });
}
