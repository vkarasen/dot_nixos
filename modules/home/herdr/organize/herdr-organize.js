// herdr-organize — consolidate herdr workspaces and relocate misplaced tabs.
//
// Four jobs, one pass over herdr's own JSON:
//
//   1. Relocate tabs — move every pane into the workspace that owns its
//      checkout. A pi session goes where its session file says it is (the
//      cwd encoded in the session dir name; a relocated pane's own `cwd` is
//      stale, so the session dir is authoritative). A plain shell goes where
//      its cwd (or git toplevel) says. A linked worktree with no open
//      workspace is opened (herdr worktree open --path) so the tab has
//      somewhere to land.
//
//   2. Consolidate duplicate workspaces — group workspaces by the checkout
//      they're rooted at, keep one canonical workspace per checkout (prefer
//      the herdr-managed one, else most panes, else lowest number), move
//      every pane out of the others, then close the now-empty duplicates.
//
//   3. Sort + rename — after relocation, within each linked worktree
//      sub-workspace move pi tabs to the front and rename only stale labels
//      (empty/auto-numbered tab labels, empty/auto-slug workspace labels).
//
//   4. Repair hijacked worktree associations — a NON-linked workspace that
//      stole a linked worktree's open_workspace_id (the corruption the pi
//      launcher used to cause by calling `herdr worktree open` without
//      --cwd, so herdr rooted the workspace at the caller's stale cwd, i.e.
//      the main checkout, instead of at the worktree). See
//      repairHijackedWorktrees() below; runs FIRST, then the other passes
//      re-read the repaired state.
//
// Safety: nothing is ever force-deleted. A duplicate is closed only after all
// its panes have moved out (0 remain). Workspaces whose checkout can't be
// determined are reported and left untouched. `--dry-run` previews everything.
//
// Usage: herdr-organize [--dry-run|-n] [--help|-h]

"use strict";

const { execFileSync } = require("node:child_process");
const path = require("node:path");

const HERDR = process.env.HERDR_BIN_PATH || "herdr";
const DRY_RUN = process.argv.includes("--dry-run") || process.argv.includes("-n");
const HELP = process.argv.includes("--help") || process.argv.includes("-h");

