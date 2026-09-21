/**
 * Herdr context-rename extension (replaces herdr-tab-rename.ts).
 *
 * The rename target is now context-aware. After the relocate flow, each task
 * lives in its own linked worktree sub-workspace, so the WORKSPACE is the
 * meaningful unit (its sidebar label is what the human scans to navigate). A
 * session still sitting in a shared/parent workspace is distinguished by its
 * TAB instead. rename_herdr_context resolves the live location via
 * `herdr pane current` — never the stale HERDR_* env vars, which are fixed at
 * process spawn and drift after the first relocate (see herdr-tab-relocate.ts)
 * — and renames whichever unit is appropriate.
 *
 * The per-turn reminder is deliberately label-agnostic: showing the *current*
 * label would require async work in the context hook, which must stay
 * synchronous (verified pattern, see recon-nudge.ts). The tool itself resolves
 * fresh on every call, which is the only place the label actually matters.
 *
 * Requires: HERDR_ENV=1 (injected automatically by herdr).
 * NOT for subagents — same isDelegatedChild() / ctx.mode guards as before, so
 * a delegated child can never rename its parent's workspace or tab.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

/**
 * Best-effort detection of a delegated (non-interactive) pi session.
 * See the herdr-tab-relocate.ts header / prior herdr-tab-rename.ts for the
 * full rationale; identical logic.
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

  // Set on a successful rename; consumed by the very next input event to skip
  // exactly one check cycle. Asking "still accurate?" one message after a
  // rename that just happened is pure noise.
  let skipNextCheck = false;

  // Set by a genuine new user turn, consumed by the following context build
  // for that same turn. A turn can rebuild context multiple times (once per
  // tool-calling round-trip); the boolean ensures the reminder is injected at
  // most once per turn, at the first context build.
  let pendingCheck = false;

  // Reset per session so /new and /resume each start from a clean check cycle.
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    skipNextCheck = false;
    pendingCheck = false;
  });

  // A genuine new user turn is the natural checkpoint — excludes
  // "extension"-sourced input (queued follow-ups, not a real new turn).
  pi.on("input", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (event.source === "extension") return;
    if (skipNextCheck) {
      skipNextCheck = false;
      return;
    }
    pendingCheck = true;
  });

  // Append the reminder to the tail of the outgoing request only. Returning a
  // new `messages` array from the context hook changes just that one provider
  // call; pi never persists it back into the session (verified pattern).
  pi.on("context", (event, ctx) => {
    if (ctx.mode !== "tui") return;
    if (!pendingCheck) return;
    pendingCheck = false;

    const text =
      "⚑ Herdr label check: does the workspace (when this session lives in a" +
      " worktree sub-workspace) or tab (otherwise) still carry a label that" +
      " matches what this conversation is actually about now? If the topic has" +
      " moved on, call rename_herdr_context with a fresh 2–4 word label.";

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
    name: "rename_herdr_context",
    label: "Rename Workspace or Tab",
    description:
      "Rename the unit this session lives in to reflect the current task: in a linked worktree sub-workspace, rename the workspace and its tab; otherwise rename just the tab. The tab is always prefixed `pi: `.",
    promptSnippet: "Rename the workspace/tab this session lives in",
    promptGuidelines: [
      "Use rename_herdr_context as the first tool call each session to label the" +
        " task. Also call it whenever the session topic shifts significantly.",
    ],
    parameters: Type.Object({
      label: Type.String({
        description:
          'Short label: 2–4 words, lowercase noun phrase' +
          ' (e.g. "nixvim config", "flake inputs bump", "pr review").' +
          ' Avoid generics like "chat", "session", "work", or the bare repo name.',
      }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      // Defence in depth: only the interactive TUI session owns a herdr pane.
      if (ctx.mode !== "tui") {
        throw new Error(
          "rename_herdr_context is only available to the interactive session" +
            " that owns the herdr pane, not to a delegated subagent.",
        );
      }

      // Resolve the live location. `herdr pane current` resolves the caller
      // through herdr's public_pane_id_aliases, so it stays correct across
      // any number of relocates even though HERDR_* env vars are stale.
      let workspaceId: string | undefined;
      let tabId: string | undefined;
      let isLinked = false;
      try {
        const cur = await pi.exec("herdr", ["pane", "current"], { timeout: 3000 });
        if (cur.code !== 0) throw new Error("pane current failed");
        const pane = JSON.parse(cur.stdout)?.result?.pane;
        workspaceId = pane?.workspace_id;
        tabId = pane?.tab_id;
        if (!workspaceId || !tabId) throw new Error("missing ids");
        const ws = await pi.exec("herdr", ["workspace", "get", workspaceId], {
          timeout: 3000,
        });
        if (ws.code === 0) {
          isLinked =
            JSON.parse(ws.stdout)?.result?.workspace?.worktree?.is_linked_worktree ===
            true;
        }
      } catch {
        throw new Error("Could not determine the current herdr workspace/tab.");
      }

      if (isLinked) {
        await pi.exec("herdr", ["workspace", "rename", workspaceId!, params.label], {
          timeout: 5000,
        });
        await pi.exec("herdr", ["tab", "rename", tabId!, `pi: ${params.label}`], {
          timeout: 5000,
        });
        skipNextCheck = true;
        return {
          content: [
            {
              type: "text",
              text: `Workspace renamed to "${params.label}" and tab to "pi: ${params.label}".`,
            },
          ],
          details: {},
        };
      }

      await pi.exec("herdr", ["tab", "rename", tabId!, `pi: ${params.label}`], {
        timeout: 5000,
      });
      skipNextCheck = true;
      return {
        content: [{ type: "text", text: `Tab renamed to "pi: ${params.label}".` }],
        details: {},
      };
    },
  });
}
