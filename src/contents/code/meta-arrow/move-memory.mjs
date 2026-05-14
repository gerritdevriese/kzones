import { eq } from "./geometry.mjs";

// Universal one-step undo memory for Meta+Arrow moves.
//
// Memory is stored in a module-level Map keyed by client.internalId (falling
// back to client itself if internalId is missing). KWin's Window object can
// be flaky about retaining arbitrary JS properties across signal boundaries,
// so we keep ownership of the map inside this module instead of attaching to
// the client.
//
// `prevGeometry`    is the absolute pixel rect the window had before the move.
// `direction`       is the direction that produced the current state.
// `snappedGeometry` is the absolute rect we set after applying the move; used
//                   to detect when the user has dragged / resized the window
//                   off our last snap so we can invalidate memory.

const memory = new Map();
const clientFallback = new WeakMap();

function keyFor(client) {
  if (!client) return null;
  if (client.internalId !== undefined && client.internalId !== null) return String(client.internalId);
  if (client.windowId  !== undefined && client.windowId  !== null) return String(client.windowId);
  let k = clientFallback.get(client);
  if (k === undefined) {
    k = "obj:" + memory.size + ":" + Math.random().toString(36).slice(2);
    clientFallback.set(client, k);
  }
  return k;
}

export function captureMove(client, prevGeometry, direction, snappedGeometry) {
  const key = keyFor(client);
  if (!key) return;
  memory.set(key, {
    prevGeometry: cloneGeom(prevGeometry),
    direction: direction || null,
    snappedGeometry: cloneGeom(snappedGeometry),
  });
}

export function getMoveMemory(client) {
  const key = keyFor(client);
  if (!key) return null;
  return memory.get(key) || null;
}

export function clearMemory(client) {
  const key = keyFor(client);
  if (!key) return;
  memory.delete(key);
}

export function isFullscreenSized(client, clientArea) {
  if (!client || !clientArea || !clientArea.width || !clientArea.height) return false;
  const g = client.frameGeometry;
  const xPct = (g.x - clientArea.x) / clientArea.width * 100;
  const yPct = (g.y - clientArea.y) / clientArea.height * 100;
  const wPct = g.width / clientArea.width * 100;
  const hPct = g.height / clientArea.height * 100;
  return eq(xPct, 0) && eq(yPct, 0) && eq(wPct, 100) && eq(hPct, 100);
}

export function memoryDriftedFromSnap(client) {
  const m = getMoveMemory(client);
  if (!m || !m.snappedGeometry) return false;
  const g = client.frameGeometry;
  const s = m.snappedGeometry;
  return Math.abs(g.x - s.x) > 4
      || Math.abs(g.y - s.y) > 4
      || Math.abs(g.width  - s.width)  > 4
      || Math.abs(g.height - s.height) > 4;
}

function cloneGeom(g) {
  if (!g) return null;
  return { x: g.x, y: g.y, width: g.width, height: g.height };
}
