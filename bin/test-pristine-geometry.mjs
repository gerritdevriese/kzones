#!/usr/bin/env node
// Smoke test for pristine-geometry.mjs. Runs offline (no QML / KWin).
// Exercises the state-transition rules + interactive drag rules.

import {
  setConfigGate,
  onStateMaybeChanged,
  onInteractiveStart,
  onInteractiveEnd,
  clear,
  getPristine,
  isAtPristine,
  _resetForTests,
  FLOATING,
  SNAPPED,
  FULLSCREEN,
} from "../src/contents/code/pristine-geometry.mjs";

let pass = 0, fail = 0;

function check(label, cond, detail = "") {
  if (cond) {
    console.log(`PASS  ${label}`);
    pass++;
  } else {
    console.error(`FAIL  ${label}${detail ? "\n      " + detail : ""}`);
    fail++;
  }
}

function rect(x, y, w, h) {
  return { x, y, width: w, height: h };
}
function rectEq(a, b) {
  if (!a || !b) return false;
  return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
}

function mkClient(id) {
  return { internalId: id, frameGeometry: rect(0, 0, 100, 100) };
}

// Build a deps object whose computeState is driven by a `state` variable in
// the closure, and whose applyFrame records into a log.
function mkDeps(initialState) {
  const log = [];
  const ctl = { state: initialState };
  const deps = {
    computeState: () => ctl.state,
    applyFrame: (c, r) => log.push({ kind: "applyFrame", id: c.internalId, rect: { ...r } }),
    unmaximize: (c) => log.push({ kind: "unmaximize", id: c.internalId }),
    log: () => {},
  };
  return { deps, ctl, log };
}

// -------------------------------------------------------------------- 1
{
  _resetForTests();
  const c = mkClient("c1");
  const { deps, ctl } = mkDeps(FLOATING);
  // Start at FLOATING (stateCache uninitialised defaults to FLOATING).
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(100, 100, 800, 600), deps);
  check("1: FLOATING -> SNAPPED captures pristine",
    rectEq(getPristine(c), rect(100, 100, 800, 600)));
}

// -------------------------------------------------------------------- 2
{
  _resetForTests();
  const c = mkClient("c2");
  const { deps, ctl, log } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(50, 60, 700, 500), deps);
  // Now return to floating.
  ctl.state = FLOATING;
  onStateMaybeChanged(c, rect(0, 0, 500, 500), deps);
  check("2a: SNAPPED -> FLOATING fires applyFrame",
    log.length === 1 && log[0].kind === "applyFrame" && rectEq(log[0].rect, rect(50, 60, 700, 500)));
  check("2b: SNAPPED -> FLOATING clears pristine",
    getPristine(c) === null);
}

// -------------------------------------------------------------------- 3
{
  _resetForTests();
  const c = mkClient("c3");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(200, 200, 600, 400), deps);
  // SNAPPED -> FULLSCREEN: should NOT overwrite pristine.
  ctl.state = FULLSCREEN;
  onStateMaybeChanged(c, rect(0, 0, 1920, 1080), deps);
  check("3: FLOATING->SNAPPED->FULLSCREEN keeps original floating pristine",
    rectEq(getPristine(c), rect(200, 200, 600, 400)));
}

// -------------------------------------------------------------------- 4
{
  _resetForTests();
  const c = mkClient("c4");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(150, 150, 500, 400), deps);
  // SNAPPED-A -> SNAPPED-B: still SNAPPED, no transition crossing FLOATING.
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(0, 0, 960, 1080), deps);
  check("4: SNAPPED-A -> SNAPPED-B keeps pristine unchanged",
    rectEq(getPristine(c), rect(150, 150, 500, 400)));
}

// -------------------------------------------------------------------- 5
{
  _resetForTests();
  const c = mkClient("c5");
  const { deps, ctl, log } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(100, 100, 800, 600), deps);
  // Interactive start on a snapped window with pristine cached:
  onInteractiveStart(c, rect(0, 0, 960, 1080), deps);
  check("5a: mid-drag restore fires applyFrame with pristine rect",
    log.length === 1 && log[0].kind === "applyFrame" && rectEq(log[0].rect, rect(100, 100, 800, 600)));
  check("5b: pristine remains cached after mid-drag restore",
    rectEq(getPristine(c), rect(100, 100, 800, 600)));
}

