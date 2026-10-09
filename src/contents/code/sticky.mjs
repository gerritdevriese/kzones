export let snaps = [];
export let resizedInfo = null;

export function isSameScreen(c1, c2) {
  if (!c1 || !c2) return true;
  const o1 = c1.output !== undefined ? c1.output : c1.screen;
  const o2 = c2.output !== undefined ? c2.output : c2.screen;
  if (o1 !== undefined && o1 !== null && o2 !== undefined && o2 !== null) {
    if (o1 === o2) return true;
    if (o1.name && o2.name && o1.name === o2.name) return true;
    if (typeof o1 === "number" && typeof o2 === "number") return o1 === o2;
    return false;
  }
  return true;
}

export function isOnCurrentDesktop(c, Workspace) {
  if (!c) return false;
  if (c.onAllDesktops) return true;
  if (c.onCurrentDesktop !== undefined && c.onCurrentDesktop) return true;
  if (c.desktops && Workspace && Workspace.currentDesktop) {
    for (let i = 0; i < c.desktops.length; i++) {
      if (c.desktops[i] === Workspace.currentDesktop || (c.desktops[i].id && c.desktops[i].id === Workspace.currentDesktop.id)) {
        return true;
      }
    }
    return false;
  }
  if (c.desktop !== undefined && Workspace && Workspace.currentDesktop !== undefined) {
    if (c.desktop === Workspace.currentDesktop || (c.desktop.id && c.desktop.id === Workspace.currentDesktop.id)) {
      return true;
    }
    return false;
  }
  return true;
}

export function startResize(client, Workspace, config, checkFilter) {
  if (!config || !config.enableStickyResizing) return;
  if (!client || !client.resize) return;

  const g1 = client.frameGeometry;
  if (!g1) return;
  const l1 = g1.x;
  const r1 = g1.x + g1.width;
  const t1 = g1.y;
  const b1 = g1.y + g1.height;
  const threshold = 15;

  resizedInfo = {
    lOrig: l1,
    rOrig: r1,
    tOrig: t1,
    bOrig: b1,
    lMoved: false,
    rMoved: false,
    tMoved: false,
    bMoved: false,
  };
  snaps = [];

  const windows = Workspace.stackingOrder;
  if (!windows) return;

  for (let i = 0; i < windows.length; i++) {
    const c = windows[i];
    if (!c || c === client) continue;
    if (!c.normalWindow || c.popupWindow || c.skipTaskbar) continue;
    if (checkFilter && !checkFilter(c)) continue;
    if (!isSameScreen(c, client)) continue;
    if (!isOnCurrentDesktop(c, Workspace)) continue;
    if (c.minimized || c.fullScreen) continue;

    const g2 = c.frameGeometry;
    if (!g2) continue;
    const l2 = g2.x;
    const r2 = g2.x + g2.width;
    const t2 = g2.y;
    const b2 = g2.y + g2.height;

    // Check overlap along shared edge (at least 10px overlap)
    const vOverlap = Math.min(b1, b2) - Math.max(t1, t2) > 10;
    const hOverlap = Math.min(r1, r2) - Math.max(l1, l2) > 10;

    const lr = vOverlap && Math.abs(l1 - r2) <= threshold;
    const rl = vOverlap && Math.abs(r1 - l2) <= threshold;
    const tb = hOverlap && Math.abs(t1 - b2) <= threshold;
    const bt = hOverlap && Math.abs(b1 - t2) <= threshold;

    if (lr || rl || tb || bt) {
      snaps.push({
        client: c,
        originalGeometry: { x: g2.x, y: g2.y, width: g2.width, height: g2.height },
        lr,
        rl,
        tb,
        bt,
      });
    }
  }
}

export function stepResize(client, rect, config) {
  if (!config || !config.enableStickyResizing) return;
  if (!resizedInfo || !client || !client.resize) return;

  const currentRect = rect || client.frameGeometry;
  if (!currentRect) return;

  resizedInfo.lMoved = resizedInfo.lMoved || (resizedInfo.lOrig !== currentRect.x);
  resizedInfo.rMoved = resizedInfo.rMoved || (resizedInfo.rOrig !== currentRect.x + currentRect.width);
  resizedInfo.tMoved = resizedInfo.tMoved || (resizedInfo.tOrig !== currentRect.y);
  resizedInfo.bMoved = resizedInfo.bMoved || (resizedInfo.bOrig !== currentRect.y + currentRect.height);

  for (let i = 0; i < snaps.length; i++) {
    const s = snaps[i];
    const og = s.originalGeometry;
    let newX = og.x;
    let newY = og.y;
    let newWidth = og.width;
    let newHeight = og.height;

    if (resizedInfo.lMoved && s.lr) {
      // Client left moved: neighbor is to the left (adjust its width)
      newWidth = currentRect.x - newX;
    }
    if (resizedInfo.rMoved && s.rl) {
      // Client right moved: neighbor is to the right (adjust its x and width)
      const rightEdge = og.x + og.width;
      newX = currentRect.x + currentRect.width;
      newWidth = rightEdge - newX;
    }
    if (resizedInfo.tMoved && s.tb) {
      // Client top moved: neighbor is above (adjust its height)
      newHeight = currentRect.y - newY;
    }
    if (resizedInfo.bMoved && s.bt) {
      // Client bottom moved: neighbor is below (adjust its y and height)
      const bottomEdge = og.y + og.height;
      newY = currentRect.y + currentRect.height;
      newHeight = bottomEdge - newY;
    }

    const minW = Math.max(50, (s.client.minSize && (s.client.minSize.width ?? s.client.minSize.w)) || 50);
    const minH = Math.max(50, (s.client.minSize && (s.client.minSize.height ?? s.client.minSize.h)) || 50);

    if (newWidth < minW) {
      if (s.rl) newX = og.x + og.width - minW;
      newWidth = minW;
    }
    if (newHeight < minH) {
      if (s.bt) newY = og.y + og.height - minH;
      newHeight = minH;
    }

    if (newWidth >= minW && newHeight >= minH) {
      s.client.frameGeometry = Qt.rect(
        Math.round(newX),
        Math.round(newY),
        Math.round(newWidth),
        Math.round(newHeight)
      );
    }
  }
}

export function finishResize() {
  snaps = [];
  resizedInfo = null;
}
