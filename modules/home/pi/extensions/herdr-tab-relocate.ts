/**
 * Herdr tab relocation extension.
 *
 * Lets the interactive pi session relocate its own pane into another herdr
 * workspace — creating a fresh tab there — so a session started in the parent
 * workspace can move itself onto its worktree (existing or new) on its first
 * turn. `herdr pane move` relocates the pane *and the process running in it*:
 * pi keeps running, only the terminal surface moves, so this is a clean
 * self-relocation rather than a restart (verified empirically — the session
 * survives the move and keeps answering from the new workspace).
 *
 * Two call shapes:
 *   - relocate_herdr_tab(workspace, name?, label?) — move to a workspace named
 *     by id or label, optionally renaming it and labelling the new tab.
 *   - relocate_herdr_tab(name?) — the bootstrap shape, used right after
 *     `wt switch --create <branch>` moved this session's cwd into a worktree:
 *     infer the worktree from cwd, auto-open a herdr workspace for it if none
 *     exists yet (`herdr worktree open`), then move the pane there and rename.
 *     This is the second half of the two-phase bootstrap; the worktrunk switch
 *     (which moves the cwd) stays a separate first step because it is deferred
 *     and session-moving, unlike the synchronous pane move here.
 *
 * Self-identification: HERDR_PANE_ID is fixed at process spawn and goes stale
 * after the first move, but `herdr pane current` resolves the caller through
 * herdr's public_pane_id_aliases, which map the spawn-time id to the stable
 * internal pane id — so it stays correct across any number of moves. Always
 * resolve the live pane id freshly; never trust the env var.
 *
 * Requires: HERDR_ENV=1 (injected automatically by herdr).
 * NOT for subagents — same isDelegatedChild() / ctx.mode guards as
 * herdr-context-rename.ts, so a delegated child can never move its parent's pane.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { createConnection } from "node:net";

/**
 * Best-effort detection of a delegated (non-interactive) pi session.
 * See herdr-context-rename.ts for the full rationale; identical logic.
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

/**
 * Send one request to the herdr socket and resolve with the JSON response.
 * Used only for `tab.move`, which has no CLI wrapper. The socket API is
 * newline-delimited JSON: one request per line, one response per line.
 */
