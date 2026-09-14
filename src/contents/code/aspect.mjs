// Aspect ratio conditions for layouts.
//
// A layout can set "aspectRatio" to limit itself to screens with that shape.
// The value is a ratio ("16:9", "16/9", "16x9" or a number like 1.778), an
// array of ratios, or a comparison (">16:9" for anything wider, "<=4:3" for
// anything at most that wide). Layouts without the key show up everywhere.
//
// "aspectRatioTolerance" is how far a screen may be off the ratio and still
// count as a match, as a fraction of the ratio itself. The default of 0.05
// keeps the usual 21:9 panels (2.37 and 2.39) matching "21:9" while staying
// well clear of 16:9.

export const DEFAULT_TOLERANCE = 0.05;

// Returns the ratio as width / height, or 0 when nothing valid is configured.
export function parseAspectRatio(value) {
  if (value === undefined || value === null || value === false || value === "") return 0;

  if (typeof value === "number") return value > 0 ? value : 0;

  const text = value.toString().trim();
  const parts = text.split(/[:\/x]/);

  if (parts.length === 2) {
    const width = parseFloat(parts[0]);
    const height = parseFloat(parts[1]);
    return width > 0 && height > 0 ? width / height : 0;
  }

  const ratio = parseFloat(text);
  return ratio > 0 ? ratio : 0;
}

// Splits an optional comparison operator off the ratio. Returns null when the
// value does not describe a usable ratio.
export function parseCondition(value) {
  if (value === undefined || value === null || value === false || value === "") return null;

  if (typeof value === "number") return value > 0 ? { op: "=", ratio: value } : null;

  const text = value.toString().trim();
  const match = text.match(/^(>=|<=|>|<|=)?\s*(.+)$/);
  if (!match) return null;

  const ratio = parseAspectRatio(match[2]);
  if (!(ratio > 0)) return null;

  return { op: match[1] || "=", ratio: ratio };
}

export function matchesCondition(screenRatio, condition, tolerance) {
  if (!condition || !(screenRatio > 0)) return false;

  const margin = condition.ratio * (typeof tolerance === "number" && tolerance >= 0 ? tolerance : DEFAULT_TOLERANCE);

  switch (condition.op) {
    case ">":
      return screenRatio > condition.ratio + margin;
    case ">=":
      return screenRatio >= condition.ratio - margin;
    case "<":
      return screenRatio < condition.ratio - margin;
    case "<=":
      return screenRatio <= condition.ratio + margin;
    default:
      return Math.abs(screenRatio - condition.ratio) <= margin;
  }
}

// A layout without a usable "aspectRatio" is available on every screen.
export function layoutMatchesScreen(layout, width, height) {
  if (!layout) return false;
  if (!(width > 0) || !(height > 0)) return true;

  const value = layout.aspectRatio;
  if (value === undefined || value === null || value === false || value === "") return true;

  const values = Array.isArray(value) ? value : [value];
  const screenRatio = width / height;
  let usable = false;

  for (let i = 0; i < values.length; i++) {
    const condition = parseCondition(values[i]);
    if (!condition) continue;
    usable = true;
    if (matchesCondition(screenRatio, condition, layout.aspectRatioTolerance)) return true;
  }

  // an unreadable aspect ratio should not make the layout disappear
  return !usable;
}

// Layouts available on this screen, as { index, layout } so the original index
// stays usable for shortcuts and for the zone overlay. Falls back to every
// layout when nothing matches, to never leave the user without a layout.
export function visibleLayouts(layouts, width, height) {
  const all = layouts || [];
  const visible = [];

  for (let i = 0; i < all.length; i++) {
    if (layoutMatchesScreen(all[i], width, height)) visible.push({ index: i, layout: all[i] });
  }

  if (visible.length > 0) return visible;

  const fallback = [];
  for (let i = 0; i < all.length; i++) fallback.push({ index: i, layout: all[i] });
  return fallback;
}

// Next layout index in cycling order, skipping the ones hidden on this screen.
export function nextVisibleLayout(layouts, current, step, width, height) {
  const visible = visibleLayouts(layouts, width, height);
  if (visible.length === 0) return current;

  const indexes = visible.map((entry) => entry.index);
  const position = indexes.indexOf(current);
  if (position === -1) return step < 0 ? indexes[indexes.length - 1] : indexes[0];

  return indexes[(position + step + indexes.length) % indexes.length];
}
