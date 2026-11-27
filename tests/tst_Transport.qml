import QtQuick
import QtTest
import "../Transport.js" as Transport

TestCase {
  name: "Transport"

  function player(canSeek) {
    return { canSeek: canSeek, offsets: [], seek: function(offset) { this.offsets.push(offset) } }
  }

  function timedPlayer(options) {
    var player = {
      canSeek: options.canSeek === true,
      positionSupported: options.positionSupported !== false,
      lengthSupported: options.lengthSupported !== false,
      length: options.length === undefined ? 208 : options.length,
      offsets: [],
      seek: function(offset) { this.offsets.push(offset) }
    }
    return player
  }

  function test_seeksPlayersThatAdvertiseIt() {
    var subject = player(true)
    verify(Transport.seekBy(subject, -Transport.SEEK_STEP))
    verify(Transport.seekBy(subject, Transport.SEEK_STEP))
    compare(subject.offsets, [-10, 10])
  }

  function test_leavesOtherPlayersAlone() {
    var subject = player(false)
    verify(!Transport.seekBy(subject, 10))
    compare(subject.offsets, [])
    verify(!Transport.seekBy(null, 10))
  }

  function test_ignoresOffsetsThatMoveNothing() {
    var subject = player(true)
    verify(!Transport.seekBy(subject, 0))
    verify(!Transport.seekBy(subject, NaN))
    verify(!Transport.seekBy(subject, Infinity))
    verify(!Transport.seekBy(subject, "ten"))
    compare(subject.offsets, [])
    // IPC arguments can arrive as text.
    verify(Transport.seekBy(subject, "-10"))
    compare(subject.offsets, [-10])
  }

  function test_formatsMinutesAndHours() {
    compare(Transport.formatTime(0), "0:00")
    compare(Transport.formatTime(72), "1:12")
    compare(Transport.formatTime(208), "3:28")
    compare(Transport.formatTime(3599), "59:59")
    compare(Transport.formatTime(3600), "1:00:00")
    compare(Transport.formatTime(3661), "1:01:01")
    compare(Transport.formatTime(72.9), "1:12")
  }

  function test_formatsMissingTimeAsZero() {
    compare(Transport.formatTime(NaN), "0:00")
    compare(Transport.formatTime(-5), "0:00")
    compare(Transport.formatTime(undefined), "0:00")
    compare(Transport.formatTime(null), "0:00")
    // IPC arguments can arrive as text.
    compare(Transport.formatTime("72"), "1:12")
  }

  function test_hasProgressNeedsCapabilitiesAndLength() {
    verify(Transport.hasProgress(timedPlayer({})))
    verify(!Transport.hasProgress(null))
    verify(!Transport.hasProgress(timedPlayer({ lengthSupported: false })))
    verify(!Transport.hasProgress(timedPlayer({ positionSupported: false })))
    verify(!Transport.hasProgress(timedPlayer({ length: 0 })))
    verify(!Transport.hasProgress(timedPlayer({ length: NaN })))
  }

  function test_progressFractionStaysOnTheTrack() {
    compare(Transport.progressFraction(104, 208), 0.5)
    compare(Transport.progressFraction(208, 208), 1)
    compare(Transport.progressFraction(0, 208), 0)
    compare(Transport.progressFraction(72, 0), 0)
    compare(Transport.progressFraction(300, 208), 1)
    compare(Transport.progressFraction(-3, 208), 0)
    compare(Transport.progressFraction(NaN, 208), 0)
  }

  function test_seekableNeedsCanSeekAndATimeline() {
    verify(Transport.seekable(timedPlayer({ canSeek: true })))
    verify(!Transport.seekable(timedPlayer({ canSeek: false })))
    // Spotify-style: advertises seeking without revealing a length.
    verify(!Transport.seekable(timedPlayer({ canSeek: true, lengthSupported: false })))
    verify(!Transport.seekable(null))
  }

  function test_seekToSendsTheOffsetFromTheReportedPosition() {
    var subject = timedPlayer({ canSeek: true })
    verify(Transport.seekTo(subject, 100, 72))
    verify(Transport.seekTo(subject, 20, 72))
    compare(subject.offsets, [28, -52])
  }

  function test_seekToRefusesWhatSeekByRefuses() {
    var seekless = timedPlayer({ canSeek: false })
    verify(!Transport.seekTo(seekless, 100, 72))
    compare(seekless.offsets, [])

    var subject = timedPlayer({ canSeek: true })
    verify(!Transport.seekTo(subject, 72, 72))
    verify(!Transport.seekTo(subject, NaN, 72))
    compare(subject.offsets, [])
    verify(!Transport.seekTo(null, 100, 72))
  }

  // A relative Seek is measured from an estimate of where the player is, so
  // every millisecond of that estimate is an error in where the track lands.
  // SetPosition needs no estimate at all.
  function absolutePlayer(options) {
    var player = timedPlayer(options)
    player.absolute = []
    var offsets = player.offsets
    player.seek = function(offset) { offsets.push(offset) }
    Object.defineProperty(player, "position", {
      get: function() { return 0 },
      set: function(value) { player.absolute.push(value) },
      configurable: true
    })
    return player
  }

  function test_seekAbsoluteWritesTheExactTarget() {
    var subject = absolutePlayer({ canSeek: true })
    verify(Transport.seekAbsolute(subject, 170))
    verify(Transport.seekAbsolute(subject, 30))
    compare(subject.absolute, [170, 30])
    // No relative offset was sent: absolute seeking must not depend on any
    // reading of the player's own position.
    compare(subject.offsets, [])
  }

  function test_seekAbsoluteRefusesImpossibleJumps() {
    verify(!Transport.seekAbsolute(absolutePlayer({ canSeek: false }), 10))
    verify(!Transport.seekAbsolute(absolutePlayer({ canSeek: true, positionSupported: false }), 10))
    verify(!Transport.seekAbsolute(absolutePlayer({ canSeek: true }), NaN))
    verify(!Transport.seekAbsolute(absolutePlayer({ canSeek: true }), -1))
    verify(!Transport.seekAbsolute(null, 10))
  }
}
