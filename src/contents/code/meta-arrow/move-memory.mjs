import { eq } from "./geometry.mjs";

// Universal one-step undo memory for Meta+Arrow moves.
//
// Every Meta+Arrow action records the source frameGeometry plus the direction
// pressed. Pressing the *opposite* direction restores the prior geometry —
// works whether the previous state was a tile, fullscreen, floating, or on a
// different monitor.
//
// `prevGeometry`    is the absolute pixel rect the window had before the move.
// `direction`       is the direction that produced the current state.
// `snappedGeometry` is the absolute rect we set after applying the move; used
//                   to detect when the user has dragged / resized the window
//                   off our last snap so we can invalidate memory.

export function captureMove(client, prevGeometry, direction, snappedGeometry) {
  if (!client) return;
  client.metaMemory = {
    prevGeometry: cloneGeom(prevGeometry),
    direction: direction || null,
    snappedGeometry: cloneGeom(snappedGeometry),
  };
}

export function getMoveMemory(client) {
  return (client && client.metaMemory) ? client.metaMemory : null;
}

export function clearMemory(client) {
  if (!client) return;
  if (client.metaMemory !== undefined) client.metaMemory = null;
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
  const m = client && client.metaMemory;
  if (!m || !m.snappedGeometry) return false;
  const g = client.frameGeometry;
  const s = m.snappedGeometry;
  return Math.abs(g.x - s.x) > 2
      || Math.abs(g.y - s.y) > 2
      || Math.abs(g.width  - s.width)  > 2
      || Math.abs(g.height - s.height) > 2;
}

function cloneGeom(g) {
  if (!g) return null;
  return { x: g.x, y: g.y, width: g.width, height: g.height };
}
