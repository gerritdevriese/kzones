export let KWin = null;
export let Workspace = null;
export let QML = {};
export let config = {};

export function init(kwin, workspace) {
  console.log("KZones: Loading APIs...");
  KWin = kwin || null;
  Workspace = workspace || null;
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
    // [0][0] Two Columns (1/2 - 1/2)
    {
      name: "Two Columns (1/2 - 1/2)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 50, height: 100 },
        { x: 50, y: 0, width: 50, height: 100 },
      ],
    },
    // [0][1] Two Columns (2/3 - 1/3)
    {
      name: "Two Columns (2/3 - 1/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 66.67, height: 100 },
        { x: 66.67, y: 0, width: 33.33, height: 100 },
      ],
    },
    // [0][2] Two Columns (1/3 - 2/3)
    {
      name: "Two Columns (1/3 - 2/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 33.33, height: 100 },
        { x: 33.33, y: 0, width: 66.67, height: 100 },
      ],
    },
    // [0][3] Three Columns (1/3 - 1/3 - 1/3)
    {
      name: "Three Columns (1/3 - 1/3 - 1/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 33.33, height: 100 },
        { x: 33.33, y: 0, width: 33.34, height: 100 },
        { x: 66.67, y: 0, width: 33.33, height: 100 },
      ],
    },
    // [1][0] Priority Grid Left (1/2 - 1/4 - 1/4)
    {
      name: "Priority Grid Left (1/2 - 1/4 - 1/4)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 50, height: 100 },
        { x: 50, y: 0, width: 50, height: 50 },
        { x: 50, y: 50, width: 50, height: 50 },
      ],
    },
    // [1][1] Priority Grid Right (1/4 - 1/4 - 1/2)
    {
      name: "Priority Grid Right (1/4 - 1/4 - 1/2)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 50, height: 50 },
        { x: 0, y: 50, width: 50, height: 50 },
        { x: 50, y: 0, width: 50, height: 100 },
      ],
    },
    // [1][2] Quadrant Grid (2x2)
    {
      name: "Quadrant Grid (2x2)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 50, height: 50 },
        { x: 50, y: 0, width: 50, height: 50 },
        { x: 0, y: 50, width: 50, height: 50 },
        { x: 50, y: 50, width: 50, height: 50 },
      ],
    },
    // [1][3] Three Columns (1/6 - 2/3 - 1/6)
    {
      name: "Three Columns (1/6 - 2/3 - 1/6)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 16.67, height: 100 },
        { x: 16.67, y: 0, width: 66.66, height: 100 },
        { x: 83.33, y: 0, width: 16.67, height: 100 },
      ],
    },
    // [2][0] Two Rows (1/2 - 1/2)
    {
      name: "Two Rows (1/2 - 1/2)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 50 },
        { x: 0, y: 50, width: 100, height: 50 },
      ],
    },
    // [2][1] Three Rows (1/3 - 1/3 - 1/3)
    {
      name: "Three Rows (1/3 - 1/3 - 1/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 33.33 },
        { x: 0, y: 33.33, width: 100, height: 33.34 },
        { x: 0, y: 66.67, width: 100, height: 33.33 },
      ],
    },
    // [2][2] Four Rows (1/4 - 1/4 - 1/4 - 1/4)
    {
      name: "Four Rows (1/4 - 1/4 - 1/4 - 1/4)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 25 },
        { x: 0, y: 25, width: 100, height: 25 },
        { x: 0, y: 50, width: 100, height: 25 },
        { x: 0, y: 75, width: 100, height: 25 },
      ],
    },
    // [2][3] Two Rows (2/3 - 1/3)
    {
      name: "Two Rows (2/3 - 1/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 66.67 },
        { x: 0, y: 66.67, width: 100, height: 33.33 },
      ],
    },
    // [3][0] Two Rows (1/3 - 2/3)
    {
      name: "Two Rows (1/3 - 2/3)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 33.33 },
        { x: 0, y: 33.33, width: 100, height: 66.67 },
      ],
    },
    // [3][1] Priority Rows Top (1/2 - 1/4 - 1/4)
    {
      name: "Priority Rows Top (1/2 - 1/4 - 1/4)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 50 },
        { x: 0, y: 50, width: 50, height: 50 },
        { x: 50, y: 50, width: 50, height: 50 },
      ],
    },
    // [3][2] Priority Rows Bottom (1/4 - 1/4 - 1/2)
    {
      name: "Priority Rows Bottom (1/4 - 1/4 - 1/2)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 50, height: 50 },
        { x: 50, y: 0, width: 50, height: 50 },
        { x: 0, y: 50, width: 100, height: 50 },
      ],
    },
    // [3][3] Three Rows (1/6 - 2/3 - 1/6)
    {
      name: "Three Rows (1/6 - 2/3 - 1/6)",
      padding: 0,
      zones: [
        { x: 0, y: 0, width: 100, height: 16.67 },
        { x: 0, y: 16.67, width: 100, height: 66.66 },
        { x: 0, y: 83.33, width: 100, height: 16.67 },
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

  config.enableZoneSelector = KWin.readConfig("enableZoneSelector", true);
  config.zoneSelectorTriggerDistance = KWin.readConfig("zoneSelectorTriggerDistance", 1);
  config.enableZoneOverlay = KWin.readConfig("enableZoneOverlay", true);
  config.zoneOverlayShowWhen = KWin.readConfig("zoneOverlayShowWhen", 0);
  config.zoneOverlayHighlightTarget = KWin.readConfig("zoneOverlayHighlightTarget", 0);
  config.zoneOverlayIndicatorDisplay = KWin.readConfig("zoneOverlayIndicatorDisplay", 0);
  const enableSnapAssist = KWin.readConfig("enableSnapAssist", true);
  config.enableSnapAssist = enableSnapAssist !== false;
  config.enableStickyResizing = KWin.readConfig("enableStickyResizing", true);
  config.enableEdgeSnapping = KWin.readConfig("enableEdgeSnapping", false);
  config.edgeSnappingTriggerDistance = KWin.readConfig("edgeSnappingTriggerDistance", 1);
  config.rememberWindowGeometries = KWin.readConfig("rememberWindowGeometries", true);
  config.trackLayoutPerScreen = KWin.readConfig("trackLayoutPerScreen", false);
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