// -------------------------------------------------------------------- 6
{
  _resetForTests();
  const c = mkClient("c6");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(40, 40, 720, 540), deps);
  onInteractiveStart(c, rect(0, 0, 960, 1080), deps);
  // User re-snaps mid-drag (drops on another zone). End in SNAPPED.
  ctl.state = SNAPPED;
  onInteractiveEnd(c, /*isResizing*/ false, deps);
  check("6: drag re-snap keeps pristine for next drag-away",
    rectEq(getPristine(c), rect(40, 40, 720, 540)));
}

// -------------------------------------------------------------------- 7
{
  _resetForTests();
  const c = mkClient("c7");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(40, 40, 720, 540), deps);
  onInteractiveStart(c, rect(0, 0, 960, 1080), deps);
  // User dropped in floating area → pristine consumed.
  ctl.state = FLOATING;
  onInteractiveEnd(c, /*isResizing*/ false, deps);
  check("7: drag to floating after mid-drag restore clears pristine",
    getPristine(c) === null);
}

// -------------------------------------------------------------------- 8
{
  _resetForTests();
  const c = mkClient("c8");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(80, 80, 640, 480), deps);
  // User manually resizes (not moves).
  onInteractiveStart(c, rect(0, 0, 960, 1080), deps);
  onInteractiveEnd(c, /*isResizing*/ true, deps);
  check("8: manual resize clears pristine",
    getPristine(c) === null);
}

// -------------------------------------------------------------------- 9
{
  _resetForTests();
  const c = mkClient("c9");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(30, 30, 600, 500), deps);
  // Simulate "minimize event" — module receives no call (per plan: minimize
  // is invisible to the pristine module). Just verify pristine still exists.
  check("9: minimize is a no-op (pristine retained)",
    rectEq(getPristine(c), rect(30, 30, 600, 500)));
}

// -------------------------------------------------------------------- 10
// Cross-screen: module doesn't clamp (that's the QML applyFrame wrapper's
// job). Verify the module faithfully calls applyFrame with the stored rect
// and the wrapper would receive the original pristine to clip.
{
  _resetForTests();
  const c = mkClient("c10");
  const { deps, ctl, log } = mkDeps(FLOATING);
  // Pristine captured on screen A.
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(100, 100, 1000, 800), deps);
  // Now restore on screen B (different origin/size — module is screen-blind,
  // gets the raw rect; clamping happens in the QML applyFrame wrapper).
  ctl.state = FLOATING;
  onStateMaybeChanged(c, rect(0, 0, 0, 0), deps);
  check("10: restore passes raw pristine rect to applyFrame (clipping is the wrapper's job)",
    log.length === 1 && rectEq(log[0].rect, rect(100, 100, 1000, 800)));
}

// ----------------------------------------------------------------- bonus
{
  _resetForTests();
  setConfigGate(() => false);
  const c = mkClient("cgate");
  const { deps, ctl, log } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(100, 100, 800, 600), deps);
  check("bonus: gate disabled → onStateMaybeChanged no-op",
    getPristine(c) === null && log.length === 0);
  setConfigGate(() => true);
}

// ------------------------------------------------- isAtPristine sanity
{
  _resetForTests();
  const c = mkClient("cap");
  const { deps, ctl } = mkDeps(FLOATING);
  ctl.state = SNAPPED;
  onStateMaybeChanged(c, rect(100, 100, 800, 600), deps);
  c.frameGeometry = rect(102, 100, 800, 600); // within 4px tolerance
  check("extra: isAtPristine true within tolerance",
    isAtPristine(c, x => x.frameGeometry) === true);
  c.frameGeometry = rect(200, 200, 800, 600);
  check("extra: isAtPristine false when far off",
    isAtPristine(c, x => x.frameGeometry) === false);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
