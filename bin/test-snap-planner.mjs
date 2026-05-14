#!/usr/bin/env node
// Smoke test for the Meta+Arrow snap planner. Runs offline (no QML / KWin),
// exercises the planner against the user's two-monitor layout config and
// asserts the documented Flow 2 / Q1–Q11 / cross-monitor outcomes.

import { planSnap } from "../src/contents/code/meta-arrow/snap-planner.mjs";
import { clientToSourcePct } from "../src/contents/code/meta-arrow/geometry.mjs";
import { captureMove } from "../src/contents/code/meta-arrow/move-memory.mjs";

const layouts = [
  { name: "Portrait - Thirds", screens: ["DP-2"], padding: 0, zones: [
    { x: 0, y: 0,  width: 100, height: 33 },
    { x: 0, y: 33, width: 100, height: 34 },
    { x: 0, y: 67, width: 100, height: 33 },
  ]},
  { name: "Portrait - Halves", screens: ["DP-2"], padding: 0, zones: [
    { x: 0, y: 0,  width: 100, height: 50 },
    { x: 0, y: 50, width: 100, height: 50 },
  ]},
  { name: "Portrait - Top 2/3 Bottom 1/3", screens: ["DP-2"], padding: 0, zones: [
    { x: 0, y: 0,  width: 100, height: 67 },
    { x: 0, y: 67, width: 100, height: 33 },
  ]},
  { name: "Portrait - Top 1/3 Bottom 2/3", screens: ["DP-2"], padding: 0, zones: [
    { x: 0, y: 0,  width: 100, height: 33 },
    { x: 0, y: 33, width: 100, height: 67 },
  ]},
  { name: "Landscape - Halves", screens: ["HDMI-A-2"], padding: 0, zones: [
    { x: 0,  y: 0, width: 50, height: 100 },
    { x: 50, y: 0, width: 50, height: 100 },
  ]},
  { name: "Landscape - Quarters", screens: ["HDMI-A-2"], padding: 0, zones: [
    { x: 0,  y: 0,  width: 50, height: 50 },
    { x: 50, y: 0,  width: 50, height: 50 },
    { x: 0,  y: 50, width: 50, height: 50 },
    { x: 50, y: 50, width: 50, height: 50 },
  ]},
  { name: "Landscape - Horizontal Thirds", screens: ["HDMI-A-2"], padding: 0, zones: [
    { x: 0,  y: 0, width: 33, height: 100 },
    { x: 33, y: 0, width: 34, height: 100 },
    { x: 67, y: 0, width: 33, height: 100 },
  ]},
];

const HDMI = { name: "HDMI-A-2", geometry: { x: 0,    y: 0, width: 1920, height: 1080 } };
const DP   = { name: "DP-2",     geometry: { x: 1920, y: 0, width: 1080, height: 1920 } };
const screens = [HDMI, DP];

function clientArea(screen) {
  return { x: screen.geometry.x, y: screen.geometry.y, width: screen.geometry.width, height: screen.geometry.height };
}

function mkClient(screen, pctRect, opts = {}) {
  const ca = clientArea(screen);
  const fg = {
    x: ca.x + Math.round(pctRect.x / 100 * ca.width),
    y: ca.y + Math.round(pctRect.y / 100 * ca.height),
    width:  Math.round(pctRect.w / 100 * ca.width),
    height: Math.round(pctRect.h / 100 * ca.height),
  };
  const c = {
    frameGeometry: fg,
    zone: opts.zone != null ? opts.zone : -1,
    layout: opts.layout != null ? opts.layout : -1,
    internalId: opts.internalId || ("test-" + Math.random().toString(36).slice(2)),
  };
  if (opts.metaMemory) {
    captureMove(c, opts.metaMemory.prevGeometry, opts.metaMemory.direction, opts.metaMemory.snappedGeometry);
  }
  return c;
}

let pass = 0, fail = 0;
function check(label, actual, expected) {
  const aStr = JSON.stringify(actual);
  const eMatch = expected(actual);
  if (eMatch.ok) {
    console.log(`PASS  ${label}`);
    pass++;
  } else {
    console.error(`FAIL  ${label}\n      expected: ${eMatch.want}\n      got:      ${aStr}`);
    fail++;
  }
}

