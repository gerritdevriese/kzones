export const TOL = 1.0;

export function eq(a, b) {
  return Math.abs(a - b) < TOL;
}

export function area(z) {
  return z.w * z.h;
}

export function centerX(z) {
  return z.x + z.w / 2;
}

export function centerY(z) {
  return z.y + z.h / 2;
}

export function touchesEdge(z, dir) {
  switch (dir) {
    case "up":    return Math.abs(z.y) < TOL;
    case "down":  return Math.abs(z.y + z.h - 100) < TOL;
    case "left":  return Math.abs(z.x) < TOL;
    case "right": return Math.abs(z.x + z.w - 100) < TOL;
  }
  return false;
}

export function isWidthPreserveDirection(dir) {
  return dir === "up" || dir === "down";
}

export function rectsApproxEqual(a, b) {
  return eq(a.x, b.x) && eq(a.y, b.y) && eq(a.w, b.w) && eq(a.h, b.h);
}

export function clientToSourcePct(client, clientArea) {
  if (!client || !clientArea || !clientArea.width || !clientArea.height) return null;
  const g = client.frameGeometry;
  return {
    x: (g.x - clientArea.x) / clientArea.width * 100,
    y: (g.y - clientArea.y) / clientArea.height * 100,
    w: g.width / clientArea.width * 100,
    h: g.height / clientArea.height * 100,
  };
}

// Replicates matchZone() padding formula in main.qml: zones are inset by `padding`
// on top/left, and adjacent zones leave a `padding` gap between them.
export function applyPadding(zone, padding, clientArea) {
  const p = padding || 0;
  const x = ((zone.x / 100) * (clientArea.width  - p)) + p + clientArea.x;
  const y = ((zone.y / 100) * (clientArea.height - p)) + p + clientArea.y;
  const w = ((zone.w  / 100) * (clientArea.width  - p)) - p;
  const h = ((zone.h / 100) * (clientArea.height - p)) - p;
  return {
    x: Math.round(x),
    y: Math.round(y),
    width: Math.round(w),
    height: Math.round(h),
  };
}

export function fullScreenRect(clientArea) {
  return {
    x: Math.round(clientArea.x),
    y: Math.round(clientArea.y),
    width: Math.round(clientArea.width),
    height: Math.round(clientArea.height),
  };
}

export function isFullscreenSized(client, clientArea) {
  if (!client || !clientArea) return false;
  const src = clientToSourcePct(client, clientArea);
  if (!src) return false;
  return eq(src.x, 0) && eq(src.y, 0) && eq(src.w, 100) && eq(src.h, 100);
}
