// Screenshot fixture standing in for Service.qml. It exposes the same
// properties and methods the bar widget reads, with no MPRIS import, so the
// capture host never sees or controls a real media player.
import QtQuick

QtObject {
  id: fixture
  property bool ipcEnabled: false
  property bool playing: true
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""
  // Timeline, in seconds as Quickshell reports it. The capture flips these to
  // prove the popup hides the bar when a player has no length and keeps it
  // visible but frozen when the player cannot seek.
  property real position: 72
  property real length: 208
  property bool canSeek: true
  property bool canGoPrevious: true
  property bool canGoNext: true
  // Set to model a browser whose MPRIS clock dies after a seek: it keeps
  // claiming to play but reports 0 forever, exactly like Firefox on Linux.
  property bool positionClockBroken: false
  // The fixture's cover is already a local file, so there is nothing to fetch.
  readonly property string artSource: artUrl
  readonly property bool hasMedia: title !== "" || artist !== ""
  // The panel's source line, exactly what Service.qml computes from MPRIS.
  readonly property string playerName: "Mozilla firefox"
  readonly property string playerState: playing ? "Playing" : "Paused"
  readonly property string playerSummary: hasMedia ? playerName + " · " + playerState : ""

  // What the widget actually sees. Kept in step with the fixture by
  // `syncPlayer()`, which the capture calls after changing the fixture: a real
  // MprisPlayer pushes its own changes, while this plain object cannot.
  readonly property QtObject activePlayer: QtObject {
    property real position: 0
    readonly property bool isPlaying: fixture.playing
    readonly property bool canGoPrevious: fixture.canGoPrevious
    readonly property bool canGoNext: fixture.canGoNext
    readonly property bool canPlay: true
    readonly property bool canPause: true
    readonly property bool canTogglePlaying: true
    readonly property bool canSeek: fixture.canSeek
    readonly property bool canRaise: true
    readonly property bool positionSupported: true
    readonly property bool lengthSupported: fixture.length > 0
    readonly property real length: fixture.length
    // A real MprisPlayer carries the track identity; the widget keys its
    // remembered length and its timeline on it.
    readonly property string trackTitle: fixture.title
    readonly property string trackArtist: fixture.artist
    // `positionChanged` is the property's own notify signal, which QML lets
    // callers invoke; a real MprisPlayer behaves the same way, and that is how
    // the popup asks for a fresh reading.
    onPositionChanged: {
      // A write from the widget is MPRIS SetPosition: it lands exactly on the
      // requested time and the player adopts it.
      if (fixture.syncing) return
      fixture.position = position
      fixture.absoluteSeeks.push(Number(position))
    }
    function seek(offset) {
      var step = Number(offset)
      fixture.seekOffsets.push(step)
      // Honour the seek like a real player, clamped at both ends, so the
      // capture exercises the same read-back the widget relies on.
      var next = Number(fixture.position) + step
      fixture.position = Math.max(0, Math.min(Number(fixture.length), next))
      fixture.syncPlayer()
    }
  }

  // Publish the fixture's state to the object the widget reads.
  property bool syncing: false
  function syncPlayer() {
    syncing = true
    activePlayer.position = positionClockBroken ? 0 : position
    syncing = false
  }

  property var seekOffsets: []
  property var seekTargets: []
  property var absoluteSeeks: []

  // Publish the starting position so the widget sees it from its first tick.
  Component.onCompleted: syncPlayer()

  function previous() { return false }
  function next() { return false }
  function playPause() { return false }
  function seekBy(seconds) { return false }
  function seekTo(seconds) {
    seekTargets.push(seconds)
    return true
  }
  function raisePlayer() { return false }
}
