.pragma library

// Mouse-button behavior for the bar widget, kept free of QML types so the
// rules can be tested on their own.
//
// Every clickable surface of the widget shares one table: the right button
// toggles playback wherever it lands, left click on the artwork or the label
// opens the now-playing screen, and a transport button's own left click
// dispatches that button's action.

// Qt's button values, repeated here so this file needs no QML import and can
// be exercised outside a running shell.
var LEFT = 1
var RIGHT = 2
var MIDDLE = 4

var INFO = "info"
var PLAY_PAUSE = "playPause"
var PREVIOUS = "previous"
var TRIGGER = "trigger"
var NONE = "none"

// What a press on `surface` with `button` should do. `surface` is "art",
// "label" or "transport". Unknown combinations do nothing.
function actionFor(button, surface) {
  if (button === RIGHT) return PLAY_PAUSE

  if (surface === "transport") return button === LEFT ? TRIGGER : NONE
  if (surface !== "art" && surface !== "label") return NONE

  if (button === LEFT) return INFO
  if (button === MIDDLE) return PREVIOUS
  return NONE
}

if (typeof module !== "undefined") {
  module.exports = {
    LEFT: LEFT,
    RIGHT: RIGHT,
    MIDDLE: MIDDLE,
    INFO: INFO,
    PLAY_PAUSE: PLAY_PAUSE,
    PREVIOUS: PREVIOUS,
    TRIGGER: TRIGGER,
    NONE: NONE,
    actionFor: actionFor
  }
}
