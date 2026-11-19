"use strict";

const { BrowserWindow, app } = require("electron");

const noop = () => {};
const winOnly = {
  hookWindowMessage: noop,
  unhookWindowMessage: noop,
  unhookAllWindowMessages: noop,
  isWindowMessageHooked: () => false,
  setThumbarButtons: () => false,
  setThumbnailClip: () => false,
  setThumbnailToolTip: () => false,
  setAppDetails: noop,
  setOverlayIcon: noop,
  setIcon: undefined,
};
for (const [k, v] of Object.entries(winOnly)) {
  if (v !== undefined && typeof BrowserWindow.prototype[k] !== "function") BrowserWindow.prototype[k] = v;
}
if (typeof app.setUserTasks !== "function") app.setUserTasks = () => false;
if (typeof app.setJumpList !== "function") app.setJumpList = () => "ok";
