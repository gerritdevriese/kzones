export let KWin = null;
export let Workspace = null;
export let QML = {};
export let config = {};

// Native-JS reference to parsed layouts. Avoids round-tripping through
// `config.layouts`, which QML coerces to QVariantList and loses Array identity.
let _layoutsRaw = [];

export function init(kwin, workspace) {
  console.log("KZones: Loading APIs...");
  KWin = kwin || null;
  Workspace = workspace || null;
}

export function getScreenId(screen) {
  return screen && screen.name ? String(screen.name) : "";
}

// QML wraps JS arrays as QVariantList across the property-var boundary,
// which breaks `Array.isArray`.
function isArrayLike(x) {
  return x != null && typeof x !== "string" && typeof x.length === "number";
}

// Missing/empty `screens` means: apply to every monitor (back-compat).
export function layoutAppliesToScreen(layout, screenId) {
  if (!layout) return true;
  const s = layout.screens;
  if (!isArrayLike(s) || s.length === 0) return true;
  for (let i = 0; i < s.length; i++) {
    if (String(s[i]) === screenId) return true;
  }
  return false;
}

// Returns [{ layout, index }, ...] visible on `screenId`. `index` is the
// position in the unfiltered layouts array so callers can keep referring to
// layouts by their original index.
export function getLayoutsForScreen(screenId) {
  const out = [];
  const layouts = _layoutsRaw;
  if (!isArrayLike(layouts)) return out;
  for (let i = 0; i < layouts.length; i++) {
    if (layoutAppliesToScreen(layouts[i], screenId))
      out.push({ layout: layouts[i], index: i });
  }
  return out;
}

// Enumerate attached monitors. Surfaces connector names users need for the
// per-layout `screens` field; KWin scripting can't auto-populate the KCM.
export function getDetectedScreens() {
  if (!Workspace) return [];
  let screens = [];
  try {
    if (Array.isArray(Workspace.screens)) {
      screens = Workspace.screens;
    } else if (Workspace.screens && typeof Workspace.screens.length === "number") {
      for (let i = 0; i < Workspace.screens.length; i++)
        screens.push(Workspace.screens[i]);
    } else if (typeof Workspace.numScreens === "number" && typeof Workspace.screenAt === "function") {
      for (let i = 0; i < Workspace.numScreens; i++)
        screens.push(Workspace.screenAt(i));
    }
  } catch (e) {
    console.error("KZones: getDetectedScreens enumeration failed:", e);
    return [];
  }
  return screens.map(s => {
    const g = (s && s.geometry) || {};
    return {
      name: (s && s.name) ? String(s.name) : "",
      width: g.width || 0,
      height: g.height || 0
    };
  });
}

export function registerQMLComponent(name, component) {
  console.log("KZones: Registering QML component:", name);
  try {
    QML[name] = component;
  } catch (error) {
    console.error("KZones: Error registering QML component:", error);
  }
}

export function loadConfig() {
  console.log("KZones: Loading config...");

  const defaultLayouts = [
    {
      name: "Priority Grid",
      padding: 0,
      zones: [
        { x: 0, y: 0, height: 100, width: 25 },
        { x: 25, y: 0, height: 100, width: 50 },
        { x: 75, y: 0, height: 100, width: 25 },
      ],
    },
    {
      name: "Quadrant Grid",
      zones: [
        { x: 0, y: 0, height: 50, width: 50 },
        { x: 0, y: 50, height: 50, width: 50 },
        { x: 50, y: 50, height: 50, width: 50 },
        { x: 50, y: 0, height: 50, width: 50 },
      ],
    },
  ];

  let layouts;
  try {
    layouts = JSON.parse(KWin.readConfig("layoutsJson", JSON.stringify(defaultLayouts)));
  } catch (e) {
    // TODO: Notify user about invalid config and using defaults instead
    layouts = defaultLayouts;
  }
  _layoutsRaw = layouts;

  // Any screen-scoped layout forces per-screen tracking; otherwise switching
  // screens could land on an index hidden by the filter.
  const anyScopedLayout = layouts.some(l => isArrayLike(l && l.screens) && l.screens.length > 0);

  config.enableZoneSelector = KWin.readConfig("enableZoneSelector", true);
  config.zoneSelectorTriggerDistance = KWin.readConfig("zoneSelectorTriggerDistance", 1);
  config.enableZoneOverlay = KWin.readConfig("enableZoneOverlay", true);
  config.zoneOverlayShowWhen = KWin.readConfig("zoneOverlayShowWhen", 0);
  config.zoneOverlayHighlightTarget = KWin.readConfig("zoneOverlayHighlightTarget", 0);
  config.zoneOverlayIndicatorDisplay = KWin.readConfig("zoneOverlayIndicatorDisplay", 0);
  config.enableEdgeSnapping = KWin.readConfig("enableEdgeSnapping", false);
  config.edgeSnappingTriggerDistance = KWin.readConfig("edgeSnappingTriggerDistance", 1);
  config.rememberWindowGeometries = KWin.readConfig("rememberWindowGeometries", true);
  config.trackLayoutPerScreen = KWin.readConfig("trackLayoutPerScreen", false) || anyScopedLayout;
  config.smartHotkeys = KWin.readConfig("smartHotkeys", false);
  config.trackLayoutPerDesktop = KWin.readConfig("trackLayoutPerDesktop", false);
  config.showOsdMessages = KWin.readConfig("showOsdMessages", true);
  config.fadeWindowsWhileMoving = KWin.readConfig("fadeWindowsWhileMoving", false);
  config.autoSnapAllNew = KWin.readConfig("autoSnapAllNew", false);
  config.layouts = layouts;
  config.filterMode = KWin.readConfig("filterMode", 0);
  config.filterList = KWin.readConfig("filterList", "");
  config.pollingRate = KWin.readConfig("pollingRate", 100);
  config.enableDebugLogging = KWin.readConfig("enableDebugLogging", false);
  config.enableDebugOverlay = KWin.readConfig("enableDebugOverlay", false);

  QML.root.config = config;

  console.log("KZones: Config loaded:", JSON.stringify(config));
}
