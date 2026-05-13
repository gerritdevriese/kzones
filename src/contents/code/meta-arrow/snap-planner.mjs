import { eq, centerX, centerY, isWidthPreserveDirection } from "./geometry.mjs";
import { buildZonePool, findEntryMatchingSource } from "./zone-pool.mjs";
import { edgeFilter, axisPreserveFilter, directionModifyFilter, perpendicularPreserveFilter, strictlySmallerArea } from "./direction-rules.mjs";
import { adjustmentCost, pickMinCost } from "./cost.mjs";
import { findScreenInDirection } from "./monitor-adjacency.mjs";
import { getPreFullscreen, isFullscreenSized } from "./fullscreen-state.mjs";

const OPPOSITE = { up: "down", down: "up", left: "right", right: "left" };

function actionZone(e, screenName) {
  return { type: "zone", layoutIndex: e.sourceLayoutIndex, zoneIndex: e.sourceZoneIndex, padding: e.padding, zone: { x: e.x, y: e.y, w: e.w, h: e.h }, screenName: screenName || "" };
}

function actionFullscreen(screenName) {
  return { type: "fullscreen", screenName: screenName || "" };
}

function actionRestore(zoneRefObj) {
  return { type: "restore", zoneRef: zoneRefObj };
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
function landingActionForJump(dstPool, source, dir, destScreenName) {
  if (!source) {
    return actionNoop("no source for jump");
  }
  const widthPreserve = isWidthPreserveDirection(dir);
  const perpDim = widthPreserve ? source.w : source.h;

  const candidates = perpendicularPreserveFilter(dstPool, source, dir);
  if (candidates.length === 0) {
    if (eq(perpDim, 100)) return actionFullscreen(destScreenName);
    const fallback = pickMinCost(dstPool, source);
    return fallback ? actionZone(fallback, destScreenName) : actionFullscreen(destScreenName);
  }

  const pick = pickMinCost(candidates, source);
  return pick ? actionZone(pick, destScreenName) : actionFullscreen(destScreenName);
}

function planMonitorJump({ source, dir, currentScreen, screens, layouts }) {
  const dstScreen = findScreenInDirection(screens, currentScreen, dir);
  if (!dstScreen) return null;
  const dstName = String(dstScreen.name || "");
  const dstPool = buildZonePool(layouts, dstName);
  const landing = landingActionForJump(dstPool, source, dir, dstName);
  return actionJump(dstName, landing);
}

// Floating / off-grid: no hard constraints — pick the candidate closest in
// shape and position. Centre metric handles "feels natural" better than
// corner deltas when sizes differ.
function planFloating({ source, dir, pool, currentScreenName, screens, currentScreen, layouts }) {
  const edges = edgeFilter(pool, dir);
  if (edges.length > 0) {
    const pick = pickMinCost(edges, source);
    if (pick) return actionZone(pick, currentScreenName);
  }
  const jump = planMonitorJump({ source, dir, currentScreen, screens, layouts });
  return jump || actionNoop("no candidate, no monitor in direction");
}

function sourceMatchesEntry(zones, source) {
  for (let i = 0; i < zones.length; i++) {
    const c = zones[i];
    if (eq(c.x, source.x) && eq(c.y, source.y) && eq(c.w, source.w) && eq(c.h, source.h)) return true;
  }
  return false;
}

function planSnapped({ source, dir, pool, currentScreenName, screens, currentScreen, layouts }) {
  // axis-preserve + direction-edge defines the natural cycle for the source's
  // width (or height for L/R). Strict-shrink keeps repeated presses moving
  // toward smaller zones; lateral same-area moves are intentionally excluded.
  const edges = edgeFilter(pool, dir);
  const cycleSet = axisPreserveFilter(edges, source, dir);
  const cycleModify = directionModifyFilter(cycleSet, source, dir);
  const sourceInCycle = sourceMatchesEntry(cycleSet, source);

  if (!sourceInCycle) {
    // Source isn't part of the direction-edge cycle yet (e.g. bottom-left ¼
    // moving up). Enter at the least-cost zone that actually changes the
    // direction-of-travel dimension.
    const pick = pickMinCost(cycleModify, source);
    if (pick) return actionZone(pick, currentScreenName);
    if (cycleSet.length > 0) {
      const fallback = pickMinCost(cycleSet, source);
      if (fallback) return actionZone(fallback, currentScreenName);
    }
    if (dir === "up") return actionFullscreen(currentScreenName);
    return planMonitorJump({ source, dir, currentScreen, screens, layouts }) || actionNoop("no candidate, no monitor");
  }

  // Source IS in the cycle.
  const shrinkSet = strictlySmallerArea(cycleModify, source);
  if (shrinkSet.length > 0) {
    const pick = pickMinCost(shrinkSet, source);
    if (pick) return actionZone(pick, currentScreenName);
  }

  if (dir === "up") return actionFullscreen(currentScreenName);
  return planMonitorJump({ source, dir, currentScreen, screens, layouts }) || actionNoop("cycle exhausted, no monitor");
}

// Meta+Down from 100%-coverage without pre-FS memory:
//   1. Prefer bottom-edge zones whose centerX lines up with the source's
//      (within tolerance) and minimize width delta.
//   2. If none align, fall back to top-left-most bottom-edge zone — the
//      sensible "undo fullscreen" landing.
function planFullscreenDown({ source, pool, currentScreenName }) {
  const bottomEdge = edgeFilter(pool, "down");
  if (bottomEdge.length === 0) return actionNoop("no bottom-edge zone");
  const srcCx = centerX(source);
  const centered = bottomEdge.filter(c => eq(centerX(c), srcCx));
  if (centered.length > 0) {
    let best = centered[0];
    let bestDw = Math.abs(best.w - source.w);
    let bestCost = adjustmentCost(best, source);
    for (let i = 1; i < centered.length; i++) {
      const c = centered[i];
      const dw = Math.abs(c.w - source.w);
      const cc = adjustmentCost(c, source);
      if (dw < bestDw || (dw === bestDw && cc < bestCost)) {
        best = c; bestDw = dw; bestCost = cc;
      }
    }
    return actionZone(best, currentScreenName);
  }
  let topLeft = bottomEdge[0];
  for (let i = 1; i < bottomEdge.length; i++) {
    const c = bottomEdge[i];
    if (c.x < topLeft.x || (c.x === topLeft.x && c.y < topLeft.y)) topLeft = c;
  }
  return actionZone(topLeft, currentScreenName);
}

function planFromFullscreen({ client, source, dir, pool, currentScreenName, currentScreen, screens, layouts }) {
  if (dir === "up") {
    return planMonitorJump({ source, dir, currentScreen, screens, layouts }) || actionNoop("at fullscreen, no monitor above");
  }
  if (dir === "down") {
    const preFS = getPreFullscreen(client);
    if (preFS && (!preFS.sourceScreen || preFS.sourceScreen === currentScreenName)) {
      return actionRestore(preFS);
    }
    return planFullscreenDown({ source, pool, currentScreenName });
  }
  // Left / Right from fullscreen-sized: fresh floating-source decision using
  // the full monitor rect; memory is irrelevant here.
  return planFloating({ source, dir, pool, currentScreenName, screens, currentScreen, layouts });
}

// Main entry point. Inputs are pure data; no QML / KWin coupling here.
//
// `client`     — the KWin client (used only to read .zone / .preFS state).
// `clientArea` — { x, y, width, height } pixel rect of current monitor.
// `source`     — frameGeometry expressed as monitor %.
// `dir`        — "up" | "down" | "left" | "right".
// `screens`    — list of KWin screens, used for adjacency lookups.
// `currentScreen` — entry from `screens` representing the current monitor.
export function planSnap({ client, source, clientArea, dir, screens, currentScreen, layouts }) {
  if (!source || !clientArea) return actionNoop("no source / clientArea");
  const currentScreenName = currentScreen && currentScreen.name ? String(currentScreen.name) : "";
  const pool = buildZonePool(layouts, currentScreenName);

  if (isFullscreenSized(client, clientArea)) {
    return planFromFullscreen({ client, source, dir, pool, currentScreenName, currentScreen, screens, layouts });
  }

  const inCycle = findEntryMatchingSource(pool, source);
  const isSnapped = client && client.zone !== undefined && client.zone !== null && client.zone !== -1 && inCycle;

  if (isSnapped) {
    return planSnapped({ source, dir, pool, currentScreenName, currentScreen, screens, layouts });
  }
  return planFloating({ source, dir, pool, currentScreenName, currentScreen, screens, layouts });
}

export const _internals = { OPPOSITE };
