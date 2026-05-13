import { applyPadding, fullScreenRect } from "./geometry.mjs";
import { enterFullscreen, clearMemory } from "./fullscreen-state.mjs";

// Walks an action (possibly a nested jump) and applies it to the client.
// `deps` provides everything QML/KWin-coupled so this module stays pure JS.
//
// deps:
//   getClientAreaForScreen(screenName) -> { x, y, width, height } | null
//   getLayoutPadding(layoutIndex) -> number
//   setMaximize(client, h, v)
//   setFrameGeometry(client, rect)
//   saveClientProperties(client, layoutIndex, zoneIndex)
//   log(msg)
export function executeSnap(action, client, deps) {
  if (!action || !client) return;
  if (action.type === "noop") {
    if (deps.log) deps.log("snap noop: " + (action.reason || ""));
    return;
  }
  if (action.type === "zone") return applyZone(action, client, deps);
  if (action.type === "fullscreen") return applyFullscreen(action, client, deps, true);
  if (action.type === "restore") return applyRestore(action, client, deps);
  if (action.type === "jump") return applyJump(action, client, deps);
}

function applyZone(action, client, deps) {
  const ca = deps.getClientAreaForScreen(action.screenName);
  if (!ca) {
    if (deps.log) deps.log("snap zone: missing client area for " + action.screenName);
    return;
  }
  const padding = (action.padding != null) ? action.padding : deps.getLayoutPadding(action.layoutIndex);
  const rect = applyPadding(action.zone, padding, ca);
  deps.setMaximize(client, false, false);
  deps.setFrameGeometry(client, rect);
  deps.saveClientProperties(client, action.layoutIndex, action.zoneIndex);
  clearMemory(client);
}

function applyFullscreen(action, client, deps, rememberFromCurrent) {
  const ca = deps.getClientAreaForScreen(action.screenName);
  if (!ca) return;
  const rect = fullScreenRect(ca);

  // Capture the source zone *before* we replace geometry so meta+down can
  // bring the window back to where the user came from.
  let preZone = null;
  if (rememberFromCurrent && client.zone !== undefined && client.zone !== null && client.zone !== -1 && deps.getZoneRef) {
    preZone = deps.getZoneRef(client.layout, client.zone);
  }

  deps.setMaximize(client, false, false);
  deps.setFrameGeometry(client, rect);
  deps.saveClientProperties(client, -1, -1);

  enterFullscreen(client, preZone, "up", action.screenName);
}

function applyRestore(action, client, deps) {
  const ref = action.zoneRef;
  if (!ref) {
    clearMemory(client);
    return;
  }
  const ca = deps.getClientAreaForScreen(ref.sourceScreen || "");
  if (!ca) {
    clearMemory(client);
    return;
  }
  const padding = (ref.padding != null) ? ref.padding : deps.getLayoutPadding(ref.sourceLayoutIndex);
  const rect = applyPadding({ x: ref.x, y: ref.y, w: ref.w, h: ref.h }, padding, ca);
  deps.setMaximize(client, false, false);
  deps.setFrameGeometry(client, rect);
  deps.saveClientProperties(client, ref.sourceLayoutIndex, ref.sourceZoneIndex);
  clearMemory(client);
}

function applyJump(action, client, deps) {
  // The destination screen is identified entirely by the geometry we set on
  // the client; KWin will move the window onto whichever screen owns that
  // rect. We don't need a separate "sendToScreen" call.
  const nextAct = action.nextAction;
  if (!nextAct) return;
  if (nextAct.type === "zone") {
    applyZone(nextAct, client, deps);
    return;
  }
  if (nextAct.type === "fullscreen") {
    applyFullscreen(nextAct, client, deps, false);
    return;
  }
}
