.pragma library

// Which parts of the widget the bar shows at a given width, kept free of QML
// types so the ladder can be tested without a running shell.
//
// The adaptive ladder, from widest to narrowest:
//
//   0  everything
//   1  play/pause instead of previous/play/next (and no seek buttons)
//   2  artwork, label, no controls
//   3  label only
//   4  one minimal hit: play/pause, or artwork, or the label
//   5  nothing fits, hide the widget
//
// Two settings bypass the ladder: album art only, and idle (no media), both of
// which keep the widget at artwork width with no label and no controls.

var HIDDEN_STAGE = 5

// `state` is a plain object of geometry and switches, built by the widget:
//   horizontalPadding, buttonWidth, contentSpacing, artLabelGap,
//   artSize, barSize,
//   preferredLabelWidth, minimumLabelWidth, adaptiveWidthBudget,
//   hasLabel, hasMedia, showAlbumArt, showControls, showSeekControls,
//   adaptiveLayout, albumArtOnly, vertical
// The stage is passed separately so these functions never read each other's
// derived properties.

function albumOnlyWidth(state) {
  return state.horizontalPadding + state.artSize
}

// The narrowest clickable form: one button, no artwork, no label.
function minimalHitWidth(state) {
  return state.horizontalPadding + state.buttonWidth
}

// Total width of `state` when the widget shows `buttons` transport buttons,
// plus optional artwork and label. Artwork and label need a little more room
// between them than two controls do: the disc is round and its ring reaches
// past its own box, so the text would otherwise look glued to it.
function widthFor(state, buttons, includeArt, includeLabel, labelWidth) {
  var count = buttons + (includeArt ? 1 : 0) + (includeLabel ? 1 : 0)
  if (count === 0) return 0
  return state.horizontalPadding
    + buttons * state.buttonWidth
    + (includeArt ? state.artSize : 0)
    + (includeLabel ? labelWidth : 0)
    + Math.max(0, count - 1) * state.contentSpacing
    + (includeArt && includeLabel ? (state.artLabelGap || 0) : 0)
}

// Album-art-only and idle share one shape: artwork and nothing else.
function simpleMode(state) {
  return state.albumArtOnly === true || state.hasMedia === false
}

function showsLabel(state, stage) {
  if (simpleMode(state)) return false
  // A vertical bar is 28px wide: text and artwork beside the controls never
  // fit, so only the controls show, as in the upstream widget.
  if (state.vertical === true) return false
  if (state.hasLabel === false) return false
  if (stage <= 3) return true
  return stage === 4 && state.showControls !== true && state.showAlbumArt !== true
}

function showsArt(state, stage) {
  if (simpleMode(state)) return true
  if (state.vertical === true) return false
  if (state.showAlbumArt !== true) return false
  return stage <= 2 || (stage === 4 && state.showControls !== true)
}

function showsPreviousNext(state, stage) {
  return !simpleMode(state) && state.vertical !== true
    && state.showControls === true && stage === 0
}

function showsSeek(state, stage) {
  return showsPreviousNext(state, stage) && state.showSeekControls === true
}

function showsPlayPause(state, stage) {
  if (simpleMode(state)) return false
  if (state.vertical === true) return true
  return state.showControls === true && (stage <= 1 || stage === 4)
}

// How many transport buttons the current stage draws.
function buttonCount(state, stage) {
  return (showsPreviousNext(state, stage) ? 2 : 0)
    + (showsSeek(state, stage) ? 2 : 0)
    + (showsPlayPause(state, stage) ? 1 : 0)
}

// The stage `budget` allows.
function stageFor(budget, state) {
  if (simpleMode(state)) return 0
  if (state.vertical === true) return 0

  var hasLabel = state.hasLabel !== false
  var labelFloor = hasLabel ? state.minimumLabelWidth : 0
  var buttons = state.showControls === true ? (state.showSeekControls === true ? 5 : 3) : 0

  if (budget >= widthFor(state, buttons, state.showAlbumArt === true, hasLabel, labelFloor)) return 0
  if (state.showControls === true
      && budget >= widthFor(state, 1, state.showAlbumArt === true, hasLabel, labelFloor)) return 1
  if (budget >= widthFor(state, 0, state.showAlbumArt === true, hasLabel, labelFloor)) return 2
  if (budget >= widthFor(state, 0, false, hasLabel, labelFloor)) return 3
  var fallback = widthFor(state, state.showControls === true ? 1 : 0,
    state.showControls !== true && state.showAlbumArt === true,
    state.showControls !== true && state.showAlbumArt !== true && hasLabel, 1)
  if (budget >= fallback) return 4
  return budget >= minimalHitWidth(state) ? 4 : HIDDEN_STAGE
}

// Width the label may take at `stage`.
function effectiveLabelWidth(state, stage) {
  if (!showsLabel(state, stage)) return 0
  if (state.adaptiveLayout !== true) return state.preferredLabelWidth

  var fixed = widthFor(state, buttonCount(state, stage), showsArt(state, stage), true, 0)
  return Math.max(0, Math.min(state.preferredLabelWidth,
    Math.floor(state.adaptiveWidthBudget - fixed)))
}

// Whole-widget width for the current state.
function width(state, stage) {
  if (state.vertical === true) return state.barSize
  if (simpleMode(state)) return albumOnlyWidth(state)

  var desired = widthFor(state, buttonCount(state, stage), showsArt(state, stage),
    showsLabel(state, stage), effectiveLabelWidth(state, stage))
  if (state.adaptiveLayout !== true) return desired
  return Math.min(desired, state.adaptiveWidthBudget)
}

if (typeof module !== "undefined") {
  module.exports = {
    HIDDEN_STAGE: HIDDEN_STAGE,
    albumOnlyWidth: albumOnlyWidth,
    minimalHitWidth: minimalHitWidth,
    widthFor: widthFor,
    simpleMode: simpleMode,
    stageFor: stageFor,
    showsLabel: showsLabel,
    showsArt: showsArt,
    showsPreviousNext: showsPreviousNext,
    showsSeek: showsSeek,
    showsPlayPause: showsPlayPause,
    buttonCount: buttonCount,
    effectiveLabelWidth: effectiveLabelWidth,
    width: width
  }
}