function run(cmd, args) {
  return execFileSync(cmd, args, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

function herdrJson(...args) {
  try {
    return JSON.parse(run(HERDR, args));
  } catch (e) {
    throw new Error(
      `herdr ${args.join(" ")} failed: ` +
        String((e && e.message) || e).split("\n")[0],
    );
  }
}

function tryHerdrJson(...args) {
  try {
    return JSON.parse(run(HERDR, args));
  } catch {
    return null;
  }
}

// pi's exact cwd -> session-dir-name encoding (forward direction only).
function encodeCwd(cwd) {
  return "--" + cwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-") + "--";
}

function pad(s, n) {
  return String(s).padEnd(n);
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function isPi(pane) {
  return (
    pane.agent === "pi" &&
    pane.agent_session &&
    pane.agent_session.kind === "path" &&
    pane.agent_session.value
  );
}

function sessionDirOf(pane) {
  return path.basename(path.dirname(pane.agent_session.value));
}

function labelFor(pane, checkout) {
  const title = String(pane.terminal_title || "")
    .replace(/^\s*π\s*-\s*/, "")
    .trim();
  if (title) return "pi: " + title;
  return "pi: " + (checkout ? path.basename(checkout) : "pi");
}

// A tab label is "stale" (safe to rename) when empty or a bare auto-number.
function isStaleTabLabel(label) {
  return !label || /^[0-9]+$/.test(label);
}

// A workspace label is "stale" when empty or the auto-slug `wt switch --create`
// generates (pi-YYYYmmdd-HHMMSS). Never rename a label a human/agent has set.
function isStaleWorkspaceLabel(label) {
  return !label || /^pi-\d{8}-\d{6}$/.test(label);
}

// Sort + rename, after relocation. Sorts only linked worktree sub-workspaces
// (pi tabs to the front, preserving their relative order); the main checkout
// and other plain workspaces are left in place so a human's deliberate tab
// order is preserved. Renames are conservative: only stale labels (empty /
// auto-numbered tabs, empty / auto-slug workspaces) are touched.
function sortAndRename(panes, workspaces, tabs, wtByPath, dry) {
  const rows = [];
  const piTabIds = new Set();
  for (const p of panes) {
    if (p.agent === "pi" && p.tab_id) piTabIds.add(p.tab_id);
  }
  const panesByTab = new Map();
  for (const p of panes) {
    if (!panesByTab.has(p.tab_id)) panesByTab.set(p.tab_id, []);
    panesByTab.get(p.tab_id).push(p);
  }
  const tabsByWs = new Map();
  for (const t of tabs) {
    if (!tabsByWs.has(t.workspace_id)) tabsByWs.set(t.workspace_id, []);
    tabsByWs.get(t.workspace_id).push(t);
  }

  for (const ws of workspaces) {
    const linked = !!(ws.worktree && ws.worktree.is_linked_worktree);
    const checkout = ws.worktree && ws.worktree.checkout_path;
    const wtMeta = checkout ? wtByPath.get(checkout) : null;
    const wsTabs = tabsByWs.get(ws.workspace_id) || [];
    const piTabs = wsTabs.filter((t) => piTabIds.has(t.tab_id));

    if (linked && isStaleWorkspaceLabel(ws.label)) {
      const branch = (wtMeta && wtMeta.branch) || (checkout ? path.basename(checkout) : "");
      if (branch && branch !== ws.label) {
        const note = `${ws.label || "(empty)"} -> ${branch}`;
        if (dry) {
          rows.push({ status: "would-rename-ws", pane: ws.workspace_id, title: ws.label || "", note });
        } else {
          try {
            run(HERDR, ["workspace", "rename", ws.workspace_id, branch]);
            rows.push({ status: "renamed-ws", pane: ws.workspace_id, title: ws.label || "", note });
          } catch (e) {
            rows.push({ status: "error", pane: ws.workspace_id, title: ws.label || "", note: "rename ws: " + (e.message || e) });
          }
        }
      }
    }

    if (linked && piTabs.length > 0) {
      let idx = 0;
      for (const t of piTabs) {
        const note = `-> index ${idx}`;
        if (dry) {
          rows.push({ status: "would-move-tab", pane: t.tab_id, title: t.label || "", note });
        } else {
          try {
            run("herdr-tab-move", [t.tab_id, String(idx)]);
            rows.push({ status: "moved-tab", pane: t.tab_id, title: t.label || "", note });
          } catch (e) {
            rows.push({ status: "error", pane: t.tab_id, title: t.label || "", note: "move tab: " + (e.message || e) });
          }
        }
        idx++;
      }
    }

    for (const t of piTabs) {
      if (!isStaleTabLabel(t.label)) continue;
      const pane = (panesByTab.get(t.tab_id) || []).find((p) => p.agent === "pi");
      if (!pane) continue;
      const label = labelFor(pane, checkout || null);
      if (!label || label === t.label) continue;
      const note = `${t.label || "(empty)"} -> ${label}`;
      if (dry) {
        rows.push({ status: "would-rename-tab", pane: t.tab_id, title: t.label || "", note });
      } else {
        try {
          run(HERDR, ["tab", "rename", t.tab_id, label]);
          rows.push({ status: "renamed-tab", pane: t.tab_id, title: t.label || "", note });
        } catch (e) {
          rows.push({ status: "error", pane: t.tab_id, title: t.label || "", note: "rename tab: " + (e.message || e) });
        }
      }
    }
  }
  return rows;
}

// Every linked worktree herdr knows about, keyed by path. Repo candidates:
// herdr-managed repo_roots PLUS every workspace checkout (a plain workspace
// rooted at a git repo still needs its worktrees listed).
function buildWorktreeCatalog(workspaces, wsCheckout) {
  const repoCands = new Set();
  for (const ws of workspaces) {
    if (ws.worktree && ws.worktree.repo_root) repoCands.add(ws.worktree.repo_root);
    const c = wsCheckout.get(ws.workspace_id);
    if (c) repoCands.add(c);
  }
  const wtByPath = new Map(); // path -> { branch, is_linked, open_ws, repo_root }
  for (const repo of repoCands) {
    const j = tryHerdrJson("worktree", "list", "--cwd", repo);
    if (!j || !j.result || !Array.isArray(j.result.worktrees)) continue;
    for (const wt of j.result.worktrees) {
      if (!wt.path) continue;
      wtByPath.set(wt.path, {
        branch: wt.branch || null,
        is_linked: !!wt.is_linked_worktree,
        open_ws: wt.open_workspace_id || null,
        repo_root: repo,
      });
    }
  }
  return wtByPath;
}

// Is any linked worktree still associated with this workspace? herdr refuses
// to close a workspace that has open linked children, and the fix is NOT to
// force it (`workspace close --group` closes the whole repo group) but to
// leave the workspace alone and re-run once the children are gone.
function hasOpenLinkedChildren(repoRoot, workspaceId) {
  const j = tryHerdrJson("worktree", "list", "--cwd", repoRoot);
  if (!j || !j.result || !Array.isArray(j.result.worktrees)) return true; // unknown -> assume yes, do not close
  return j.result.worktrees.some(
    (w) => w.is_linked_worktree && w.open_workspace_id === workspaceId,
  );
}

// The corruption class: a workspace W that is NOT a linked worktree, yet W is
// the open_workspace_id herdr reports for a LINKED worktree T whose path is not
// W's own checkout. T's association was pointed at a workspace rooted somewhere
// else (historically: at main, because `herdr worktree open` ran with a stale
// cwd), so T has no workspace of its own and its pi session silently lives in a
// workspace that does not own its checkout. Corroborated when W also holds a pi
// pane whose session dir encodes T's path (a live pi agent in the wrong place).
//
// Repair, in order (each step is a precondition for the next):
//   (i)   `herdr worktree open --cwd <repo root> --path <T.path>` — mint a
//         properly linked sub-workspace for T. bash.nix now prevents new ones;
//         this cleans up the old ones.
//   (ii)  move W's pi panes that belong to T into that new workspace.
//   (iii) move W's stray main-rooted shell panes back to the canonical source
//         workspace for that checkout — the other non-linked workspace with the
//         same checkout that is NOT itself a hijacker. If there is none, the
//         shells stay and W stays (never strand a checkout without a home).
//   (iv)  close the now-emptied W, only at zero panes and only when no linked
//         worktree is still associated with it. `workspace close` takes a plain
//         id here; `--group` is never used.
//
// Non-destructive and idempotent: after a successful repair W no longer matches
// the detection (it is gone or its association was re-pointed), so a re-run
// reports nothing. `--dry-run` plans every step and touches nothing.
function repairHijackedWorktrees(
  panes,
  workspaces,
  wtByPath,
  wsCheckout,
  encodedToPath,
  resolveShell,
  dry,
) {
  const rows = [];
  const panesByWs = new Map();
  for (const p of panes) {
    if (!panesByWs.has(p.workspace_id)) panesByWs.set(p.workspace_id, []);
    panesByWs.get(p.workspace_id).push(p);
  }

  // ---- detect ----
  const plans = [];
  const hijackers = new Set();
  for (const ws of workspaces) {
    const wid = ws.workspace_id;
    if (ws.worktree && ws.worktree.is_linked_worktree) continue; // W is linked: not this class
    const wCheckout = wsCheckout.get(wid) || null;
    if (!wCheckout) continue; // unrecorded/ambiguous checkout: cannot prove a mismatch
    for (const [tPath, t] of wtByPath) {
      if (!t.is_linked || t.open_ws !== wid || tPath === wCheckout) continue;
      const cellPanes = panesByWs.get(wid) || [];
      const tPiPanes = cellPanes.filter(
        (p) => isPi(p) && encodedToPath.get(sessionDirOf(p)) === tPath,
      );
      plans.push({
        wid,
        wsLabel: ws.label || wid,
        wCheckout,
        tPath,
        t,
        cellPanes,
        tPiPanes,
        corroborated: tPiPanes.length > 0,
      });
      hijackers.add(wid);
    }
  }
  if (plans.length === 0) return { rows, hijacks: 0, changed: false };

  // A source workspace to park W's stray shells in: same checkout, non-linked,
  // itself not a hijacker, not W. Nothing is moved out of W (and W is never
  // closed) when none exists.
  function sourceWorkspaceFor(wid, checkout) {
    return (
      workspaces
        .filter(
          (w) =>
            w.workspace_id !== wid &&
            !hijackers.has(w.workspace_id) &&
            !(w.worktree && w.worktree.is_linked_worktree) &&
            (wsCheckout.get(w.workspace_id) || null) === checkout,
        )
        .sort((a, b) => (b.pane_count || 0) - (a.pane_count || 0))[0] || null
    );
  }

  let changed = false;
  for (const plan of plans) {
    const { wid, wsLabel, wCheckout, tPath, t } = plan;
    const repoRoot = t.repo_root || wCheckout;
    const branch = t.branch || path.basename(tPath);
    rows.push({
      status: "hijack",
      pane: wid,
      title: wsLabel,
      note:
        `${tPath} misplaced (linked worktree pointed at ${wid}` +
        `, rooted at ${wCheckout})` +
        (plan.corroborated
          ? `; ${plan.tPiPanes.length} pi pane(s) corroborate`
          : "; no pi pane corroborates - minting anyway, moving nothing unproven"),
    });

    // ---- (i) mint a properly linked sub-workspace for T ----
    let newWs = null;
    if (dry) {
      rows.push({
        status: "would-open-worktree",
        pane: wid,
        title: wsLabel,
        note: `worktree open --cwd ${repoRoot} --path ${tPath}  (label: ${branch})`,
      });
    } else {
      const j = tryHerdrJson(
        "worktree", "open",
        "--cwd", repoRoot,
        "--path", tPath,
        "--label", branch,
        "--no-focus",
      );
      newWs = j && j.result && j.result.workspace ? j.result.workspace.workspace_id : null;
      if (!newWs) {
        rows.push({
          status: "error",
          pane: wid,
          title: wsLabel,
          note: `worktree open failed for ${tPath} - leaving ${wid} untouched`,
        });
        continue; // nothing else is safe without a destination
      }
      changed = true;
      // Validate the minted workspace before moving anything into it: it must
      // be a linked workspace rooted at T. If herdr handed back the very
      // workspace that hijacked T (or anything else), move nothing and close
      // nothing — the global scan will retry after the situation changes.
      const chk = tryHerdrJson("workspace", "get", newWs);
      const newWt =
        chk && chk.result && chk.result.workspace
          ? chk.result.workspace.worktree
          : null;
      if (
        !newWt ||
        newWt.is_linked_worktree !== true ||
        newWt.checkout_path !== tPath
      ) {
        rows.push({
          status: "error",
          pane: wid,
          title: wsLabel,
          note: `worktree open returned ${newWs}, not a linked workspace for ${tPath} - moving nothing`,
        });
        continue;
      }
      rows.push({
        status: "opened-worktree",
        pane: wid,
        title: wsLabel,
        note: `${newWs} for ${tPath} (label: ${branch})`,
      });
    }

    const dest = dry ? "(new workspace)" : newWs;

    // ---- (ii) move W's pi panes that belong to T ----
    for (const p of plan.tPiPanes) {
      const label = labelFor(p, tPath);
      if (dry) {
        rows.push({
          status: "would-move",
          pane: p.pane_id,
          title: String(p.terminal_title || p.pane_id),
          note: `${wid} -> ${dest}  (${label})`,
        });
      } else {
        try {
          run(HERDR, [
            "pane", "move", p.pane_id,
            "--new-tab",
            "--workspace", newWs,
            "--label", label,
            "--focus",
          ]);
          changed = true;
          rows.push({
            status: "moved",
            pane: p.pane_id,
            title: String(p.terminal_title || p.pane_id),
            note: `${wid} -> ${newWs}  (${label})`,
          });
        } catch (e) {
          rows.push({
            status: "error",
            pane: p.pane_id,
            title: String(p.terminal_title || p.pane_id),
            note: String((e && e.message) || e).split("\n")[0],
          });
        }
      }
    }

    // ---- (iii) move W's stray main-rooted shells back to the source ws ----
    const shells = plan.cellPanes.filter((p) => !isPi(p));
    const sourceWs = sourceWorkspaceFor(wid, wCheckout);
    if (shells.length > 0 && !sourceWs) {
      rows.push({
        status: "keep",
        pane: wid,
        title: wsLabel,
        note: `no canonical source workspace for ${wCheckout} - leaving its shell(s) and ${wid} intact`,
      });
    } else if (sourceWs) {
      for (const p of shells) {
        const pCheckout = resolveShell(p);
        if (pCheckout !== wCheckout) {
          rows.push({
            status: "skip",
            pane: p.pane_id,
            title: String(p.terminal_title || p.pane_id),
            note: `shell not rooted at ${wCheckout} - left for the relocate pass`,
          });
          continue;
        }
        if (dry) {
          rows.push({
            status: "would-move",
            pane: p.pane_id,
            title: String(p.terminal_title || p.pane_id),
            note: `${wid} -> ${sourceWs.workspace_id}  (stray shell)`,
          });
        } else {
          try {
            run(HERDR, [
              "pane", "move", p.pane_id,
              "--new-tab",
              "--workspace", sourceWs.workspace_id,
              "--no-focus",
            ]);
            changed = true;
            rows.push({
              status: "moved",
              pane: p.pane_id,
              title: String(p.terminal_title || p.pane_id),
              note: `${wid} -> ${sourceWs.workspace_id}  (stray shell)`,
            });
          } catch (e) {
            rows.push({
              status: "error",
              pane: p.pane_id,
              title: String(p.terminal_title || p.pane_id),
              note: String((e && e.message) || e).split("\n")[0],
            });
          }
        }
      }
    }

    // ---- (iv) close the emptied W, only at zero panes and no linked children ----
    if (dry) {
      rows.push({
        status: "would-close",
        pane: wid,
        title: wsLabel,
        note: `if it reaches 0 panes and no linked worktree is left pointing at it`,
      });
      continue;
    }
    if (!sourceWs) {
      rows.push({
        status: "keep",
        pane: wid,
        title: wsLabel,
        note: "no source workspace to absorb its shells - not closing",
      });
      continue;
    }
    const live =
      (tryHerdrJson("workspace", "list") || {}).result || {};
    const liveWs = (live.workspaces || []).find(
      (w) => w.workspace_id === wid,
    );
    if (!liveWs) continue; // already gone
    if ((liveWs.pane_count || 0) > 0) {
      rows.push({
        status: "keep",
        pane: wid,
        title: wsLabel,
        note: `${liveWs.pane_count} pane(s) still inside - not closing`,
      });
      continue;
    }
    if (hasOpenLinkedChildren(repoRoot, wid)) {
      rows.push({
        status: "keep",
        pane: wid,
        title: wsLabel,
        note: "linked worktree(s) still associated (workspace_group_close_required) - not closing",
      });
      continue;
    }
    try {
      run(HERDR, ["workspace", "close", wid]);
      changed = true;
      rows.push({
        status: "closed",
        pane: wid,
        title: wsLabel,
        note: "emptied mis-rooted workspace",
      });
    } catch (e) {
      rows.push({
        status: "keep",
        pane: wid,
        title: wsLabel,
        note: String((e && e.message) || e).split("\n")[0],
      });
    }
  }

  return { rows, hijacks: plans.length, changed };
}

// Compute per-workspace identity and the canonical workspace per checkout.
// Returns { wsById, wsCheckout, wsLinked, canonical, duplicates }.
function computeModel(panes, workspaces) {
  const wsById = new Map();
  for (const ws of workspaces) wsById.set(ws.workspace_id, ws);

  const panesByWs = new Map();
  for (const p of panes) {
    if (!panesByWs.has(p.workspace_id)) panesByWs.set(p.workspace_id, []);
    panesByWs.get(p.workspace_id).push(p);
  }

  const wsCheckout = new Map(); // ws_id -> checkout path (or null)
  const wsLinked = new Map(); // ws_id -> true/false (herdr-managed) or null (plain)

  for (const ws of workspaces) {
    if (ws.worktree && ws.worktree.checkout_path) {
      wsCheckout.set(ws.workspace_id, ws.worktree.checkout_path);
      wsLinked.set(ws.workspace_id, !!ws.worktree.is_linked_worktree);
    } else {
      // Plain workspace: its checkout is the dominant cwd across its panes.
      // Ambiguous (no strict majority) -> null, left untouched.
      const cs = panesByWs.get(ws.workspace_id) || [];
      const counts = new Map();
      for (const p of cs) {
        const cwd = p.cwd || "";
        counts.set(cwd, (counts.get(cwd) || 0) + 1);
      }
      let dom = null;
      let domN = 0;
      let tie = false;
      for (const [cwd, n] of counts) {
        if (n > domN) {
          dom = cwd;
          domN = n;
          tie = false;
        } else if (n === domN) {
          tie = true;
        }
      }
      wsCheckout.set(
        ws.workspace_id,
        dom !== null && !tie && domN > 0 ? dom : null,
      );
      wsLinked.set(ws.workspace_id, null);
    }
  }

  // Group workspaces by checkout; keep one canonical per checkout.
  const byCheckout = new Map();
  for (const ws of workspaces) {
    const c = wsCheckout.get(ws.workspace_id);
    if (!c) continue;
    if (!byCheckout.has(c)) byCheckout.set(c, []);
    byCheckout.get(c).push(ws.workspace_id);
  }

  const canonical = new Map(); // checkout -> kept ws_id
  const duplicates = new Set(); // non-canonical ws_ids
  for (const [c, ids] of byCheckout) {
    if (ids.length === 1) {
      canonical.set(c, ids[0]);
      continue;
    }
    const keep = [...ids].sort((a, b) => {
      const wa = wsById.get(a);
      const wb = wsById.get(b);
      const ra = wsLinked.get(a) === null ? 0 : 1; // herdr-managed wins
      const rb = wsLinked.get(b) === null ? 0 : 1;
      if (ra !== rb) return rb - ra;
      if ((wa && wa.pane_count) !== (wb && wb.pane_count)) {
        return (wb ? wb.pane_count : 0) - (wa ? wa.pane_count : 0);
      }
      return (wa ? wa.number : 0) - (wb ? wb.number : 0);
    })[0];
    canonical.set(c, keep);
    for (const id of ids) if (id !== keep) duplicates.add(id);
  }

  return { wsById, wsCheckout, wsLinked, canonical, duplicates };
}

function main() {
  if (HELP) {
    console.log(
      "herdr-organize: consolidate herdr workspaces, relocate misplaced tabs,\n" +
        "  repair hijacked/mis-rooted worktree workspaces, sort pi tabs to the\n" +
        "  front, and rename stale tabs/workspaces.\n\n" +
        "  herdr-organize              apply all passes and close emptied duplicates\n" +
        "  herdr-organize --dry-run    preview only, change nothing\n",
    );
    return;
  }

  let panes;
  let workspaces;
  try {
    panes = (herdrJson("pane", "list").result || {}).panes || [];
    workspaces =
      (herdrJson("workspace", "list").result || {}).workspaces || [];
  } catch (e) {
    console.error(
      "herdr-organize: " +
        String((e && e.message) || e).split("\n")[0] +
        " (is a herdr server running?)",
    );
    process.exit(1);
  }

  // ---- first model pass (before opening any worktrees) ----
  let model = computeModel(panes, workspaces);
  let { wsCheckout } = model;

  // ---- worktree catalog: every linked worktree path herdr knows about ----
  let wtByPath = buildWorktreeCatalog(workspaces, wsCheckout);

  const checkoutValues = new Set();
  for (const ws of workspaces) {
    const c = wsCheckout.get(ws.workspace_id);
    if (c) checkoutValues.add(c);
  }

  // encoded session dir -> checkout path, for pi pane resolution.
  const encodedToPath = new Map();
  for (const p of wtByPath.keys()) encodedToPath.set(encodeCwd(p), p);
  for (const c of checkoutValues) encodedToPath.set(encodeCwd(c), c);

  const gitTopCache = new Map();
  function resolveNonPiCheckout(pane) {
    const cwd = pane.cwd || "";
    if (checkoutValues.has(cwd) || wtByPath.has(cwd)) return cwd;
    if (gitTopCache.has(cwd)) return gitTopCache.get(cwd);
    let res = null;
    try {
      const top = run("git", ["-C", cwd, "rev-parse", "--show-toplevel"]).trim();
      if (top && (checkoutValues.has(top) || wtByPath.has(top))) res = top;
    } catch {
      /* not a repo */
    }
    gitTopCache.set(cwd, res);
    return res;
  }

  // ---- repair workspaces that hijacked a linked worktree's association ----
  // Runs before the relocate pass so everything downstream sees a repaired
  // (linked, correctly-rooted) world.
  let repairRows = [];
  let hijacks = 0;
  {
    const r = repairHijackedWorktrees(
      panes,
      workspaces,
      wtByPath,
      wsCheckout,
      encodedToPath,
      resolveNonPiCheckout,
      DRY_RUN,
    );
    repairRows = r.rows;
    hijacks = r.hijacks;
    if (r.changed) {
      // Re-read state: workspaces were opened/moved into/closed.
      workspaces =
        (herdrJson("workspace", "list").result || {}).workspaces || workspaces;
      try {
        panes = (herdrJson("pane", "list").result || {}).panes || panes;
      } catch { /* keep pre-repair view */ }
      model = computeModel(panes, workspaces);
      ({ wsCheckout } = model);
      wtByPath = buildWorktreeCatalog(workspaces, wsCheckout);
      checkoutValues.clear();
      for (const ws of workspaces) {
        const c = wsCheckout.get(ws.workspace_id);
        if (c) checkoutValues.add(c);
      }
      encodedToPath.clear();
      for (const p of wtByPath.keys()) encodedToPath.set(encodeCwd(p), p);
      for (const c of checkoutValues) encodedToPath.set(encodeCwd(c), c);
      gitTopCache.clear();
    }
  }

  // ---- find linked worktrees that have panes but no open workspace ----
  const toOpen = new Map(); // path -> branch
  for (const pane of panes) {
    let cp = null;
    if (isPi(pane)) cp = encodedToPath.get(sessionDirOf(pane));
    else cp = resolveNonPiCheckout(pane);
    if (!cp) continue;
    const wt = wtByPath.get(cp);
    if (wt && wt.is_linked && !wt.open_ws) {
      toOpen.set(cp, wt.branch || path.basename(cp));
    }
  }

  // ---- open them (one workspace each) ----
  const openErrors = [];
  if (!DRY_RUN) {
    for (const [p, branch] of toOpen) {
      try {
        run(HERDR, ["worktree", "open", "--path", p, "--label", branch]);
      } catch (e) {
        openErrors.push(
          p + ": " + String((e && e.message) || e).split("\n")[0],
        );
      }
    }
    if (toOpen.size > 0) {
      // Re-read workspaces (newly opened sub-workspaces now present) and
      // rebuild the model + lookup tables.
      workspaces =
        (herdrJson("workspace", "list").result || {}).workspaces || [];
      model = computeModel(panes, workspaces);
      ({ wsCheckout } = model);
      checkoutValues.clear();
      for (const ws of workspaces) {
        const c = wsCheckout.get(ws.workspace_id);
        if (c) checkoutValues.add(c);
      }
      encodedToPath.clear();
      for (const p of wtByPath.keys()) encodedToPath.set(encodeCwd(p), p);
      for (const c of checkoutValues) encodedToPath.set(encodeCwd(c), c);
    }
  }

  const { wsById, canonical, duplicates } = model;

  // ---- resolve every pane to a destination and move mismatches ----
  const rows = [];
  let ok = 0;
  let moved = 0;
  let skipped = 0;
  let errors = 0;

  for (const pane of panes) {
    const title = String(pane.terminal_title || pane.pane_id);
    let checkout = null;

    if (isPi(pane)) {
      checkout = encodedToPath.get(sessionDirOf(pane));
      if (!checkout) {
        skipped++;
        rows.push({
          status: "skip",
          pane: pane.pane_id,
          title,
          note: "pi checkout not in any known repo",
        });
        continue;
      }
    } else {
      checkout = resolveNonPiCheckout(pane);
      if (!checkout) {
        skipped++;
        rows.push({
          status: "skip",
          pane: pane.pane_id,
          title,
          note: "not on a known checkout",
        });
        continue;
      }
    }

    const dest = canonical.get(checkout);
    if (!dest) {
      if (toOpen.has(checkout)) {
        if (DRY_RUN) {
          moved++;
          rows.push({
            status: "would-move",
            pane: pane.pane_id,
            title,
            note: `${pane.workspace_id} -> new workspace (open ${checkout})`,
          });
        } else {
          skipped++;
          rows.push({
            status: "skip",
            pane: pane.pane_id,
            title,
            note: "worktree open failed for " + checkout,
          });
        }
      } else {
        skipped++;
        rows.push({
          status: "skip",
          pane: pane.pane_id,
          title,
          note: "no workspace for " + checkout,
        });
      }
      continue;
    }

    if (dest === pane.workspace_id) {
      ok++;
      rows.push({ status: "ok", pane: pane.pane_id, title, note: dest });
      continue;
    }

    const label = isPi(pane) ? labelFor(pane, checkout) : null;
    if (DRY_RUN) {
      moved++;
      rows.push({
        status: "would-move",
        pane: pane.pane_id,
        title,
        note: `${pane.workspace_id} -> ${dest}${label ? "  (" + label + ")" : ""}`,
      });
      continue;
    }

    try {
      const args = [
        "pane", "move", pane.pane_id,
        "--new-tab",
        "--workspace", dest,
        "--focus",
      ];
      if (label) args.push("--label", label);
      run(HERDR, args);
      moved++;
      rows.push({
        status: "moved",
        pane: pane.pane_id,
        title,
        note: `${pane.workspace_id} -> ${dest}${label ? "  (" + label + ")" : ""}`,
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

  // ---- sort + rename pass (on fresh post-relocation state) ----
  let postPanes = panes;
  let postWorkspaces = workspaces;
  let postTabs = [];
  try {
    postPanes = (herdrJson("pane", "list").result || {}).panes || panes;
  } catch { /* keep pre-move view */ }
  try {
    postWorkspaces = (herdrJson("workspace", "list").result || {}).workspaces || workspaces;
  } catch { /* keep */ }
  try {
    postTabs = (herdrJson("tab", "list").result || {}).tabs || [];
  } catch { /* keep */ }
  rows.push(...sortAndRename(postPanes, postWorkspaces, postTabs, wtByPath, DRY_RUN));

  // ---- close emptied duplicates (fail-safe: only zero-pane ones) ----
  const closes = [];
  if (!DRY_RUN && duplicates.size > 0) {
    let live;
    try {
      live =
        (herdrJson("workspace", "list").result || {}).workspaces || [];
    } catch {
      live = null;
    }
    const paneCount = new Map();
    if (live) for (const ws of live) paneCount.set(ws.workspace_id, ws.pane_count || 0);
    for (const id of duplicates) {
      const count = paneCount.has(id) ? paneCount.get(id) : -1;
      if (count === 0) {
        // Hard safety: never close a workspace that still has open linked
        // children (herdr answers workspace_group_close_required) — report it
        // as kept rather than reaching for a wider close.
        const dupWs = wsById.get(id) || {};
        const dupRepo =
          (dupWs.worktree && dupWs.worktree.repo_root) || wsCheckout.get(id);
        if (dupRepo && hasOpenLinkedChildren(dupRepo, id)) {
          closes.push({
            id,
            label: dupWs.label || id,
            err: "workspace_group_close_required (linked child still associated)",
          });
          continue;
        }
        try {
          run(HERDR, ["workspace", "close", id]);
          closes.push({ id, label: (wsById.get(id) || {}).label || id });
        } catch (e) {
          closes.push({
            id,
            label: (wsById.get(id) || {}).label || id,
            err: String((e && e.message) || e).split("\n")[0],
          });
        }
      }
    }
  } else if (duplicates.size > 0) {
    for (const id of duplicates) {
      closes.push({ id, label: (wsById.get(id) || {}).label || id });
    }
  }

  // ---- report ----
  console.log(pad("STATUS", 12) + pad("PANE", 11) + pad("TITLE", 42) + "DETAIL");
  console.log("-".repeat(110));
  for (const r of rows) {
    console.log(
      pad(r.status, 12) +
        pad(r.pane, 11) +
        pad(truncate(r.title, 42), 42) +
        (r.note || ""),
    );
  }
  console.log("-".repeat(110));

  if (repairRows.length > 0) {
    console.log("\nhijacked worktree associations (" + (DRY_RUN ? "plan" : "repair") + "):");
    for (const r of repairRows) {
      console.log(
        "  " + pad(r.status, 21) + pad(r.pane, 9) +
          pad(truncate(r.title, 30), 30) + (r.note || ""),
      );
    }
    if (DRY_RUN) {
      console.log(
        "  (plan only — the relocate/consolidate rows above were computed" +
          " against the still-corrupted state)",
      );
    }
  }

  if (toOpen.size > 0) {
    console.log("\nopen worktree sub-workspace:");
    for (const [p, branch] of toOpen) {
      console.log("  open  " + p + "  (label: " + branch + ")");
    }
    for (const e of openErrors) console.log("  ERROR " + e);
  }

  if (duplicates.size > 0) {
    const verb = DRY_RUN ? "would close" : "closed";
    console.log("\nduplicate workspaces (" + verb + "):");
    for (const c of closes) {
      console.log(
        "  " + (c.err ? "KEPT  " : "close ") + c.id + "  " + c.label +
          (c.err ? "  [" + c.err + "]" : ""),
      );
    }
  }

  console.log(
    "\npanes: " + panes.length +
      "   ok: " + ok +
      "   " + (DRY_RUN ? "would-move" : "moved") + ": " + moved +
      "   skipped: " + skipped +
      "   errors: " + errors +
      "   open: " + toOpen.size +
      "   duplicates: " + duplicates.size +
      "   hijacks: " + hijacks,
  );
  if (DRY_RUN) {
    console.log("(dry run — nothing was changed; rerun without --dry-run to apply)");
  }
}

main();
