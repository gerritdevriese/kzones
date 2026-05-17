import { eq } from "./geometry.mjs";
import { keyFor, cloneGeom } from "../client-key.mjs";

// Universal one-step undo memory for Meta+Arrow moves.
//
// Memory is stored in a module-level Map keyed via the shared client-key
// helper so the pristine-geometry module and this module agree on identity
// for the same KWin client.
//
// `prevGeometry`    is the absolute pixel rect the window had before the move.
// `direction`       is the direction that produced the current state.
// `snappedGeometry` is the absolute rect we set after applying the move; used
//                   to detect when the user has dragged / resized the window
//                   off our last snap so we can invalidate memory.

const memory = new Map();

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
