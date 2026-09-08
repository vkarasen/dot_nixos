/**
 * Defer the `worktrunk` tool until it is actually needed.
 *
 * WHY
 * ---
 * `pi-worktrunk` is worth keeping: it moves the Pi session on `wt switch`,
 * recovers when the current worktree is removed, mirrors Pi's lifecycle into
 * `wt list` branch markers, and gates model-initiated aliases/hooks/admin
 * changes behind confirmation. None of that is replaceable by `bash wt`.
 *
 * What is *not* worth keeping always-on is its tool description: it inlines the
 * complete generated `wt` CLI reference. Measured on this setup that single
 * tool is ~27KB — about a quarter of the entire always-on context budget —
 * whether or not the session ever touches a worktree.
 *
 * The extension exposes no knob for this (`WORKTRUNK_REFERENCE` is baked into
 * `description`), so this shim deactivates the tool instead. Inactive tools
 * stay registered but are never sent to the provider. `pi-lens` already relies
 * on the same mechanism, which is how it keeps ~20KB of situational tools out
 * of the prompt.
 *
 * Nothing else is affected: `/wt` is a slash command, not a tool, and costs no
 * prompt tokens; session placement, markers, recovery and approval gating all
 * live in the extension and keep working.
 *
 * TIMING
 * ------
 * `pi-worktrunk` registers its tool *inside* its own `session_start` handler,
 * after an await. Racing it there is unreliable, so this shim acts at
 * `before_agent_start`, which pi runs after every `session_start` handler has
 * settled and before the first provider request — the same point at which the
 * tool inventory was measured.
 *
 * REMOVE THIS when pi-worktrunk gains a native way to defer or compact its
 * reference (upstream: mavam/pi-worktrunk).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const DEFERRED_TOOL = "worktrunk";

export default function (pi: ExtensionAPI) {
  // Per-session state. `/reload`, `/new` and session switches re-run
  // session_start, which re-registers (and re-activates) the worktrunk tool,
  // so the deferral has to be re-applied for each new session.
  let activated = false;
  let deferred = false;

  pi.on("session_start", () => {
    activated = false;
    deferred = false;
  });

  pi.on("before_agent_start", () => {
    if (activated || deferred) return;
    const active = pi.getActiveTools();
    if (!active.includes(DEFERRED_TOOL)) {
      // Not registered yet, or already inactive. Either way there is nothing
      // to do; stay unlatched so a later turn can retry if it appears.
      return;
    }
    pi.setActiveTools(active.filter((name: string) => name !== DEFERRED_TOOL));
    deferred = true;
  });

  pi.registerTool({
    name: "activate_worktrunk",
    label: "Activate Worktrunk",
    description:
      "Load the full `worktrunk` tool, which carries the complete wt command" +
      " reference. Call this once before any Worktrunk operation (switch," +
      " create a worktree, merge, remove, list, hooks, aliases). The worktrunk" +
      " tool becomes available on the next turn.",
    // Deliberately no promptSnippet: activating a tool that carries prompt
    // metadata rebuilds the system prompt, and this one is meant to be cheap.
    promptGuidelines: [
      "Never run `wt` through bash — it will not move the Pi session." +
        " Call activate_worktrunk first, then use the worktrunk tool.",
    ],
    parameters: Type.Object({}, { additionalProperties: false }),
    async execute() {
      const all = pi.getAllTools().map((t: { name: string }) => t.name);
      if (!all.includes(DEFERRED_TOOL)) {
        throw new Error(
          "The worktrunk tool is not registered. Is pi-worktrunk installed," +
            " and is this a git repository Worktrunk can manage?",
        );
      }
      activated = true;
      // Additive change: keeps the provider's cached prompt prefix valid on
      // models that support deferred tool loading.
      const active = pi.getActiveTools();
      if (!active.includes(DEFERRED_TOOL)) {
        pi.setActiveTools([...active, DEFERRED_TOOL]);
      }
      return {
        content: [
          {
            type: "text",
            text: "The worktrunk tool is now available. Use it for all wt commands.",
          },
        ],
        details: {},
      };
    },
  });
}
