.pragma library

// Seconds the seek buttons move the playhead.
var SEEK_STEP = 10

// Seek only players that advertise it, and only by a real, nonzero offset.
// Returns whether the seek was sent; the player clamps at either end.
function seekBy(player, seconds) {
  var offset = Number(seconds)
  if (!player || !player.canSeek || !isFinite(offset) || offset === 0) return false
  player.seek(offset)
  return true
}

// A timeline needs both a playhead and a total to place it on. Browsers can
// report Playing with position 0 and no length at all, so both capabilities
// and a positive finite length are required before a progress bar means
// anything.
function hasProgress(player) {
  if (!player || player.positionSupported !== true || player.lengthSupported !== true) return false
  var total = Number(player.length)
  return isFinite(total) && total > 0
}

// Fraction of the track already played, clamped so a stale position cannot
// paint outside the slider's track.
function progressFraction(position, length) {
  var total = Number(length)
  if (!isFinite(total) || total <= 0) return 0
  var elapsed = Number(position)
  if (!isFinite(elapsed) || elapsed <= 0) return 0
  return Math.max(0, Math.min(1, elapsed / total))
}

// Whether the slider can be dragged. MPRIS players advertise CanSeek far more
// often than they can actually move: Spotify says yes and ignores the write,
// so a timeline must exist before a seek is even offered.
function seekable(player) {
  return !!player && player.canSeek === true && hasProgress(player)
}

// Move the playhead to an absolute position by sending the difference from
// where the caller believes it is. Returns whether the seek was sent.
function seekTo(player, targetSeconds, currentSeconds) {
  var target = Number(targetSeconds)
  var current = Number(currentSeconds)
  if (!isFinite(target) || !isFinite(current)) return false
  return seekBy(player, target - current)
}

// Jump to an absolute position through MPRIS SetPosition, which needs no
// estimate of where the player currently is. This is the only correct way to
// seek a player whose reported position cannot be trusted: a relative Seek is
// measured from a guess, so every millisecond of that guess is an error in
// where the track actually lands. Returns whether the jump was sent.
function seekAbsolute(player, seconds) {
  var target = Number(seconds)
  if (!player || !player.canSeek || player.positionSupported !== true) return false
  if (!isFinite(target) || target < 0) return false
  player.position = target
  return true
}

// `1:12` under an hour, `1:01:12` above it, and `0:00` for anything the player
// failed to report rather than a bare `NaN`.
function formatTime(seconds) {
  var total = Math.floor(Number(seconds))
  if (!isFinite(total) || total < 0) return "0:00"

  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  var padded = secs < 10 ? "0" + secs : String(secs)

  if (hours > 0) {
    var paddedMinutes = minutes < 10 ? "0" + minutes : String(minutes)
    return hours + ":" + paddedMinutes + ":" + padded
  }
  return minutes + ":" + padded
}

if (typeof module !== "undefined") {
  module.exports = {
    SEEK_STEP: SEEK_STEP,
    seekBy: seekBy,
    hasProgress: hasProgress,
    progressFraction: progressFraction,
    seekable: seekable,
    seekTo: seekTo,
    seekAbsolute: seekAbsolute,
    formatTime: formatTime
  }
}