function socketRequest(
  method: string,
  params: Record<string, unknown>,
  timeoutMs = 3000,
): Promise<{ result?: unknown; error?: unknown }> {
  const socketPath =
    process.env.HERDR_SOCKET_PATH ||
    `${process.env.HOME ?? ""}/.config/herdr/herdr.sock`;
  const id = `pi-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  return new Promise((resolve, reject) => {
    const sock = createConnection(socketPath);
    let buf = "";
    let settled = false;
    const timer = setTimeout(() => {
      settle(() => {
        sock.destroy();
        reject(new Error("herdr socket timeout"));
      });
    }, timeoutMs);
    const settle = (fn: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn();
    };
    sock.on("connect", () => sock.write(JSON.stringify({ id, method, params }) + "\n"));
    sock.on("data", (chunk) => {
      buf += chunk.toString();
      const nl = buf.indexOf("\n");
      if (nl === -1) return;
      settle(() => {
        sock.destroy();
        try {
          resolve(JSON.parse(buf.slice(0, nl)));
        } catch {
          reject(new Error("herdr socket returned non-JSON"));
        }
      });
    });
    sock.on("error", (err) => settle(() => reject(err)));
    sock.on("close", () => settle(() => reject(new Error("herdr socket closed before response"))));
  });
}

export default function (pi: ExtensionAPI) {
  if (process.env.HERDR_ENV !== "1") return;
  if (isDelegatedChild()) return;

  // Live identity of the pane this session runs in, resolved freshly on every
  // call (see header on why the env var must not be trusted).
  async function currentPaneInfo(): Promise<
    { paneId: string; workspaceId: string; tabId: string } | undefined
  > {
    try {
      const r = await pi.exec("herdr", ["pane", "current"], { timeout: 3000 });
      if (r.code !== 0) return undefined;
      const pane = JSON.parse(r.stdout)?.result?.pane;
      if (!pane?.pane_id || !pane?.workspace_id || !pane?.tab_id) return undefined;
      return { paneId: pane.pane_id, workspaceId: pane.workspace_id, tabId: pane.tab_id };
    } catch {
      return undefined;
    }
  }

  // Resolve a target workspace by exact id first, then exact sidebar label.
  async function resolveWorkspace(target: string): Promise<string | undefined> {
    try {
      const r = await pi.exec("herdr", ["workspace", "list"], { timeout: 3000 });
      if (r.code !== 0) return undefined;
      const workspaces = (JSON.parse(r.stdout)?.result?.workspaces ?? []) as Array<{
        workspace_id?: string;
        label?: string;
      }>;
      const byId = workspaces.find((w) => w.workspace_id === target);
      if (byId?.workspace_id) return byId.workspace_id;
      const byLabel = workspaces.find((w) => w.label === target);
      return byLabel?.workspace_id;
    } catch {
      return undefined;
    }
  }

  async function workspaceSummary(): Promise<string> {
    try {
      const r = await pi.exec("herdr", ["workspace", "list"], { timeout: 3000 });
      if (r.code !== 0) return "(unavailable)";
      const workspaces = (JSON.parse(r.stdout)?.result?.workspaces ?? []) as Array<{
        workspace_id?: string;
        label?: string;
      }>;
      return workspaces
        .map((w) => `${w.label ?? "(unnamed)"} (${w.workspace_id})`)
        .join(", ");
    } catch {
      return "(unavailable)";
    }
  }

  // Bootstrap shape: infer the workspace for the worktree this session's cwd
  // is in, opening a herdr workspace for it if none exists yet. Returns the
  // workspace id, or undefined with a thrown error carrying the reason.
  async function resolveWorktreeWorkspace(): Promise<string> {
    const top = await pi.exec("git", ["rev-parse", "--show-toplevel"], {
      timeout: 3000,
    });
    if (top.code !== 0) {
      throw new Error("Not inside a git worktree (git rev-parse failed).");
    }
    const worktreePath = top.stdout.trim();

    const common = await pi.exec(
      "git",
      ["rev-parse", "--path-format=absolute", "--git-common-dir"],
      { timeout: 3000 },
    );
    if (common.code !== 0) {
      throw new Error("Could not determine the main repository for this worktree.");
    }
    const repoRoot = common.stdout.trim().replace(/\/\.git\/?$/, "");

    const list = await pi.exec("herdr", ["worktree", "list", "--cwd", repoRoot], {
      timeout: 3000,
    });
    if (list.code !== 0) {
      throw new Error(`herdr worktree list failed for ${repoRoot}.`);
    }
    let worktrees: Array<{
      path?: string;
      is_linked_worktree?: boolean;
      open_workspace_id?: string;
    }>;
    try {
      worktrees = JSON.parse(list.stdout)?.result?.worktrees ?? [];
    } catch {
      throw new Error(`herdr worktree list returned unexpected output for ${repoRoot}.`);
    }
    const entry = worktrees.find((w) => w.path === worktreePath);
    if (!entry) {
      throw new Error(`No herdr worktree entry found for ${worktreePath}.`);
    }
    if (entry.is_linked_worktree !== true) {
      throw new Error(
        "The current checkout is the main repository, not a worktree. Create a" +
          " worktree first (wt switch --create <branch>), then call" +
          " relocate_herdr_tab again.",
      );
    }
    if (entry.open_workspace_id) {
      return entry.open_workspace_id;
    }

    const open = await pi.exec("herdr", ["worktree", "open", "--path", worktreePath], {
      timeout: 5000,
    });
    if (open.code !== 0) {
      throw new Error(
        `herdr worktree open failed: ${open.stderr || open.stdout || "no output"}`,
      );
    }
    let workspaceId: string | undefined;
    try {
      workspaceId = JSON.parse(open.stdout)?.result?.workspace?.workspace_id;
    } catch {
      throw new Error("herdr worktree open returned unexpected output.");
    }
    if (!workspaceId) {
      throw new Error("herdr worktree open returned no workspace id.");
    }
    return workspaceId;
  }

  pi.registerTool({
    name: "relocate_herdr_tab",
    label: "Relocate Tab",
    description:
      "Move this pi session's own pane into another herdr workspace, opening a new tab there, and optionally rename that workspace to the task name. With no workspace argument, infer the workspace from the current worktree (opening one if needed) — the second half of the worktree bootstrap after `wt switch --create`.",
    promptSnippet: "Relocate this session to its worktree workspace",
    promptGuidelines: [
      "After wt switch --create has moved the session into a worktree, call" +
        " relocate_herdr_tab with just a name to open a herdr workspace for the" +
        " worktree, move this session's pane there, and name it after the task.",
    ],
    parameters: Type.Object({
      workspace: Type.Optional(
        Type.String({
          description:
            "Target workspace: its id (e.g. w210) or its exact sidebar label. Omit to infer it from the current worktree (bootstrap shape).",
        }),
      ),
      name: Type.Optional(
        Type.String({
          description:
            "Optional task name. Renames the target workspace to this after" +
            " relocating, so the workspace carries the task name.",
        }),
      ),
      label: Type.Optional(
        Type.String({
          description:
            "Optional label for the new tab created in the target workspace." +
            " Defaults to `pi: <name>` when name is given.",
        }),
      ),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      // Defence in depth: only the interactive TUI session owns a herdr pane.
      if (ctx.mode !== "tui") {
        throw new Error(
          "relocate_herdr_tab is only available to the interactive session that" +
            " owns the herdr pane, not to a delegated subagent.",
        );
      }

      const cur = await currentPaneInfo();
      if (!cur) {
        throw new Error(
          "Could not determine the current herdr pane (is HERDR_ENV set?).",
        );
      }

      let targetWs: string;
      if (params.workspace) {
        const resolved = await resolveWorkspace(params.workspace);
        if (!resolved) {
          const summary = await workspaceSummary();
          throw new Error(
            `No workspace matches "${params.workspace}". Available: ${summary}`,
          );
        }
        targetWs = resolved;
      } else {
        targetWs = await resolveWorktreeWorkspace();
      }

      // If we're already in the target workspace, skip the move and just
      // rename + focus if asked.
      if (targetWs === cur.workspaceId) {
        if (params.name) {
          await pi.exec("herdr", ["workspace", "rename", targetWs, params.name], {
            timeout: 5000,
          });
        }
        // Bring the client's view to this workspace in case it is elsewhere.
        await pi.exec("herdr", ["workspace", "focus", targetWs], { timeout: 5000 });
        return {
          content: [
            {
              type: "text",
              text: params.name
                ? `Already in workspace ${targetWs}; renamed to "${params.name}".`
                : `Already in workspace ${targetWs}.`,
            },
          ],
          details: {},
        };
      }

      const args = [
        "pane",
        "move",
        cur.paneId,
        "--new-tab",
        "--workspace",
        targetWs,
        "--focus",
      ];
      const tabLabel =
        params.label ?? (params.name ? `pi: ${params.name}` : undefined);
      if (tabLabel) args.push("--label", tabLabel);
      const r = await pi.exec("herdr", args, { timeout: 10000 });
      if (r.code !== 0) {
        throw new Error(
          `herdr pane move failed (exit ${r.code}): ${r.stderr || r.stdout || "no output"}`,
        );
      }
      // Move the pi tab to the front of the workspace. `tab.move` has no CLI
      // wrapper, so go through the raw socket; ordering is cosmetic, so a
      // failure here is non-fatal.
      try {
        const fresh = await currentPaneInfo();
        if (fresh) {
          await socketRequest("tab.move", {
            tab_id: fresh.tabId,
            insert_index: 0,
          });
        }
      } catch {
        // Ignore — the relocation already succeeded.
      }
      let renameNote = "";
      if (params.name) {
        const rr = await pi.exec(
          "herdr",
          ["workspace", "rename", targetWs, params.name],
          { timeout: 5000 },
        );
        renameNote =
          rr.code === 0
            ? ` Workspace renamed to "${params.name}".`
            : ` (workspace rename failed: ${rr.stderr || rr.stdout || "unknown"})`;
      }
      // Focus the workspace so the client's view follows the relocated
      // session — `pane move --focus` focuses the pane, but the client keeps
      // rendering whichever workspace it was showing.
      await pi.exec("herdr", ["workspace", "focus", targetWs], { timeout: 5000 });
      return {
        content: [
          {
            type: "text",
            text: `Relocated to workspace ${targetWs}.${renameNote}`,
          },
        ],
        details: {},
      };
    },
  });
}
