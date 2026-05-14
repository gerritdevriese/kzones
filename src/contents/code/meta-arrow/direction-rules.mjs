import { eq, touchesEdge, isWidthPreserveDirection, TOL, centerX, centerY } from "./geometry.mjs";

export function edgeFilter(pool, dir) {
  const out = [];
  for (let i = 0; i < pool.length; i++) {
    if (touchesEdge(pool[i], dir)) out.push(pool[i]);
  }
  return out;
}

export function axisPreserveFilter(pool, source, dir) {
  if (!source) return pool.slice();
  const widthPreserve = isWidthPreserveDirection(dir);
  const out = [];
  for (let i = 0; i < pool.length; i++) {
    const c = pool[i];
    if (widthPreserve ? eq(c.w, source.w) : eq(c.h, source.h)) out.push(c);
  }
  return out;
}

export function directionModifyFilter(pool, source, dir) {
  if (!source) return pool.slice();
  const widthPreserve = isWidthPreserveDirection(dir);
  const out = [];
  for (let i = 0; i < pool.length; i++) {
    const c = pool[i];
    // Vertical motion modifies height; horizontal modifies width.
    if (widthPreserve ? !eq(c.h, source.h) : !eq(c.w, source.w)) out.push(c);
  }
  return out;
}

export function perpendicularPreserveFilter(pool, source, dir) {
  return axisPreserveFilter(pool, source, dir);
}

// Candidate's geometric centre must lie strictly in `dir` of source's centre.
// This replaces the old edge-only filter so e.g. middle-third counts as a
// "to-the-left-of-right-third" candidate even though it doesn't touch the
// screen edge.
export function centerInDirectionFilter(pool, source, dir) {
  if (!source) return pool.slice();
  const sx = centerX(source);
  const sy = centerY(source);
  const out = [];
  for (let i = 0; i < pool.length; i++) {
    const c = pool[i];
    const cx = centerX(c);
    const cy = centerY(c);
    let inDir = false;
    switch (dir) {
      case "left":  inDir = cx + TOL < sx; break;
      case "right": inDir = cx - TOL > sx; break;
      case "up":    inDir = cy + TOL < sy; break;
      case "down":  inDir = cy - TOL > sy; break;
    }
    if (inDir) out.push(c);
  }
  return out;
}
