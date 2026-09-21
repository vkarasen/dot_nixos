// herdr-tab-move — move a herdr tab to a position via the socket API.
//
// `herdr tab.move` has no CLI wrapper, so this speaks newline-delimited JSON
// over the herdr socket. Usage: herdr-tab-move <tab_id> <insert_index>
// Exits 0 only after a matching, error-free response; non-zero otherwise.
// Reordering is cosmetic; callers treat failure as non-fatal.
"use strict";

const net = require("node:net");

const tabId = process.argv[2];
const insertIndex = Number(process.argv[3]);
if (!tabId || !Number.isInteger(insertIndex) || insertIndex < 0) {
  console.error("usage: herdr-tab-move <tab_id> <insert_index>");
  process.exit(2);
}

const socketPath =
  process.env.HERDR_SOCKET_PATH ||
  `${process.env.HOME ?? ""}/.config/herdr/herdr.sock`;

const id = `pi-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
let timer = null;
let settled = false;

function finish(code) {
  if (settled) return;
  settled = true;
  if (timer) clearTimeout(timer);
  sock.destroy();
  process.exit(code);
}

const sock = net.createConnection(socketPath);
timer = setTimeout(() => finish(1), 3000);

sock.on("connect", () => {
  sock.write(
    JSON.stringify({
      id,
      method: "tab.move",
      params: { tab_id: tabId, insert_index: insertIndex },
    }) + "\n",
  );
});

let buf = "";
sock.on("data", (chunk) => {
  buf += chunk.toString();
  const nl = buf.indexOf("\n");
  if (nl === -1) return;
  let resp;
  try {
    resp = JSON.parse(buf.slice(0, nl));
  } catch {
    finish(1);
    return;
  }
  if (resp.id !== id || resp.error) {
    finish(1);
    return;
  }
  finish(0);
});

sock.on("error", () => finish(1));
sock.on("close", () => finish(1));
