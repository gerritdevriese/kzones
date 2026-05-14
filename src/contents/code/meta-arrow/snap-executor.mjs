import { applyPadding, fullScreenRect } from "./geometry.mjs";
import { captureMove, clearMemory } from "./move-memory.mjs";

// Walks an action (possibly a nested jump) and applies it to the client.
// Records undo memory after every real move so the next opposite-direction
// press can step back exactly to where the user came from.
//
// `direction` is the Meta+Arrow direction the user pressed; used to populate
// memory.
//
// deps:
//   getClientAreaForScreen(screenName) -> { x, y, width, height } | null
//   getLayoutPadding(layoutIndex) -> number
//   setMaximize(client, h, v)
//   setFrameGeometry(client, rect)
//   saveClientProperties(client, layoutIndex, zoneIndex)
//   log(msg)
export function executeSnap(action, client, deps, direction) {
  if (!action || !client) return;
  if (action.type === "noop") {
    if (deps.log) deps.log("snap noop: " + (action.reason || ""));
    return;
  }

  const prevGeom = cloneGeom(client.frameGeometry);

  if (action.type === "restore") {
    deps.setMaximize(client, false, false);
    deps.setFrameGeometry(client, action.prevGeometry);
    captureMove(client, prevGeom, direction, action.prevGeometry);
    // After restore, the zone/layout properties are likely stale (we don't
    // know which tile this geometry corresponds to). Mark as floating; if
    // user lands on a real tile next, the snap action will reset zone/layout.
    deps.saveClientProperties(client, -1, -1);
    return;
  }

  if (action.type === "zone") {
    applyZone(action, client, deps);
  } else if (action.type === "fullscreen") {
    applyFullscreen(action, client, deps);
  } else if (action.type === "jump") {
    applyJump(action, client, deps);
  } else {
    return;
  }

  const newGeom = cloneGeom(client.frameGeometry);
  captureMove(client, prevGeom, direction, newGeom);
}

function applyZone(action, client, deps) {
  const ca = deps.getClientAreaForScreen(action.screenName);
  if (!ca) {
    if (deps.log) deps.log("snap zone: missing client area for " + action.screenName);
    return;
  }
  const padding = (action.padding != null) ? action.padding : deps.getLayoutPadding(action.layoutIndex);
  const rect = applyPadding(action.zone, padding, ca);
  // Unmaximize first so KWin restores the pre-max frameGeometry, then
  // capture that as oldGeometry BEFORE we overwrite with the zone rect.
  // Without this order, a window maximized via title-bar double-click + then
  // snapped via Meta+Arrow would store the snapped rect as oldGeometry and
  // a future drag would never restore the pre-max size.
  deps.setMaximize(client, false, false);
  deps.saveClientProperties(client, action.layoutIndex, action.zoneIndex);
  deps.setFrameGeometry(client, rect);
}

function applyFullscreen(action, client, deps) {
  const ca = deps.getClientAreaForScreen(action.screenName);
  if (!ca) return;
  const fsPad = deps.getFullscreenPadding ? (deps.getFullscreenPadding() || 0) : 0;
  deps.setMaximize(client, false, false);
  deps.saveClientProperties(client, -1, -2);
  if (fsPad === 0) {
    // Native maximize acts on whichever screen the window currently
    // occupies. For a cross-monitor jump the window hasn't moved yet, so
    // relocate the frame onto the target screen before maximizing.
    deps.setFrameGeometry(client, { x: ca.x, y: ca.y, width: ca.width, height: ca.height });
    deps.setMaximize(client, true, true);
  } else {
    const padded = applyPadding({ x: 0, y: 0, w: 100, h: 100 }, fsPad, ca);
    deps.setFrameGeometry(client, padded);
  }
}

function applyJump(action, client, deps) {
  // The destination screen is identified entirely by the geometry we set on
  // the client; KWin moves the window onto whichever screen owns that rect.
  const nextAct = action.nextAction;
  if (!nextAct) return;
  if (nextAct.type === "zone") {
    applyZone(nextAct, client, deps);
    return;
  }
  if (nextAct.type === "fullscreen") {
    applyFullscreen(nextAct, client, deps);
    return;
  }
}

function cloneGeom(g) {
  if (!g) return null;
  return { x: g.x, y: g.y, width: g.width, height: g.height };
}
