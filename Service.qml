import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Player.js" as Player
import "Transport.js" as Transport

Item {
  id: root

  property string preferredPlayerKey: ""
  property bool ipcEnabled: true

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var sourcePlayers: availablePlayers()
  readonly property var activePlayer: chooseActivePlayer()
  readonly property bool hasMedia: activePlayer !== null
    && activePlayer.playbackState !== MprisPlaybackState.Stopped
    && hasTrack(activePlayer)
  readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
  // Who is playing, for the now-playing panel: the player's own name, or ""
  // when it exposes none. See Player.js.
  readonly property string playerName: Player.label(activePlayer)
  readonly property string playerState: activePlayer ? Player.stateText(activePlayer.isPlaying) : ""
  // `Mozilla firefox · Playing`, or "" when the player is unnamed.
  readonly property string playerSummary: activePlayer ? Player.summary(activePlayer, activePlayer.isPlaying) : ""
  // What the bar's Image loads: never the player's URL itself, which Qt would
  // download without a size limit. See Artwork.qml.
  readonly property string artSource: artwork.source

  function playerKey(player) {
    if (!player) return ""
    return String(player.dbusName || player.desktopEntry || player.identity || player.uniqueId || "")
  }

  function isProxy(player) {
    if (!player) return false
    var dbus = String(player.dbusName || "").toLowerCase()
    var desktop = String(player.desktopEntry || "").toLowerCase()
    return dbus.indexOf("playerctld") !== -1 || desktop === "playerctld"
  }

  function hasTrack(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.trackArtUrl))
  }

  function isAvailable(player) {
    return !!(player && player.playbackState !== MprisPlaybackState.Stopped && hasTrack(player))
  }

  function availablePlayers() {
    var result = []
    for (var i = 0; i < players.length; i++) {
      if (isAvailable(players[i])) result.push(players[i])
    }
    return result
  }

  function findPreferred() {
    if (!preferredPlayerKey) return null
    for (var i = 0; i < sourcePlayers.length; i++) {
      if (playerKey(sourcePlayers[i]) === preferredPlayerKey) return sourcePlayers[i]
    }
    return null
  }

  function firstMatching(playing, proxy) {
    for (var i = 0; i < sourcePlayers.length; i++) {
      var player = sourcePlayers[i]
      if (!!player.isPlaying === playing && isProxy(player) === proxy) return player
    }
    return null
  }

  function chooseActivePlayer() {
    var preferred = findPreferred()
    if (preferred && preferred.isPlaying) return preferred

    return firstMatching(true, false)
      || firstMatching(true, true)
      || preferred
      || firstMatching(false, false)
      || firstMatching(false, true)
      || null
  }

  function remember(player) {
    var key = playerKey(player)
    if (!key) return
    console.debug("[media-play-control.player] remembered", key)
    preferredPlayerKey = key
  }

  function playPause() {
    var player = activePlayer
    if (!player) return false

    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
    else return false

    remember(player)
    return true
  }

  function previous() {
    var player = activePlayer
    if (!player || !player.canGoPrevious) return false
    player.previous()
    remember(player)
    return true
  }

  function next() {
    var player = activePlayer
    if (!player || !player.canGoNext) return false
    player.next()
    remember(player)
    return true
  }

  function seekBy(seconds) {
    var player = activePlayer
    if (!Transport.seekBy(player, seconds)) return false
    remember(player)
    return true
  }

  // Absolute seek for the popup's progress bar and for IPC. SetPosition is
  // tried first because it lands exactly on the requested time without
  // depending on the player's own reading, which is what browsers lose after
  // their first seek. A relative Seek is only the fallback: it is measured from
  // whatever position the player reports, so a stale reading moves the track
  // somewhere else entirely.
  function seekTo(seconds) {
    var player = activePlayer
    if (!player) return false
    if (!Transport.seekable(player)) {
      console.debug("[media-play-control.service] seekTo refused",
        player.canSeek ? "no timeline" : "player cannot seek")
      return false
    }
    if (Transport.seekAbsolute(player, seconds)) {
      console.info("[media-play-control.service] seekTo", seconds, "absolute")
      remember(player)
      return true
    }
    if (typeof player.positionChanged === "function") player.positionChanged()
    var current = Number(player.position)
    if (!Transport.seekTo(player, seconds, current)) {
      console.debug("[media-play-control.service] seekTo refused by Transport",
        "target", seconds, "current", current)
      return false
    }
    console.info("[media-play-control.service] seekTo", seconds, "from", current)
    remember(player)
    return true
  }

  function raisePlayer() {
    var player = activePlayer
    if (!player || !player.canRaise) return false
    player.raise()
    remember(player)
    return true
  }

  function statusObject() {
    var player = activePlayer
    return {
      available: hasMedia,
      playing: !!(player && player.isPlaying),
      player: player ? String(player.identity || player.desktopEntry || player.dbusName || "") : "",
      artist: artist,
      title: title,
      album: album,
      artUrl: artUrl,
      canGoPrevious: !!(player && player.canGoPrevious),
      canGoNext: !!(player && player.canGoNext),
      canSeek: !!(player && player.canSeek),
      hasProgress: Transport.hasProgress(player),
      position: player && player.positionSupported ? Number(player.position) : 0,
      length: player && player.lengthSupported ? Number(player.length) : 0
    }
  }

  Artwork {
    id: artwork
    url: root.artUrl
    // Plain http covers have always shown here, so they still do.
    allowHttp: true
  }

  IpcHandler {
    enabled: root.ipcEnabled
    target: "dealenx.media-play-control"

    function status(): string {
      return JSON.stringify(root.statusObject())
    }

    function playPause(): string {
      return root.playPause() ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.previous() ? "ok" : "unhandled"
    }

    function next(): string {
      return root.next() ? "ok" : "unhandled"
    }

    function seekBy(seconds: real): string {
      return root.seekBy(seconds) ? "ok" : "unhandled"
    }

    function seekTo(seconds: real): string {
      return root.seekTo(seconds) ? "ok" : "unhandled"
    }

    function raise(): string {
      return root.raisePlayer() ? "ok" : "unhandled"
    }
  }
}
