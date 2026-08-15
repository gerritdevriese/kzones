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

/* Criteria accept a single string or a list of them, and each may use `*` as a
 * wildcard: "DP-*" matches DP-1 and DP-4, "1920x*" any 1920-wide mode. */
function toPatternList(value) {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.filter((entry) => typeof entry === "string");
  return [];
}

export function globToRegExp(pattern) {
  // Escape everything with meaning in a regexp, then re-expand `*` alone, so a
  // pattern like "DP-1.2" cannot match "DP-192".
  const escaped = String(pattern).replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  return new RegExp("^" + escaped + "$", "i");
}

export function matchesAny(value, candidate) {
  const patterns = toPatternList(value);
  if (!patterns.length) return true;   // criterion absent: matches anything
  return patterns.some((pattern) => globToRegExp(pattern).test(candidate));
}

/* What a layout's `match` is tested against. Resolution and orientation come from
 * the output's own geometry rather than the client area, which excludes panels —
 * and KWin reports that geometry already rotated, so a pivoted 1920x1080 is
 * "1080x1920" and counts as vertical. */
export function screenInfo(screen, fallbackArea) {
  const geometry = (screen && screen.geometry) || fallbackArea || {};
  const width = Math.round(geometry.width || 0);
  const height = Math.round(geometry.height || 0);

  return {
    name: (screen && screen.name) || "",
    width: width,
    height: height,
    resolution: width && height ? `${width}x${height}` : "",
    orientation: height > width ? "vertical" : "horizontal"
  };
}

/* Every criterion present must hold; an absent one matches anything, so a layout
 * without `match` is available everywhere. */
export function layoutMatches(layout, screen) {
  const match = (layout && layout.match) || {};
  // `screens` was the original name for this key.
  const display = match.display !== undefined ? match.display : match.screens;

  if (!matchesAny(display, screen.name)) return false;
  if (!matchesAny(match.resolution, screen.resolution)) return false;
  if (match.orientation && match.orientation !== "any" && match.orientation !== screen.orientation) return false;

  return true;
}
