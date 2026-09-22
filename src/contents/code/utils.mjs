import { Workspace, config, QML } from "./core.mjs";

export function log(message, level = "info") {
  if (!config.enableDebugLogging) return;
  console.log(`[${level}] KZones: ${message}`);
}

export function osd(text, icon = "preferences-desktop-virtual") {
  if (!config.showOsdMessages) return;
  QML.dbusCall.exec("org.kde.plasmashell", "/org/kde/osdService", "showText", [icon, text]);
}

export function isPointInside(x, y, geometry) {
  return x >= geometry.x && x <= geometry.x + geometry.width && y >= geometry.y && y <= geometry.y + geometry.height;
}

export function isHovering(item) {
  const itemGlobal = item.mapToGlobal(Qt.point(0, 0));
  return isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, {
    x: itemGlobal.x,
    y: itemGlobal.y,
    width: item.width * item.scale,
    height: item.height * item.scale,
  });
}

export function overlapArea(a, b) {
  const x1 = Math.max(a.x, b.x);
  const y1 = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.width, b.x + b.width);
  const y2 = Math.min(a.y + a.height, b.y + b.height);
  if (x2 <= x1 || y2 <= y1) return 0;
  return (x2 - x1) * (y2 - y1);
}

// The zone a window belongs to is the one it overlaps more than any other, however
// small that overlap is: a free-floating window covering a tenth of a zone is still
// in that zone, and deciding this per window rather than per zone is what keeps it
// reachable next to a bigger neighbour. Ties go to the lowest zone index, so a
// window spread evenly over two zones always resolves the same way. Returns -1 when
// the window overlaps no zone at all.
export function bestOverlappingZone(geometry, zoneGeometries) {
  let best = -1;
  let bestArea = 0;
  for (let i = 0; i < zoneGeometries.length; i++) {
    if (!zoneGeometries[i]) continue;
    const area = overlapArea(geometry, zoneGeometries[i]);
    if (area > bestArea) {
      bestArea = area;
      best = i;
    }
  }
  return best;
}

// A key that identifies a window the same way on every invocation, so a cycle
// order built from it cannot be reshuffled while windows are raised and lowered.
// internalId is a stable per-window UUID and is what KWin 6 always provides; seq
// is a last-resort fallback for builds that don't expose it, and is only as stable
// as the caller's enumeration order.
export function windowKey(client, seq) {
  const id = client.internalId;
  if (id !== undefined && id !== null) {
    const key = String(id);
    if (key.length > 0 && key !== "undefined") return "id:" + key;
  }
  // Zero-padded so it compares in numeric order as a string.
  return "seq:" + ("0000" + seq).slice(-5);
}

// Picks which window to activate among the windows belonging to a zone.
// candidates is a list of { client, key }, stackingOrder runs bottom to top.
export function pickWindowInZone(candidates, stackingOrder, activeWindow) {
  if (candidates.length === 0) return null;

  // The cycle order must not come from the stacking order: activating a window
  // raises it, which would leave the window we just left permanently next in line,
  // ping-ponging between two windows instead of reaching the rest.
  const inZone = candidates.slice().sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));

  // Pressing the same zone again cycles through the windows stacked in it.
  for (let i = 0; i < inZone.length; i++) {
    if (inZone[i].client === activeWindow) return inZone[(i + 1) % inZone.length].client;
  }

  // Entering the zone from outside lands on the window last used there, which is
  // whichever of them sits highest in the stacking order.
  let topmost = inZone[0];
  for (let i = 0; i < inZone.length; i++) {
    if (stackingOrder.indexOf(inZone[i].client) > stackingOrder.indexOf(topmost.client)) topmost = inZone[i];
  }
  return topmost.client;
}