function expectZone(layoutIdx, zoneIdx, screenName) {
  return (a) => ({
    ok: a.type === "zone" && a.layoutIndex === layoutIdx && a.zoneIndex === zoneIdx && a.screenName === screenName,
    want: `zone layout=${layoutIdx} zone=${zoneIdx} screen=${screenName}`,
  });
}
function expectFullscreen(screenName) {
  return (a) => ({ ok: a.type === "fullscreen" && a.screenName === screenName, want: `fullscreen on ${screenName}` });
}
function expectRestore() {
  return (a) => ({ ok: a.type === "restore", want: "restore" });
}
function expectNoop() {
  return (a) => ({ ok: a.type === "noop", want: "noop" });
}
function expectJumpTo(targetScreen, nextPredicate) {
  return (a) => {
    if (a.type !== "jump" || a.targetScreen !== targetScreen) return { ok: false, want: `jump -> ${targetScreen}` };
    const inner = nextPredicate(a.nextAction);
    return { ok: inner.ok, want: `jump -> ${targetScreen} -> ${inner.want}` };
  };
}

function plan(client, screen, dir) {
  const ca = clientArea(screen);
  const source = clientToSourcePct(client, ca);
  return planSnap({ client, source, clientArea: ca, dir, screens, currentScreen: screen, layouts });
}

// Layout index reminders for assertions:
//   4 = Landscape - Halves      (zones: 0=left-half,  1=right-half)
//   5 = Landscape - Quarters    (zones: 0=TL, 1=TR, 2=BL, 3=BR)
//   6 = Landscape - Hor Thirds  (zones: 0=L3, 1=M3, 2=R3)
//   1 = Portrait - Halves       (zones: 0=top-half,   1=bottom-half)
//   3 = Portrait - 1/3-2/3      (zones: 0=top-1/3,    1=bottom-2/3)

// Q1: top-left ¼ on HDMI -> Meta+Right -> top-right ¼
check("Q1 TL -> Right -> TR",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:50}, {zone: 0, layout: 5}), HDMI, "right"),
  expectZone(5, 1, "HDMI-A-2"));

// Q11: left-half -> Meta+Up -> TL
check("Q11 left-half -> Up -> TL",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:100}, {zone: 0, layout: 4}), HDMI, "up"),
  expectZone(5, 0, "HDMI-A-2"));

// Flow 2 step 1: BL -> Meta+Up -> left-half
check("Flow2 BL -> Up -> left-half",
  plan(mkClient(HDMI, {x:0,y:50,w:50,h:50}, {zone: 2, layout: 5}), HDMI, "up"),
  expectZone(4, 0, "HDMI-A-2"));

// Flow 2 step 2: left-half -> Meta+Up -> TL (same as Q11)
check("Flow2 left-half -> Up -> TL",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:100}, {zone: 0, layout: 4}), HDMI, "up"),
  expectZone(5, 0, "HDMI-A-2"));

// Flow 2 step 3: TL -> Meta+Up -> fullscreen
check("Flow2 TL -> Up -> fullscreen",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:50}, {zone: 0, layout: 5}), HDMI, "up"),
  expectFullscreen("HDMI-A-2"));

// Memory restore: 100% on HDMI with metaMemory direction=up (we got here
// via Meta+Up from TL). Meta+Down -> restore the previous (TL) geometry.
const tlPixelRect = { x: 0, y: 0, width: 960, height: 540 };
const fullscreenHdmiRect = { x: 0, y: 0, width: 1920, height: 1080 };
check("100% HDMI metaMemory(up) -> Down -> restore",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}, {
    zone: -1, layout: -1,
    metaMemory: { prevGeometry: tlPixelRect, direction: "up", snappedGeometry: fullscreenHdmiRect },
  }), HDMI, "down"),
  expectRestore());

