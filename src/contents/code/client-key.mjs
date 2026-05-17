// Shared per-client identity + geometry helpers used by every module that
// stores per-window state in a module-level Map.
//
// KWin's Window object can be flaky about retaining arbitrary JS properties
// across signal boundaries, so we own the map externally and key off the
// stable identifier. If a single module duplicated this logic, two modules
// could assign different fallback keys to the same client and silently
// desync — so this file is the only source of truth.

const clientFallback = new WeakMap();
let fallbackSeq = 0;

export function keyFor(client) {
  if (!client) return null;
  if (client.internalId !== undefined && client.internalId !== null) return String(client.internalId);
  if (client.windowId   !== undefined && client.windowId   !== null) return String(client.windowId);
  let k = clientFallback.get(client);
  if (k === undefined) {
    k = "obj:" + (fallbackSeq++) + ":" + Math.random().toString(36).slice(2);
    clientFallback.set(client, k);
  }
  return k;
}

export function cloneGeom(g) {
  if (!g) return null;
  return { x: g.x, y: g.y, width: g.width, height: g.height };
}
