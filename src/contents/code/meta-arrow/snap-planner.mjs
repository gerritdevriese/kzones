import { isWidthPreserveDirection, eq, centerX, centerY } from "./geometry.mjs";
import { buildZonePool, findEntryMatchingSource } from "./zone-pool.mjs";
import { axisPreserveFilter, perpendicularPreserveFilter, centerInDirectionFilter } from "./direction-rules.mjs";
import { pickMinCost } from "./cost.mjs";
import { findScreenInDirection } from "./monitor-adjacency.mjs";
import { getMoveMemory, isFullscreenSized } from "./move-memory.mjs";

const OPPOSITE = { up: "down", down: "up", left: "right", right: "left" };

function actionZone(e, screenName) {
  return { type: "zone", layoutIndex: e.sourceLayoutIndex, zoneIndex: e.sourceZoneIndex, padding: e.padding, zone: { x: e.x, y: e.y, w: e.w, h: e.h }, screenName: screenName || "" };
}

function actionFullscreen(screenName) {
  return { type: "fullscreen", screenName: screenName || "" };
}

function actionRestore(prevGeometry) {
  return { type: "restore", prevGeometry: prevGeometry };
}

function actionNoop(reason) {
  return { type: "noop", reason: reason || "" };
}

function actionJump(targetScreenName, nextAction) {
  return { type: "jump", targetScreen: targetScreenName, nextAction };
}

// Best-fit landing zone on a destination monitor.
//
// Cross-monitor moves should preserve the dimension PERPENDICULAR to the
// direction of travel (height for left/right, width for up/down). When the
// source already covers that dimension fully (~100%), fall back to landing
// at fullscreen-sized on the destination so we don't squash the window onto
// a small tile.
//
// When picking a tile, prefer one that's on the *entry edge* of the new
// monitor (e.g. Meta+Right jumping right → land on the LEFT edge of the new
// monitor, the side the window is entering from). This keeps direction of
// travel consistent across the screen boundary.
function landingActionForJump(dstPool, source, dir, destScreenName) {
  if (!source) {
    return actionNoop("no source for jump");
  }
  const widthPreserve = isWidthPreserveDirection(dir);
  const perpDim = widthPreserve ? source.w : source.h;

  let candidates = perpendicularPreserveFilter(dstPool, source, dir);
  if (candidates.length === 0) {
    if (eq(perpDim, 100)) return actionFullscreen(destScreenName);
    candidates = dstPool;
  }
  if (candidates.length === 0) return actionFullscreen(destScreenName);

  const pick = pickEntryEdgeLanding(candidates, source, dir);
  return pick ? actionZone(pick, destScreenName) : actionFullscreen(destScreenName);
}

function pickEntryEdgeLanding(candidates, source, dir) {
  const srcCx = centerX(source);
  const srcCy = centerY(source);
  let best = null;
  let bestEntry = Infinity;
  let bestParallel = Infinity;
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    const cx = centerX(c);
    const cy = centerY(c);
    let entryDist = 0;
    let parallelDist = 0;
    switch (dir) {
      case "right": entryDist = cx;         parallelDist = Math.abs(cy - srcCy); break;
      case "left":  entryDist = 100 - cx;   parallelDist = Math.abs(cy - srcCy); break;
      case "down":  entryDist = cy;         parallelDist = Math.abs(cx - srcCx); break;
      case "up":    entryDist = 100 - cy;   parallelDist = Math.abs(cx - srcCx); break;
    }
    if (
      best === null
      || entryDist < bestEntry - 0.01
      || (Math.abs(entryDist - bestEntry) < 0.01 && parallelDist < bestParallel - 0.01)
      || (
        Math.abs(entryDist - bestEntry) < 0.01
        && Math.abs(parallelDist - bestParallel) < 0.01
        && (c.sourceLayoutIndex < best.sourceLayoutIndex
            || (c.sourceLayoutIndex === best.sourceLayoutIndex && c.sourceZoneIndex < best.sourceZoneIndex))
      )
    ) {
      best = c;
      bestEntry = entryDist;
      bestParallel = parallelDist;
    }
  }
  return best;
}

function planMonitorJump({ source, dir, currentScreen, screens, layouts }) {
  const dstScreen = findScreenInDirection(screens, currentScreen, dir);
  if (!dstScreen) return null;
  const dstName = String(dstScreen.name || "");
  const dstPool = buildZonePool(layouts, dstName);
  const landing = landingActionForJump(dstPool, source, dir, dstName);
  return actionJump(dstName, landing);
}

