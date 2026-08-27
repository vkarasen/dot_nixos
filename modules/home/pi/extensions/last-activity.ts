/**
 * Last-activity footer status extension.
 *
 * Shows a single "last <day> <month> <HH:MM>" chip in the pi footer via
 * `setStatus`, so switching back to an idle pane shows when this session was
 * last active. Absolute time (day + month, plus year when it differs from the
 * current year) because sessions can sit untouched for weeks.
 *
 * - agent_settled: refresh to the current wall-clock time — the "final agent
 *   response just completed" signal.
 * - session_start: restore from the session branch's entry timestamps, so the
 *   value is correct across /resume, /new, and restarts instead of resetting.
 *
 * The chip is a single slot in the existing footer status row (next to MCP /
 * LSP statuses); no footer replacement or extra line.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

function formatLastActivity(ts: number): string {
  const d = new Date(ts);
  const now = new Date();
  const day = String(d.getDate()).padStart(2, "0");
  const month = MONTHS[d.getMonth()];
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const date =
    d.getFullYear() === now.getFullYear()
      ? `${day} ${month}`
      : `${day} ${month} ${d.getFullYear()}`;
  return `last ${date} ${hh}:${mm}`;
}

// Highest entry timestamp on the active branch (ISO strings on every entry).
function lastActivityTs(ctx: any): number | undefined {
  try {
    const entries = ctx?.sessionManager?.getBranch?.() ?? [];
    let max = 0;
    for (const e of entries) {
      if (!e?.timestamp) continue;
      const t = new Date(e.timestamp).getTime();
      if (Number.isFinite(t) && t > max) max = t;
    }
    return max > 0 ? max : undefined;
  } catch {
    return undefined;
  }
}

export default function (pi: ExtensionAPI) {
  const set = (ctx: any, ts?: number) => {
    if (ctx?.mode !== "tui") return;
    const text = ts ? formatLastActivity(ts) : undefined;
    ctx.ui.setStatus(
      "last-activity",
      text ? ctx.ui.theme.fg("dim", text) : undefined,
    );
  };

  pi.on("session_start", (_event, ctx) => set(ctx, lastActivityTs(ctx)));
  pi.on("agent_settled", (_event, ctx) => set(ctx, Date.now()));
}