// Universal undo: bot-2/3 on DP with memory direction=down -> Meta+Up restores.
const bot23PixelRect = { x: 1920, y: Math.round(0.33 * 1920), width: 1080, height: Math.round(0.67 * 1920) };
const dpFullscreenRect = { x: 1920, y: 0, width: 1080, height: 1920 };
check("DP bot-2/3 metaMemory(down) -> Up -> restore fullscreen",
  plan(mkClient(DP, {x:0,y:33,w:100,h:67}, {
    zone: 1, layout: 3,
    metaMemory: { prevGeometry: dpFullscreenRect, direction: "down", snappedGeometry: bot23PixelRect },
  }), DP, "up"),
  expectRestore());

// Same window same memory but Meta+Down (NOT opposite) -> normal logic.
check("DP bot-2/3 metaMemory(down) -> Down -> normal flow",
  plan(mkClient(DP, {x:0,y:33,w:100,h:67}, {
    zone: 1, layout: 3,
    metaMemory: { prevGeometry: dpFullscreenRect, direction: "down", snappedGeometry: bot23PixelRect },
  }), DP, "down"),
  (a) => ({ ok: a.type !== "restore", want: "not restore (same direction)" }));

// Perpendicular press (Left/Right) from bot-2/3 with down-memory -> not restore.
check("DP bot-2/3 metaMemory(down) -> Left -> not restore",
  plan(mkClient(DP, {x:0,y:33,w:100,h:67}, {
    zone: 1, layout: 3,
    metaMemory: { prevGeometry: dpFullscreenRect, direction: "down", snappedGeometry: bot23PixelRect },
  }), DP, "left"),
  (a) => ({ ok: a.type !== "restore", want: "not restore (perpendicular)" }));

// Relaxed axis-preserve: tall left-third on HDMI -> Meta+Up should land on TL
// even though TL.w (50) != source.w (33). Strict width-preserve gives no
// candidates above source -> relax to full pool -> TL.
check("left-third -> Up -> TL (relaxed axis preserve)",
  plan(mkClient(HDMI, {x:0,y:0,w:33,h:100}, {zone: 0, layout: 6}), HDMI, "up"),
  expectZone(5, 0, "HDMI-A-2"));

// Symmetric: right-third -> Meta+Up -> TR.
check("right-third -> Up -> TR (relaxed)",
  plan(mkClient(HDMI, {x:67,y:0,w:33,h:100}, {zone: 2, layout: 6}), HDMI, "up"),
  expectZone(5, 1, "HDMI-A-2"));

// left-third -> Meta+Down -> BL.
check("left-third -> Down -> BL (relaxed)",
  plan(mkClient(HDMI, {x:0,y:0,w:33,h:100}, {zone: 0, layout: 6}), HDMI, "down"),
  expectZone(5, 2, "HDMI-A-2"));

// right-third -> Meta+Down -> BR.
check("right-third -> Down -> BR (relaxed)",
  plan(mkClient(HDMI, {x:67,y:0,w:33,h:100}, {zone: 2, layout: 6}), HDMI, "down"),
  expectZone(5, 3, "HDMI-A-2"));

// middle-third (HDMI) -> Meta+Up -> fullscreen. Relaxed pool would offer TL/TR
// but their perpendicular centres (cx=25, cx=75) lie outside source x-range
// [33, 67], so the relax step rejects them and we fall through to the Up
// terminal.
check("middle-third -> Up -> fullscreen (centred column)",
  plan(mkClient(HDMI, {x:33,y:0,w:34,h:100}, {zone: 1, layout: 6}), HDMI, "up"),
  expectFullscreen("HDMI-A-2"));

// middle-third (HDMI) -> Meta+Down -> noop. No relax candidate inside source
// x-range, no monitor below in fixture -> nothing should happen.
check("middle-third -> Down -> noop (no relax overlap, no monitor)",
  plan(mkClient(HDMI, {x:33,y:0,w:34,h:100}, {zone: 1, layout: 6}), HDMI, "down"),
  expectNoop());

