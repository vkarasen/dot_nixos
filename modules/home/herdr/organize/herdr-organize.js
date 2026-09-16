// herdr-organize — relocate misplaced pi tabs into their correct herdr workspace.
//
// A pi session's authoritative working directory is encoded in the directory
// name of its session file path (`agent_session.value`), using pi's encoding:
//
//     `--${cwd.replace(/^[/\\]/,"").replace(/[/\\:]/g,"-")}--`
//
// A relocated pi pane's own `cwd` field is stale (it shows the checkout the
// pane was spawned in, not where its session now lives), so this script matches
// by ENCODING known checkout paths forward and comparing — never by decoding,
// because decoding is lossy (a literal "-" is ambiguous with an encoded "/").
//
// Behaviour per pi pane:
//   - session dir matches an open workspace's checkout and the pane is already
//     there            -> "ok" (no action)
//   - matches, but the pane is elsewhere -> move it (pane move --new-tab) and
//     relabel the new tab "pi: <name>"
//   - no open workspace matches the session dir -> "skip" (reported, not moved;
//     run `herdr worktree open --path <checkout>` first if one should exist)
//
// Usage: herdr-organize [--dry-run|-n] [--help|-h]

"use strict";

const { execFileSync } = require("node:child_process");
const path = require("node:path");

const HERDR = process.env.HERDR_BIN_PATH || "herdr";
const DRY_RUN = process.argv.includes("--dry-run") || process.argv.includes("-n");
const HELP = process.argv.includes("--help") || process.argv.includes("-h");

function herdrJson(...args) {
  const out = execFileSync(HERDR, args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  try {
    return JSON.parse(out);
  } catch (e) {
    throw new Error(
      `herdr ${args.join(" ")} returned non-JSON output: ` +
        String((e && e.message) || e).split("\n")[0],
    );
  }
}

// pi's exact cwd -> session-dir-name encoding (forward direction only).
function encodeCwd(cwd) {
  return "--" + cwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-") + "--";
}

// Human label for a moved tab: strip the "π - " prefix off the pane's terminal
// title, falling back to the target checkout's basename.
function labelFor(pane, wsInfo) {
  const title = String(pane.terminal_title || "")
    .replace(/^\s*π\s*-\s*/, "")
    .trim();
  if (title) return "pi: " + title;
  const fallback =
    (wsInfo && path.basename(wsInfo.checkout_path || "")) ||
    (wsInfo && wsInfo.label) ||
    "pi";
  return "pi: " + fallback;
}

function pad(s, n) {
  return String(s).padEnd(n);
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function main() {
  if (HELP) {
    console.log(
      "herdr-organize: move misplaced pi tabs into their correct herdr workspace.\n\n" +
        "  herdr-organize              scan and fix (moves misplaced tabs)\n" +
        "  herdr-organize --dry-run    preview only, move nothing\n",
    );
    return;
  }

  let panes;
  let workspaces;
  try {
    panes = (herdrJson("pane", "list").result || {}).panes || [];
    workspaces = (herdrJson("workspace", "list").result || {}).workspaces || [];
  } catch (e) {
    console.error(
      "herdr-organize: failed to query herdr (" +
        String((e && e.message) || e).split("\n")[0] +
        "). Is a herdr server running?",
    );
    process.exit(1);
  }

  // encoded checkout -> workspace_id, for every OPEN workspace that carries a
  // worktree checkout (parent checkouts and linked worktree sub-workspaces).
  const checkoutToWorkspace = new Map();
  const wsById = new Map();
  for (const ws of workspaces) {
    wsById.set(ws.workspace_id, ws);
    const cp = ws.worktree && ws.worktree.checkout_path;
    if (cp) checkoutToWorkspace.set(encodeCwd(cp), ws.workspace_id);
  }

  const piPanes = panes.filter(
    (p) =>
      p.agent === "pi" &&
      p.agent_session &&
      p.agent_session.kind === "path" &&
      p.agent_session.value,
  );

  if (piPanes.length === 0) {
    console.log("herdr-organize: no pi panes found.");
    return;
  }

  const rows = [];
  let ok = 0;
  let moved = 0;
  let skipped = 0;
  let errors = 0;

  for (const pane of piPanes) {
    const sessionDir = path.basename(path.dirname(pane.agent_session.value));
    const title = String(pane.terminal_title || pane.pane_id);
    const targetWs = checkoutToWorkspace.get(sessionDir);

    if (!targetWs) {
      skipped++;
      // Distinguish a plain (non-worktree) workspace — where the pane's cwd is
      // current and it's already in the right place — from a session that has
      // moved to a worktree with no open workspace.
      const stale = encodeCwd(String(pane.cwd || "")) !== sessionDir;
      rows.push({
        status: "skip",
        pane: pane.pane_id,
        title,
        note: stale
          ? "no matching workspace; session may have moved to an unopened worktree"
          : "plain workspace (no herdr checkout); already in place",
      });
      continue;
    }

    if (targetWs === pane.workspace_id) {
      ok++;
      rows.push({ status: "ok", pane: pane.pane_id, title, note: targetWs });
      continue;
    }

    const label = labelFor(pane, wsById.get(targetWs));
    if (DRY_RUN) {
      moved++;
      rows.push({
        status: "would-move",
        pane: pane.pane_id,
        title,
        note: `${pane.workspace_id} -> ${targetWs}  (${label})`,
      });
      continue;
    }

    try {
      execFileSync(
        HERDR,
        [
          "pane", "move", pane.pane_id,
          "--new-tab",
          "--workspace", targetWs,
          "--focus",
          "--label", label,
        ],
        { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
      );
      moved++;
      rows.push({
        status: "moved",
        pane: pane.pane_id,
        title,
        note: `${pane.workspace_id} -> ${targetWs}  (${label})`,
      });
    } catch (e) {
      errors++;
      rows.push({
        status: "error",
        pane: pane.pane_id,
        title,
        note: String((e && e.message) || e).split("\n")[0],
      });
    }
  }

  console.log(pad("STATUS", 10) + pad("PANE", 11) + pad("TITLE", 42) + "DETAIL");
  console.log("-".repeat(110));
  for (const r of rows) {
    console.log(
      pad(r.status, 10) + pad(r.pane, 11) + pad(truncate(r.title, 42), 42) + (r.note || ""),
    );
  }
  console.log("-".repeat(110));
  console.log(
    `pi panes: ${piPanes.length}   ok: ${ok}   ` +
      `${DRY_RUN ? "would-move" : "moved"}: ${moved}   skipped: ${skipped}   errors: ${errors}`,
  );
  if (DRY_RUN) {
    console.log("(dry run — nothing was moved; rerun without --dry-run to apply)");
  }
}

main();
