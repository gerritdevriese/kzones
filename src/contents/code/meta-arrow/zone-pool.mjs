import { eq } from "./geometry.mjs";
import { layoutAppliesToScreen } from "../core.mjs";

// QML coerces JS arrays to QVariantList, breaking Array.isArray.
function isArrayLike(x) {
  return x != null && typeof x !== "string" && typeof x.length === "number";
}

// Builds the deduplicated zone pool for a screen across every layout whose
// `screens` list includes the screen (or has no `screens` filter at all).
//
// Each entry carries source coordinates so the executor can resolve padded
// geometry without changing the active layout.
export function buildZonePool(layouts, screenName) {
  const out = [];
  if (!isArrayLike(layouts)) return out;

  for (let li = 0; li < layouts.length; li++) {
    const layout = layouts[li];
    if (!layout) continue;
    if (!layoutAppliesToScreen(layout, screenName)) continue;
    const zones = layout.zones;
    if (!isArrayLike(zones)) continue;
    const padding = layout.padding || 0;

    for (let zi = 0; zi < zones.length; zi++) {
      const z = zones[zi];
      if (!z) continue;
      const entry = {
        x: +z.x, y: +z.y, w: +z.width, h: +z.height,
        sourceLayoutIndex: li,
        sourceZoneIndex: zi,
        padding,
      };
      if (!isDuplicate(entry, out)) out.push(entry);
    }
  }
  return out;
}

function isDuplicate(entry, list) {
  for (let i = 0; i < list.length; i++) {
    const e = list[i];
    if (eq(e.x, entry.x) && eq(e.y, entry.y) && eq(e.w, entry.w) && eq(e.h, entry.h))
      return true;
  }
  return false;
}

export function findEntryMatchingSource(pool, source) {
  if (!source) return null;
  for (let i = 0; i < pool.length; i++) {
    const e = pool[i];
    if (eq(e.x, source.x) && eq(e.y, source.y) && eq(e.w, source.w) && eq(e.h, source.h))
      return e;
  }
  return null;
}
