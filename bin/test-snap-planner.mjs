#!/usr/bin/env node
// Smoke test for the Meta+Arrow snap planner. Runs offline (no QML / KWin),
// exercises the planner against the user's two-monitor layout config and
// asserts the documented Flow 2 / Q1–Q11 / cross-monitor outcomes.

import { planSnap } from "../src/contents/code/meta-arrow/snap-planner.mjs";
import { clientToSourcePct } from "../src/contents/code/meta-arrow/geometry.mjs";
import { enterFullscreen } from "../src/contents/code/meta-arrow/fullscreen-state.mjs";

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
  };
  if (opts.preFS) c.preFS = opts.preFS;
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

// Memory restore: 100% on HDMI with preFS=TL -> Meta+Down -> restore TL
const tlPreFS = { x:0, y:0, w:50, h:50, sourceLayoutIndex: 5, sourceZoneIndex: 0, padding: 0, sourceScreen: "HDMI-A-2" };
check("100% HDMI preFS=TL -> Down -> restore",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}, {zone: -1, layout: -1, preFS: tlPreFS}), HDMI, "down"),
  expectRestore());

// Floating centred on HDMI -> Meta+Up -> TL (least adjustment)
check("Floating centred -> Up -> TL",
  plan(mkClient(HDMI, {x:20,y:25,w:60,h:50}), HDMI, "up"),
  expectZone(5, 0, "HDMI-A-2"));

// Dragged 100% on HDMI (no preFS) -> Meta+Left -> left-half (least adjustment)
check("Dragged 100% HDMI -> Left -> left-half",
  plan(mkClient(HDMI, {x:0,y:0,w:100,h:100}), HDMI, "left"),
  expectZone(4, 0, "HDMI-A-2"));

// Dragged 100% on DP (portrait, no preFS) -> Meta+Down -> bottom-2/3 (Top 1/3 Bottom 2/3 zone 1)
check("Dragged 100% DP -> Down -> bottom-2/3",
  plan(mkClient(DP, {x:0,y:0,w:100,h:100}), DP, "down"),
  expectZone(3, 1, "DP-2"));

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

// Horizontal terminal w/o monitor: HDMI alone on right (we'll fake no DP).
// Skip: we model adjacency by geometry; can't easily mock missing monitor here.

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