// Floating window whose source on the current monitor sits past every
// candidate's centre (e.g. window with 1% bleeding onto next monitor, the
// rest hugging the current monitor's left edge). Strict centre-in-dir filter
// is empty -> fall back to direction-edge tiles on the SAME monitor instead
// of jumping over to the bled-onto monitor.
check("source hugging HDMI left edge -> Left -> edge tile (no jump)",
  plan(mkClient(HDMI, {x:0,y:30,w:10,h:60}), HDMI, "left"),
  (a) => ({ ok: a.type === "zone" && a.screenName === "HDMI-A-2", want: "zone on HDMI-A-2" }));

// skipSmartHotkeys: per-zone flag removes a zone from the Smart Hotkeys pool.
// Layouts with skipSmartHotkeys at the layout level skip every zone. Accept
// both real booleans and stringified "true" (user-authored JSON quirk).
const skipLayouts = JSON.parse(JSON.stringify(layouts));
skipLayouts[5].zones[1].skipSmartHotkeys = "true"; // TR on HDMI Quarters skipped
function planWithLayouts(client, screen, dir, layoutOverride) {
  const ca = clientArea(screen);
  const source = clientToSourcePct(client, ca);
  return planSnap({ client, source, clientArea: ca, dir, screens, currentScreen: screen, layouts: layoutOverride });
}
check("skipSmartHotkeys per-zone hides TR from Meta+Right",
  planWithLayouts(mkClient(HDMI, {x:0,y:0,w:50,h:50}, {zone: 0, layout: 5}), HDMI, "right", skipLayouts),
  (a) => ({ ok: a.type !== "zone" || !(a.layoutIndex === 5 && a.zoneIndex === 1), want: "anything except TR (layout 5 zone 1)" }));

const skipLayouts2 = JSON.parse(JSON.stringify(layouts));
skipLayouts2[5].skipSmartHotkeys = true; // whole Quarters layout hidden
check("skipSmartHotkeys per-layout removes Quarters from pool",
  planWithLayouts(mkClient(HDMI, {x:0,y:50,w:50,h:50}, {zone: 2, layout: 5}), HDMI, "up", skipLayouts2),
  (a) => ({ ok: !(a.type === "zone" && a.layoutIndex === 5), want: "zone not from layout 5" }));

// Floating centred on HDMI -> Meta+Up -> TL (least adjustment)
check("Floating centred -> Up -> TL",
  plan(mkClient(HDMI, {x:20,y:25,w:60,h:50}), HDMI, "up"),
  expectZone(5, 0, "HDMI-A-2"));

// Dragged 100% on HDMI (no preFS) -> Meta+Left -> left-half (least adjustment)
check("Dragged 100% HDMI -> Left -> left-half",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}), HDMI, "left"),
  expectZone(4, 0, "HDMI-A-2"));

// Dragged 100% on DP (portrait, no preFS) -> Meta+Down -> middle-third.
// Source covers the entire monitor so cycle-in-direction is inclusive: the
// centred horizontal band wins on minimal change, instead of jumping to a
// bottom-aligned tile.
check("Dragged 100% DP -> Down -> middle-third",
  plan(mkClient(DP, {x:0,y:0,w:100,h:100}), DP, "down"),
  expectZone(0, 1, "DP-2"));

// Same situation on HDMI (landscape fullscreen + Meta+Down) -> middle
// vertical strip (Horizontal Thirds zone 1).
check("Dragged 100% HDMI -> Down -> middle-third",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}), HDMI, "down"),
  expectZone(6, 1, "HDMI-A-2"));

// Flow 3: TL -> Meta+Right -> TR; TR -> Meta+Down -> right-half; right-half -> Meta+Down -> BR
check("Flow3 TL -> Right -> TR",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:50}, {zone: 0, layout: 5}), HDMI, "right"),
  expectZone(5, 1, "HDMI-A-2"));
check("Flow3 TR -> Down -> right-half",
  plan(mkClient(HDMI, {x:50,y:0,w:50,h:50}, {zone: 1, layout: 5}), HDMI, "down"),
  expectZone(4, 1, "HDMI-A-2"));
check("Flow3 right-half -> Down -> BR",
  plan(mkClient(HDMI, {x:50,y:0,w:50,h:100}, {zone: 1, layout: 4}), HDMI, "down"),
  expectZone(5, 3, "HDMI-A-2"));