// Floating / off-grid: no axis-preserve constraint — pick whichever zone in
// the direction of travel sits closest in shape AND position.
function planFloating({ source, dir, pool, currentScreenName, screens, currentScreen, layouts }) {
  const candidates = centerInDirectionFilter(pool, source, dir);
  if (candidates.length > 0) {
    const pick = pickMinCost(candidates, source);
    if (pick) return actionZone(pick, currentScreenName);
  }
  const jump = planMonitorJump({ source, dir, currentScreen, screens, layouts });
  return jump || actionNoop("no candidate, no monitor in direction");
}

// Snapped path. Two filters:
//   - axis preserve  → keep width on vertical moves, keep height on horizontal
//   - centre-in-dir  → candidate's geometric centre lies strictly in `dir`
//   from source's centre.
//
// Vertical strips (h=100 thirds) have no width-matching neighbour above or
// below themselves. For Meta+Up/Down we relax the axis-preserve constraint
// so a tall left-third can land on top-left ¼ instead of bouncing into a
// monitor jump. Horizontal motion stays strict — at the right edge of a
// monitor we *do* want to jump out, not jitter sideways into a slightly
// narrower neighbour.
function planSnapped({ source, dir, pool, currentScreenName, screens, currentScreen, layouts }) {
  const axisPreserved = axisPreserveFilter(pool, source, dir);
  let candidates = centerInDirectionFilter(axisPreserved, source, dir);
  let pick = pickMinCost(candidates, source);
  if (pick) return actionZone(pick, currentScreenName);

  if (dir === "up" || dir === "down") {
    const relaxed = centerInDirectionFilter(pool, source, dir);
    pick = pickMinCost(relaxed, source);
    if (pick) return actionZone(pick, currentScreenName);
  }

  if (dir === "up") return actionFullscreen(currentScreenName);
  return planMonitorJump({ source, dir, currentScreen, screens, layouts }) || actionNoop("no candidate, no monitor");
}

function planFromFullscreen({ source, dir, pool, currentScreenName, currentScreen, screens, layouts }) {
  if (dir === "up") {
    return planMonitorJump({ source, dir, currentScreen, screens, layouts }) || actionNoop("at fullscreen, no monitor above");
  }
  // Down / Left / Right from fullscreen: floating-source rule using
  // full-monitor source. Memory-based undo is handled before reaching here.
  return planFloating({ source, dir, pool, currentScreenName, screens, currentScreen, layouts });
}

// Main entry point. Inputs are pure data; no QML / KWin coupling here.
//
// `client`     — the KWin client (used only to read .zone / .metaMemory state).
// `clientArea` — { x, y, width, height } pixel rect of current monitor.
// `source`     — frameGeometry expressed as monitor %.
// `dir`        — "up" | "down" | "left" | "right".
// `screens`    — list of KWin screens, used for adjacency lookups.
// `currentScreen` — entry from `screens` representing the current monitor.
export function planSnap({ client, source, clientArea, dir, screens, currentScreen, layouts }) {
  if (!source || !clientArea) return actionNoop("no source / clientArea");
  const currentScreenName = currentScreen && currentScreen.name ? String(currentScreen.name) : "";
  const pool = buildZonePool(layouts, currentScreenName);

  // Universal undo: opposite-of-last-move always wins. Caller (executor)
  // is responsible for swapping the memory entry once the restore lands.
  const memory = getMoveMemory(client);
  if (memory && memory.direction && OPPOSITE[memory.direction] === dir && memory.prevGeometry) {
    return actionRestore(memory.prevGeometry);
  }

  if (isFullscreenSized(client, clientArea)) {
    return planFromFullscreen({ source, dir, pool, currentScreenName, currentScreen, screens, layouts });
  }

  const inCycle = findEntryMatchingSource(pool, source);
  const isSnapped = client && client.zone !== undefined && client.zone !== null && client.zone !== -1 && inCycle;

  if (isSnapped) {
    return planSnapped({ source, dir, pool, currentScreenName, currentScreen, screens, layouts });
  }
  return planFloating({ source, dir, pool, currentScreenName, currentScreen, screens, layouts });
}
