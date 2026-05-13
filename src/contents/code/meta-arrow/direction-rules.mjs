import { eq, touchesEdge, isWidthPreserveDirection } from "./geometry.mjs";

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

export function strictlySmallerArea(pool, source) {
  if (!source) return pool.slice();
  const out = [];
  const srcArea = source.w * source.h;
  for (let i = 0; i < pool.length; i++) {
    const c = pool[i];
    if (c.w * c.h + 0.0001 < srcArea) out.push(c);
  }
  return out;
}