// Cross-monitor: right-third on HDMI -> Meta+Right -> 100% on DP (height preserved, no h=100 zone on portrait)
check("right-third -> Right -> jump DP fullscreen",
  plan(mkClient(HDMI, {x:67,y:0,w:33,h:100}, {zone: 2, layout: 6}), HDMI, "right"),
  expectJumpTo("DP-2", expectFullscreen("DP-2")));

// ¼-to-portrait: TR on HDMI -> Meta+Right -> DP top-half
check("TR -> Right -> jump DP top-half",
  plan(mkClient(HDMI, {x:50,y:0,w:50,h:50}, {zone: 1, layout: 5}), HDMI, "right"),
  expectJumpTo("DP-2", expectZone(1, 0, "DP-2")));

// No monitor right of DP: top of DP -> Meta+Right -> noop
check("DP top -> Right -> noop",
  plan(mkClient(DP, {x:0,y:0,w:100,h:33}, {zone: 0, layout: 0}), DP, "right"),
  expectNoop());

// Right-third sequence — center-in-direction with full intermediate tiles:
//   right-third (67/33) -> right-half (50/50) -> middle-third (33/34)
//   -> left-half (0/50) -> left-third (0/33)
check("seq right-third  -> Left -> right-half",
  plan(mkClient(HDMI, {x:67,y:0,w:33,h:100}, {zone: 2, layout: 6}), HDMI, "left"),
  expectZone(4, 1, "HDMI-A-2"));
check("seq right-half   -> Left -> middle-third",
  plan(mkClient(HDMI, {x:50,y:0,w:50,h:100}, {zone: 1, layout: 4}), HDMI, "left"),
  expectZone(6, 1, "HDMI-A-2"));
check("seq middle-third -> Left -> left-half",
  plan(mkClient(HDMI, {x:33,y:0,w:34,h:100}, {zone: 1, layout: 6}), HDMI, "left"),
  expectZone(4, 0, "HDMI-A-2"));
check("seq left-half    -> Left -> left-third",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:100}, {zone: 0, layout: 4}), HDMI, "left"),
  expectZone(6, 0, "HDMI-A-2"));

// Fullscreen on portrait (DP-2 sits right of HDMI in fixture). Meta+Left
// should jump to landscape on the LEFT and land on the entry edge -> the
// rightmost h=100 zone on HDMI = right-third.
check("DP-2 fullscreen -> Left -> jump HDMI right-third",
  plan(mkClient(DP, {x:0,y:0,w:100,h:100}), DP, "left"),
  expectJumpTo("HDMI-A-2", expectZone(6, 2, "HDMI-A-2")));

// DP-2 has no monitor on its right side in this fixture -> noop.
check("DP-2 fullscreen -> Right -> noop (no monitor right)",
  plan(mkClient(DP, {x:0,y:0,w:100,h:100}), DP, "right"),
  expectNoop());

// HDMI is landscape -- has horizontal zones, so Meta+Right from HDMI
// fullscreen stays on monitor and picks closest zone (right-half).
check("HDMI fullscreen -> Right -> right-half (in-monitor)",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}), HDMI, "right"),
  expectZone(4, 1, "HDMI-A-2"));

// Same chain in reverse using Meta+Right:
check("seq left-third   -> Right -> left-half",
  plan(mkClient(HDMI, {x:0,y:0,w:33,h:100}, {zone: 0, layout: 6}), HDMI, "right"),
  expectZone(4, 0, "HDMI-A-2"));
check("seq left-half    -> Right -> middle-third",
  plan(mkClient(HDMI, {x:0,y:0,w:50,h:100}, {zone: 0, layout: 4}), HDMI, "right"),
  expectZone(6, 1, "HDMI-A-2"));
check("seq middle-third -> Right -> right-half",
  plan(mkClient(HDMI, {x:33,y:0,w:34,h:100}, {zone: 1, layout: 6}), HDMI, "right"),
  expectZone(4, 1, "HDMI-A-2"));

// Horizontal terminal w/o monitor: HDMI alone on right (we'll fake no DP).
// Skip: we model adjacency by geometry; can't easily mock missing monitor here.

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
