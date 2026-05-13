import { isFullscreenSized as geomIsFullscreenSized } from "./geometry.mjs";

// pre-fullscreen memory is stored as an ad-hoc property on the KWin client
// object (same pattern as client.zone / client.oldGeometry in main.qml).

export function enterFullscreen(client, sourceZoneRef, dir, screenName) {
  if (!client) return;
  client.preFS = sourceZoneRef
    ? {
        x: sourceZoneRef.x, y: sourceZoneRef.y, w: sourceZoneRef.w, h: sourceZoneRef.h,
        sourceLayoutIndex: sourceZoneRef.sourceLayoutIndex,
        sourceZoneIndex: sourceZoneRef.sourceZoneIndex,
        padding: sourceZoneRef.padding,
        sourceScreen: screenName || "",
      }
    : null;
  client.preFSEntryDir = dir || null;
}

export function getPreFullscreen(client) {
  return (client && client.preFS) ? client.preFS : null;
}

export function clearMemory(client) {
  if (!client) return;
  if (client.preFS !== undefined) client.preFS = null;
  if (client.preFSEntryDir !== undefined) client.preFSEntryDir = null;
}

export function isFullscreenSized(client, clientArea) {
  return geomIsFullscreenSized(client, clientArea);
}
