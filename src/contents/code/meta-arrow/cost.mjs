import { centerX, centerY } from "./geometry.mjs";

export function adjustmentCost(zone, source) {
  if (!source) return 0;
  const dcx = centerX(zone) - centerX(source);
  const dcy = centerY(zone) - centerY(source);
  const positionCost = Math.sqrt(dcx * dcx + dcy * dcy);
  const sizeCost = Math.abs(zone.w - source.w) + Math.abs(zone.h - source.h);
  return sizeCost + positionCost;
}

function tiebreak(a, b) {
  if (a.sourceLayoutIndex !== b.sourceLayoutIndex) return a.sourceLayoutIndex - b.sourceLayoutIndex;
  if (a.sourceZoneIndex !== b.sourceZoneIndex) return a.sourceZoneIndex - b.sourceZoneIndex;
  return 0;
}

export function pickMinCost(zones, source) {
  if (!zones || zones.length === 0) return null;
  let best = zones[0];
  let bestCost = adjustmentCost(best, source);
  for (let i = 1; i < zones.length; i++) {
    const c = zones[i];
    const cc = adjustmentCost(c, source);
    if (cc < bestCost || (cc === bestCost && tiebreak(c, best) < 0)) {
      best = c;
      bestCost = cc;
    }
  }
  return best;
}
