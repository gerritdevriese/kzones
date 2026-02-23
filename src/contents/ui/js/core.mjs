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

  config.enableZoneSelector = KWin.readConfig("enableZoneSelector", true);
  config.zoneSelectorTriggerDistance = KWin.readConfig("zoneSelectorTriggerDistance", 1);
  config.enableZoneOverlay = KWin.readConfig("enableZoneOverlay", true);
  config.zoneOverlayShowWhen = KWin.readConfig("zoneOverlayShowWhen", 0);
  config.zoneOverlayHighlightTarget = KWin.readConfig("zoneOverlayHighlightTarget", 0);
  config.zoneOverlayIndicatorDisplay = KWin.readConfig("zoneOverlayIndicatorDisplay", 0);
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
