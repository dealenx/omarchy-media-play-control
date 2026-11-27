.pragma library

// How the playing source is named in the widget's panels, kept free of QML
// types so the rules can be tested on their own.
//
// Players differ in which name they expose: Spotify is `spotify` in both
// identity and desktop entry, `mpv` usually only in the desktop entry, and a
// browser-backed player may expose neither. The first non-empty one wins.

function label(player) {
  if (!player) return ""
  var identity = trim(player.identity)
  if (identity !== "") return identity
  return trim(player.desktopEntry)
}

function trim(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function stateText(isPlaying) {
  return isPlaying ? "Playing" : "Paused"
}

// `Mozilla firefox · Playing`, or "" when the player is unnamed: a bare
// separator with a state would read as broken metadata.
function summary(player, isPlaying) {
  var name = label(player)
  if (name === "") return ""
  return name + " · " + stateText(isPlaying)
}

if (typeof module !== "undefined") {
  module.exports = {
    label: label,
    stateText: stateText,
    summary: summary
  }
}
