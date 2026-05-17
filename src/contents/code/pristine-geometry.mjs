// Pristine geometry: remembers a window's frameGeometry BEFORE kzones (or
// the user, or the app) flips it into a snapped / fullscreen / maximized
// state, and restores it on the return trip to floating.
//
// Architecture:
//   - One module-level Map<key, rect> holds the pristine rect per window.
//   - One module-level Map<key, state> caches the most recent state derived
//     from the client's KWin properties + geometry-vs-zone match.
//   - State derivation and side-effects (frame setter, unmaximize, logger)
//     are injected by the caller — this module has zero QML / KWin imports
//     so it runs unmodified under `node` for unit tests.
//
// Single chokepoint:
//   `onStateMaybeChanged` is the primary entry. The QML side wires it to
//   KWin's `frameGeometryChanged(oldGeometry)` signal, which fires after any
//   geometry mutation (snap / fullscreen / maximize / drag-end / programmatic
//   write) carrying the pre-mutation rect as a parameter. That single hook
//   covers every path that can move a window between floating and
//   non-floating, so we do NOT need to instrument moveClientToZone /
//   snap-executor / drag-to-top / etc.
//
// Interactive drag has two special rules:
//   - If a snapped/fullscreen window is grabbed, restore pristine
//     immediately (mid-drag) so KWin drags the original-sized window with
//     the cursor (matches Windows/macOS behaviour).
//   - On drag-end:
//       * If the user resized (not moved): clear pristine — they have
//         declared a new "original" size by manual edit.
//       * If a mid-drag restore happened and the drop ended in floating
//         state: clear pristine (consumed; new floating position wins).
//       * If no mid-drag restore happened: route the (preDragRect ->
//         currentState) transition through `onStateMaybeChanged` so the
//         pristine bookkeeping stays consistent.
// The QML side gates the regular `frameGeometryChanged` dispatch with
// `!moving && !resizing` so the mid-drag `applyFrame` we issue here doesn't
// recursively trigger a state transition.

import { keyFor, cloneGeom } from "./client-key.mjs";

export const FLOATING   = "FLOATING";
export const SNAPPED    = "SNAPPED";
export const FULLSCREEN = "FULLSCREEN";

const stateCache  = new Map();
const pristineMap = new Map();
const dragState   = new Map();

let enabled = () => true;

export function setConfigGate(fn) {
  enabled = (typeof fn === "function") ? fn : () => true;
}

export function _resetForTests() {
  enabled = () => true;
  stateCache.clear();
  pristineMap.clear();
  dragState.clear();
}

export function clear(client) {
  const k = keyFor(client);
  if (!k) return;
  pristineMap.delete(k);
}

export function getPristine(client) {
  const k = keyFor(client);
  if (!k) return null;
  return pristineMap.get(k) || null;
}

export function isAtPristine(client, getFrame) {
  const p = getPristine(client);
  if (!p) return false;
  const g = getFrame ? getFrame(client) : null;
  if (!g) return false;
  return Math.abs(g.x - p.x) <= 4
      && Math.abs(g.y - p.y) <= 4
      && Math.abs(g.width  - p.width)  <= 4
      && Math.abs(g.height - p.height) <= 4;
}

export function onStateMaybeChanged(client, oldGeometry, deps) {
  if (!enabled()) return;
  const k = keyFor(client);
  if (!k || !deps || typeof deps.computeState !== "function") return;

  const newState  = deps.computeState(client);
  const prevState = stateCache.get(k) || FLOATING;

  if (prevState === FLOATING && newState !== FLOATING) {
    if (!pristineMap.has(k) && oldGeometry) {
      pristineMap.set(k, cloneGeom(oldGeometry));
      if (deps.log) deps.log("pristine capture: " + JSON.stringify(oldGeometry));
    }
  } else if (prevState !== FLOATING && newState === FLOATING) {
    const p = pristineMap.get(k);
    if (p && typeof deps.applyFrame === "function") {
      deps.applyFrame(client, p);
      pristineMap.delete(k);
      if (deps.log) deps.log("pristine restore: " + JSON.stringify(p));
    }
  }

  stateCache.set(k, newState);
}

export function onInteractiveStart(client, currentRect, deps) {
  if (!enabled()) return;
  const k = keyFor(client);
  if (!k || !deps) return;

  const entry = { preRect: cloneGeom(currentRect), midDragApplied: false };
  const p = pristineMap.get(k);
  const state = (typeof deps.computeState === "function") ? deps.computeState(client) : FLOATING;
  if (p && state !== FLOATING && typeof deps.applyFrame === "function") {
    deps.applyFrame(client, p);
    entry.midDragApplied = true;
    if (deps.log) deps.log("pristine mid-drag restore: " + JSON.stringify(p));
  }
  dragState.set(k, entry);
}

export function onInteractiveEnd(client, isResizing, deps) {
  const k = keyFor(client);
  if (!k) return;
  const entry = dragState.get(k);
  dragState.delete(k);

  if (!enabled()) return;
  if (!deps || typeof deps.computeState !== "function") return;

  if (isResizing) {
    pristineMap.delete(k);
    stateCache.set(k, deps.computeState(client));
    if (deps.log) deps.log("pristine cleared (manual resize)");
    return;
  }

  if (entry && entry.midDragApplied) {
    const finalState = deps.computeState(client);
    if (finalState === FLOATING) {
      pristineMap.delete(k);
      if (deps.log) deps.log("pristine cleared (mid-drag drop to floating)");
    }
    stateCache.set(k, finalState);
    return;
  }

  if (entry) {
    onStateMaybeChanged(client, entry.preRect, deps);
  }
}
