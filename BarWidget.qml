import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarGeometry.js" as BarGeometry
import "Clicks.js" as Clicks
import "Layout.js" as Layout
import "TextLimit.js" as TextLimit
import "Transport.js" as Transport

BarWidget {
  id: root
  moduleName: "dealenx.media-play-control"

  readonly property var mediaService: serviceSource.service
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  // Playback state, read once so the artwork's highlight and its spin agree
  // on what "playing" means.
  readonly property bool playing: !!activePlayer && activePlayer.isPlaying === true
  readonly property bool hasMedia: mediaService ? mediaService.hasMedia : false
  readonly property string title: mediaService ? mediaService.title : ""
  readonly property string artist: mediaService ? mediaService.artist : ""
  readonly property string album: mediaService ? mediaService.album : ""
  readonly property string artSource: mediaService ? String(mediaService.artSource || "") : ""
  readonly property string playerName: mediaService ? String(mediaService.playerName || "") : ""
  readonly property string playerSummary: mediaService ? String(mediaService.playerSummary || "") : ""
  readonly property bool showArtist: setting("showArtist", true) === true
  readonly property bool showControls: setting("showControls", true) === true
  readonly property bool showSeekControls: setting("showSeekControls", false) === true
  readonly property bool showAlbumArt: setting("showAlbumArt", true) === true
  readonly property bool adaptiveLayout: setting("adaptiveLayout", true) === true
  readonly property bool albumArtOnly: setting("albumArtOnly", false) === true
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property int maxCharacters: Math.max(10, Math.min(120, Number(setting("maxCharacters", 48))))
  readonly property int maxLabelWidth: Math.max(80, Number(setting("maxLabelWidth", 300)))
  readonly property int configuredArtSize: Math.max(12, Number(setting("albumArtSize", 18)))
  readonly property int artSize: Math.min(configuredArtSize, Math.max(12, barSize - Style.space(6)))
  readonly property string fullDisplayText: {
    if (showArtist && artist && title) return artist + " — " + title
    return title || artist
  }
  readonly property string displayText: TextLimit.limitCharacters(fullDisplayText, maxCharacters)
  readonly property string tooltipText: {
    var text = hasMedia ? fullDisplayText : "Nothing is playing"
    if (album) text += (text ? "\n" : "") + album
    if (!vertical) {
      text += (text ? "\n" : "")
        + "Left: now playing · Right: play/pause\n"
        + "Middle: previous · Wheel: previous/next"
    }
    return text
  }
  readonly property int buttonWidth: Style.space(20)
  readonly property int contentSpacing: Style.space(4)
  readonly property int horizontalPadding: Style.space(12)
  readonly property int preferredLabelWidth: Math.min(maxLabelWidth, Math.ceil(label.implicitWidth))
  readonly property int minimumAdaptiveLabelWidth: Math.min(preferredLabelWidth, Style.space(80))
  property real adaptiveWidthBudget: 0
  // Everything Layout.js needs to pick a stage and a width, in one plain
  // object, so the ladder lives in a testable module instead of bindings.
  readonly property var layoutState: ({
    horizontalPadding: horizontalPadding,
    buttonWidth: buttonWidth,
    contentSpacing: contentSpacing,
    artSize: artSize,
    barSize: barSize,
    preferredLabelWidth: preferredLabelWidth,
    minimumLabelWidth: minimumAdaptiveLabelWidth,
    adaptiveWidthBudget: adaptiveWidthBudget,
    hasLabel: displayText !== "",
    hasMedia: hasMedia,
    showAlbumArt: showAlbumArt,
    showControls: showControls,
    showSeekControls: showSeekControls,
    adaptiveLayout: adaptiveLayout,
    albumArtOnly: albumArtOnly,
    vertical: vertical
  })
  readonly property int adaptiveStage: Layout.stageFor(adaptiveWidthBudget, layoutState)
  readonly property bool previousNextVisible: Layout.showsPreviousNext(layoutState, adaptiveStage)
  readonly property bool seekVisible: Layout.showsSeek(layoutState, adaptiveStage)
  readonly property bool playPauseVisible: Layout.showsPlayPause(layoutState, adaptiveStage)
  readonly property bool albumArtVisible: Layout.showsArt(layoutState, adaptiveStage)
  readonly property bool labelVisible: Layout.showsLabel(layoutState, adaptiveStage)
  readonly property int effectiveLabelWidth: Layout.effectiveLabelWidth(layoutState, adaptiveStage)
  readonly property bool hiddenByLayout: adaptiveStage === Layout.HIDDEN_STAGE

  property bool settingsOpen: false
  property string page: "nowPlaying"
  // Set while a click is still in flight after the popup closed itself: the
  // focus grab clears on the same click that lands on the widget, so the card
  // is already closed by the time MouseArea runs. Without this, the click
  // would close and immediately reopen it, and a second click would look like
  // it does nothing.
  property bool justClosed: false
  readonly property bool opened: settingsOpen

  // ---- Timeline -----------------------------------------------------------
  // Quickshell caches MPRIS position and only re-reads it when asked, so the
  // popup keeps its own playhead: a mirror that ticks while the card is open
  // and re-anchors whenever the player reports a jump. All of it lives here
  // rather than in Service.qml because it must stop the moment the card closes.
  readonly property var timelinePlayer: activePlayer
  // Seconds, like everything else the widget reads from MprisPlayer: MPRIS on
  // the bus speaks microseconds, Quickshell divides that for us.
  readonly property real reportedLength: timelinePlayer && timelinePlayer.lengthSupported === true
    ? Number(timelinePlayer.length) : 0
  // Firefox's MPRIS extension drops `mpris:length` from the metadata after a
  // seek and only publishes it again on the next track change, which would make
  // the progress bar vanish mid-song. The last length the same track reported is
  // kept for exactly that case; a new track clears it.
  property real rememberedLength: 0
  property string rememberedLengthTrackKey: ""
  readonly property real trackLength: reportedLength > 0 ? reportedLength : rememberedLength
  // Same condition as Transport.hasProgress, but against the length this widget
  // is actually drawing with, including the remembered one.
  readonly property bool showProgress: !!(timelinePlayer
    && timelinePlayer.positionSupported === true
    && trackLength > 0)
  readonly property bool seekable: !!(timelinePlayer && timelinePlayer.canSeek === true && showProgress)
  readonly property string timelineState: timelinePlayer
    ? (timelinePlayer.isPlaying ? "playing" : "paused") : "idle"
  // Observable so the capture can prove the playhead stops with the card
  // instead of ticking every second behind a closed popup.
  readonly property bool timelineTicking: timelineTimer.running
  property real livePosition: 0
  property real anchorSeconds: 0
  property real anchorMillis: 0
  property real lastReportedSeconds: -1
  // Set right after a seek: the player may need a moment before it reports the
  // new position, and the mirror must not snap back to the old one meanwhile.
  property real seekGraceUntil: 0
  property bool scrubbing: false
  property string timelineTrackKey: ""
  // How many readings in a row the player reported as position 0 while
  // claiming to play. Browsers do this after a seek (Firefox's MPRIS
  // extension never recovers until the track changes), and a mirror that
  // obeys them turns into a dead slider pinned at the start. Two consecutive
  // zeroes with playback running and time passing mean the player's clock is
  // broken, not that the track restarted.
  property int zeroReadings: 0

  // ---- Artwork ------------------------------------------------------------
  // The bar hides itself for a fullscreen window; a spin nobody can see is
  // wasted frames. The trusted bar exposes `barHidden` directly, while the
  // restricted PluginBarApi reaches the same flag through `shell.bar`.
  readonly property bool barHidden: {
    if (!bar) return false
    if (bar.barHidden !== undefined) return bar.barHidden === true
    return !!(bar.shell && bar.shell.bar && bar.shell.bar.barHidden === true)
  }
  // The cover turns only while it is on screen and the track is playing.
  // `Style.reduceMotion` is the shell-wide switch behind
  // `omarchy toggle animations`.
  readonly property bool artSpinning: playing && visible && albumArtVisible
    && !barHidden && !Style.reduceMotion
  // The turning item itself, for the capture host: reading `disc.rotation`
  // through a bound property would re-evaluate a binding on every frame.
  readonly property var artDisc: disc
  // Only a decoded cover gets the disc treatment: the circle, the ground, the
  // ring, the halo. With no cover the slot is just the accent music note.
  readonly property bool coverShown: artSource !== "" && cover.status === Image.Ready
  // Why the spin is or is not running, for the log line below. Reads the
  // first gate that fails, in the same order as `artSpinning`. A function,
  // not a property: inside `onArtSpinningChanged` a sibling binding that
  // depends on `playing` still holds the previous value, which logged every
  // transition with the reason it had just left.
  function artSpinReason() {
    if (!playing) return "paused"
    if (!visible || !albumArtVisible) return "hidden"
    if (barHidden) return "bar hidden"
    if (Style.reduceMotion) return "reduced motion"
    return "playing"
  }

  // The widget stays on the bar with no media so its slot does not jump
  // around; "Hide when nothing plays" brings back the upstream behavior.
  visible: (hasMedia || !hideWhenIdle) && !hiddenByLayout
  implicitWidth: {
    if (!visible) return 0
    return Layout.width(layoutState, adaptiveStage)
  }
  implicitHeight: barSize
  clip: !vertical && adaptiveLayout && !hiddenByLayout

  Behavior on implicitWidth {
    enabled: !root.adaptiveLayout || root.vertical
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  // Long enough to cover the click that cleared the popup's focus grab, short
  // enough that a deliberate second click still opens the panel.
  Timer {
    id: closeGuard
    interval: 220
    onTriggered: root.justClosed = false
  }

  Timer {
    interval: 250
    // Kept running while the layout hides the widget: it has to keep
    // measuring the gap to notice when space comes back.
    running: (root.hasMedia || !root.hideWhenIdle) && !root.vertical && root.adaptiveLayout
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAdaptiveWidthBudget()
  }

  onBarChanged: Qt.callLater(refreshAdaptiveWidthBudget)

  ServiceSource {
    id: serviceSource
    bar: root.bar
    serviceId: root.moduleName
    // The shell's own instance keeps the IPC target.
    fallback: Component { Service { ipcEnabled: false } }
  }

  Component.onCompleted: {
    console.debug("[media-play-control] moduleName:", root.moduleName)
    console.debug("[media-play-control.art]", "cover", root.artSource ? "present" : "missing",
      "size", root.artSize)
  }

  onArtSpinningChanged: console.debug("[media-play-control.art]", "spin",
    artSpinning ? "on" : "off", "angle", artDisc ? Math.round(artDisc.rotation) : 0,
    "reason", artSpinReason())

  function previous() {
    if (mediaService) mediaService.previous()
  }

  function playPause() {
    if (mediaService) mediaService.playPause()
  }

  function next() {
    if (mediaService) mediaService.next()
  }

  function raisePlayer() {
    if (mediaService) mediaService.raisePlayer()
  }

  function seekBy(seconds) {
    if (mediaService) mediaService.seekBy(seconds)
  }

  // ---- Timeline -----------------------------------------------------------

  function timelineKey(player) {
    if (!player) return ""
    return String(player.trackTitle || "") + "\u0000" + String(player.trackArtist || "")
  }

  // Re-anchor the mirror on a fresh reading from the player. Called on a track
  // change, on the first tick, and whenever the reported position jumps (the
  // user seeked elsewhere, the player skipped, the app restarted the track).
  function anchorTimeline(reported, now) {
    anchorSeconds = reported
    anchorMillis = now
    livePosition = reported
    lastReportedSeconds = reported
  }

  // How far the mirror has travelled since its anchor. A zero anchor (the
  // reset before the first reading) would otherwise measure from the epoch.
  function elapsedSinceAnchor(now) {
    if (!anchorMillis) {
      anchorMillis = now
      return 0
    }
    return Math.max(0, now - anchorMillis) / 1000
  }

  // One tick of the popup's playhead. Skipped while the user drags the slider,
  // and while a seek is still settling so the old position cannot win.
  function syncTimeline(reason) {
    var player = timelinePlayer
    if (!player || !showProgress) return
    if (scrubbing) return
    var now = Date.now()
    if (now < seekGraceUntil) return

    // Ask Quickshell to re-read the player; the property is cached otherwise.
    if (typeof player.positionChanged === "function") player.positionChanged()
    var reported = Number(player.position)
    if (!isFinite(reported)) return

    var key = timelineKey(player)
    var trackChanged = key !== timelineTrackKey

    // A player that claims to be playing and reports 0 has almost always lost
    // its clock, usually right after a seek (Firefox's MPRIS extension keeps
    // reporting 0 until the track changes). Adopting that reading would pin the
    // slider to the start and, worse, re-anchor on it every tick, so it is
    // skipped and the mirror keeps running on its own anchors. The exception is
    // a genuine restart of the same track (repeat-one): there the estimate is
    // already at the end, and the reading is the truth.
    if (reported <= 0 && player.isPlaying && !trackChanged) {
      var estimate = anchorSeconds + elapsedSinceAnchor(now)
      var restarting = trackLength > 0 && estimate >= trackLength * 0.9
      if (!restarting) {
        zeroReadings = zeroReadings + 1
        if (zeroReadings === 2) {
          console.debug("[media-play-control.timeline] player reports no position",
            "pos", livePosition.toFixed(1), "len", trackLength)
        }
        livePosition = Math.min(trackLength, estimate)
        return
      }
    }
    zeroReadings = 0

    var jumped = lastReportedSeconds >= 0 && Math.abs(reported - lastReportedSeconds) > 1.5

    if (trackChanged || lastReportedSeconds < 0 || jumped) {
      if (trackChanged) {
        timelineTrackKey = key
        console.debug("[media-play-control.timeline] track", root.title || "(untitled)",
          "len", root.trackLength, "seekable", root.seekable)
      }
      anchorTimeline(reported, now)
      return
    }

    if (player.isPlaying) livePosition = Math.min(trackLength, anchorSeconds + elapsedSinceAnchor(now))
    else anchorTimeline(reported, now)
    lastReportedSeconds = reported
    if (reason === "manual") {
      console.debug("[media-play-control.timeline]", "pos", livePosition.toFixed(1),
        "len", trackLength, "state", timelineState)
    }
  }

  // Where the mirror thinks the playhead is, derived only from the anchor. The
  // displayed `livePosition` cannot answer this: a drag writes the pointer's
  // position into it, so asking it how far the track has actually come would
  // read back the very value the drag just set.
  function clockPosition() {
    return anchorSeconds + elapsedSinceAnchor(Date.now())
  }

  // The player's own position, except when it is lying. Quickshell caches the
  // property, so it is re-read first; a reading of exactly 0 while the player
  // claims to be playing and the track has already gone past the start means
  // the clock is gone (see syncTimeline), and the mirror is the better
  // estimate.
  function trustedPosition() {
    var player = timelinePlayer
    var estimate = clockPosition()
    if (!player || player.positionSupported !== true) return estimate
    if (typeof player.positionChanged === "function") player.positionChanged()
    var reported = Number(player.position)
    if (!isFinite(reported) || reported < 0) return estimate
    if (reported === 0 && player.isPlaying && estimate > 1) return estimate
    return reported
  }

  // Absolute seek from the slider. The player takes an offset, so it is
  // computed from the player's own position read at this instant, never from
  // the mirrored playhead: the mirror is already overwritten by the drag (or
  // by the wheel, which emits moved then released without ever dragging), and
  // after a track change it still holds the previous track's position.
  // Reading fresh also accounts for playback that continued while the pointer
  // was down, so the release lands exactly where the pointer was.
  // After it, the mirror waits out the grace period before trusting a fresh
  // reading: some players (Spotify on Linux) advertise seeking and then ignore
  // the position write.
  function seekTo(seconds) {
    var player = timelinePlayer
    var target = Math.max(0, Math.min(trackLength, Number(seconds)))
    if (!isFinite(target)) return false
    // Absolute first: SetPosition needs no guess about where the player is, so
    // the track lands exactly on the value under the pointer. A relative Seek
    // is measured from an estimate, which is wrong by every millisecond the
    // estimate is wrong, and is the whole problem for browsers whose reported
    // position cannot be trusted.
    var base = clockPosition()
    var sent = Transport.seekAbsolute(player, target)
    if (!sent) sent = Transport.seekTo(player, target, trustedPosition())
    if (!sent) {
      console.debug("[media-play-control.timeline] seek refused",
        seekable ? "bad target" : "player cannot seek",
        "target", target, "base", base, "live", livePosition)
      return false
    }
    livePosition = target
    anchorSeconds = target
    anchorMillis = Date.now()
    lastReportedSeconds = target
    // The player is about to report a position it may not honour at all; let
    // the mirror carry the truth for the grace period instead of adopting it.
    zeroReadings = 0
    seekGraceUntil = Date.now() + 1200
    timelineTimer.restart()
    console.debug("[media-play-control.timeline] seek", target.toFixed(1),
      "from", base.toFixed(1), "len", trackLength)
    return true
  }

  function timelineSnapshot() {
    return {
      showProgress: showProgress,
      seekable: seekable,
      position: livePosition,
      length: trackLength,
      fraction: Transport.progressFraction(livePosition, trackLength),
      elapsed: Transport.formatTime(livePosition),
      total: Transport.formatTime(trackLength),
      state: timelineState
    }
  }

  // A new track is a new timeline. Dropping the playhead at once keeps the
  // slider from sitting past the new track's end (the old track may have been
  // far longer) until the next tick, and the forced re-anchor below means the
  // first tick adopts the player's own position instead of interpolating from
  // the discarded one.
  function resetTimeline() {
    lastReportedSeconds = -1
    livePosition = 0
    anchorSeconds = 0
    anchorMillis = 0
    seekGraceUntil = 0
    // A new track owns its own key: the remembered length is claimed or
    // dropped here, so a player that hides the length mid-song keeps its bar
    // and a different song never inherits the previous duration.
    rememberLength()
    if (settingsOpen && page === "nowPlaying") {
      console.debug("[media-play-control.timeline] reset", root.title || "(untitled)",
        "len", trackLength, "seekable", seekable)
      timelineTimer.restart()
    }
  }
  onTitleChanged: resetTimeline()
  onArtistChanged: resetTimeline()

  // The length is remembered against the track it belongs to. A player that
  // stops publishing `mpris:length` mid-song (Firefox after a seek) keeps its
  // progress bar, while a new track never inherits the previous one's duration:
  // the first reading that carries a new track identity only claims the key,
  // and the length is adopted from a later reading of that same track.
  function rememberLength() {
    var key = timelineKey(timelinePlayer)
    if (key === "") {
      rememberedLength = 0
      rememberedLengthTrackKey = ""
      return
    }
    if (key !== rememberedLengthTrackKey) {
      rememberedLengthTrackKey = key
      rememberedLength = 0
      return
    }
    if (reportedLength > 0) rememberedLength = reportedLength
  }
  onReportedLengthChanged: rememberLength()

  // The playhead only exists while the card shows the now-playing screen with
  // a usable timeline; a closed popup must not keep a timer awake.
  Timer {
    id: timelineTimer
    interval: 1000
    repeat: true
    running: root.settingsOpen && root.page === "nowPlaying" && root.showProgress
    triggeredOnStart: true
    onTriggered: root.syncTimeline()
  }

  // Restart rather than let a stale tick land after the screen changed: the
  // timer has to re-anchor on the new player at once.
  onSettingsOpenChanged: if (settingsOpen) timelineTimer.restart()
  onPageChanged: if (page === "nowPlaying" && settingsOpen) timelineTimer.restart()
  onActivePlayerChanged: {
    timelineTrackKey = ""
    rememberLength()
    console.debug("[media-play-control.timeline] player", timelinePlayer ? timelinePlayer.identity : "none",
      "len", root.trackLength, "seekable", root.seekable)
    resetTimeline()
  }

  // Omarchy currently anchors its left, center, and right bar groups
  // independently. Measure the span left between this group and the other
  // groups so this widget can volunteer its own width before they overlap.
  function calculateAdaptiveWidthBudget() {
    if (vertical || !adaptiveLayout) return 100000

    var window = null
    try {
      window = root.QsWindow.window
    } catch (e) {
    }
    return BarGeometry.widthBudget(root, window ? window.contentItem : null,
      Style.space(8), Style.space(8))
  }

  function refreshAdaptiveWidthBudget() {
    var next = calculateAdaptiveWidthBudget()
    if (Math.abs(next - adaptiveWidthBudget) >= 1) {
      adaptiveWidthBudget = next
      console.debug("[media-play-control.layout] stage", adaptiveStage,
        "visible", visible, "budget", adaptiveWidthBudget)
    }
  }

  function close() {
    if (settingsOpen) {
      justClosed = true
      closeGuard.restart()
    }
    settingsOpen = false
  }

  function open() {
    showNowPlaying()
    settingsOpen = true
  }

  function toggle() {
    if (settingsOpen) {
      close()
      return
    }
    // The click that dismissed the card by clearing its focus grab also
    // reaches this widget. Swallow that one and open on the next click.
    if (justClosed) return
    open()
  }

  // Two screens share one card: "nowPlaying" and "settings". The settings icon
  // and the back arrow flip between them; opening always starts at the
  // now-playing screen.
  function showNowPlaying() {
    if (page === "nowPlaying") return
    page = "nowPlaying"
    console.debug("[media-play-control.popup] page:", page)
  }

  function showSettings() {
    if (page === "settings") return
    page = "settings"
    console.debug("[media-play-control.popup] page:", page)
  }

  function previewSetting(key, value) {
    var next = Object.assign({}, settings || {})
    next[key] = value
    settings = next
  }

  function saveSetting(key, value) {
    previewSetting(key, value)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  function wheelAction(wheel) {
    if (wheel.angleDelta.y > 0) previous()
    else if (wheel.angleDelta.y < 0) next()
  }

  // One dispatcher for every clickable surface, so the button table lives in
  // Clicks.js instead of three copies of if/else in the QML.
  function handleClick(button, surface) {
    var action = Clicks.actionFor(button, surface)
    if (action === Clicks.NONE) return false
    console.debug("[media-play-control.clicks]", surface, button, action)
    if (action === Clicks.PLAY_PAUSE) playPause()
    else if (action === Clicks.PREVIOUS) previous()
    // Left click is a toggle: the first click opens the now-playing screen,
    // the next one closes it again, as every other bar panel behaves.
    else if (action === Clicks.INFO) toggle()
    return true
  }

  Row {
    id: contents
    anchors.centerIn: parent
    // Full bar height, not the artwork's: the artwork is 18px in a 26px bar,
    // and a pointer in those four pixels above or below should still count as
    // being on the widget.
    height: root.barSize
    spacing: Style.space(4)

    TransportButton {
      iconText: "󰒮"
      tooltip: "Previous"
      enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
      visible: root.previousNextVisible
      onTriggered: root.previous()
    }

    TransportButton {
      iconText: "󰴪"
      tooltip: "Back " + Transport.SEEK_STEP + " seconds"
      enabled: !!(root.activePlayer && root.activePlayer.canSeek)
      visible: root.seekVisible
      onTriggered: root.seekBy(-Transport.SEEK_STEP)
    }

    TransportButton {
      iconText: root.playing ? "󰏤" : "󰐊"
      tooltip: root.playing ? "Pause" : "Play"
      enabled: !!(root.activePlayer && (root.activePlayer.canPlay || root.activePlayer.canPause || root.activePlayer.canTogglePlaying))
      visible: root.playPauseVisible
      onTriggered: root.playPause()
    }

    TransportButton {
      iconText: "󰵱"
      tooltip: "Forward " + Transport.SEEK_STEP + " seconds"
      enabled: !!(root.activePlayer && root.activePlayer.canSeek)
      visible: root.seekVisible
      onTriggered: root.seekBy(Transport.SEEK_STEP)
    }

    TransportButton {
      iconText: "󰒭"
      tooltip: "Next"
      enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
      visible: root.previousNextVisible
      onTriggered: root.next()
    }

    Item {
      id: artContainer
      // The clickable column is the bar's full height; the artwork inside it
      // stays artSize and centred, so the pointer does not have to land on an
      // 18px square in a 26px bar.
      width: root.artSize
      height: parent.height
      visible: root.albumArtVisible

      Item {
        id: artVisual
        width: root.artSize
        height: root.artSize
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        // A soft accent halo behind the disc, only while the track plays. It
        // reaches 3px past the artwork, one pixel short of the row's 4px gap
        // on either side, so it never touches its neighbours, and the 2px ring
        // sits inside it, leaving a band of haze around the bright edge.
        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          antialiasing: true
          radius: width / 2
          color: Commons.Util.alpha(Commons.Color.accent, 0.18)
          visible: root.coverShown && root.playing
        }

        // The disc's own ground: what shows through a cover with transparent
        // pixels. Nothing at all without a cover, which is the bare note.
        Rectangle {
          anchors.fill: parent
          antialiasing: true
          radius: width / 2
          visible: root.coverShown
          color: root.bar ? Style.normalFillFor(root.bar.barForeground, Commons.Color.accent) : "transparent"
        }

        // The cover, cut to a circle by a mask rather than by clipping a
        // square: a rotating square inside a clipped circle loses its corners,
        // while a mask keeps every turn inside the round edge. The mask is a
        // sibling of the masked layer, which is how Omarchy's own toast and
        // avatar photographs get their shape.
        Item {
          anchors.fill: parent
          layer.enabled: root.coverShown
          // Render the layer at device resolution. Without this Qt rasterizes
          // an 18px artwork and scales the result, which stair-steps the round
          // edge on every scaled display.
          layer.textureSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
            Math.ceil(height * Screen.devicePixelRatio))
          layer.smooth: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: discMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          Item {
            // A full turn every 12 seconds: fast enough to read as playing,
            // slow enough not to distract beside the bar's clock.
            id: disc
            anchors.fill: parent
            transformOrigin: Item.Center
            RotationAnimation on rotation {
              running: true
              paused: !root.artSpinning
              from: 0
              to: 360
              duration: Style.duration(12000)
              loops: Animation.Infinite
              easing.type: Easing.Linear
              direction: RotationAnimation.Clockwise
            }

            Image {
              id: cover
              anchors.fill: parent
              source: root.artSource
              sourceSize.width: Math.round(width * Screen.devicePixelRatio)
              sourceSize.height: Math.round(height * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              smooth: true
              onStatusChanged: if (status === Image.Error)
                console.debug("[media-play-control.art]", "cover failed to load")
            }

            // No cover at all, or one Qt could not decode: the accent music
            // note is the whole artwork — no ground, no ring, no halo, no
            // circle. It sits inside the turning item, so it turns at exactly
            // the cover's speed while the track plays and freezes on pause.
            OpticalGlyph {
              anchors.fill: parent
              visible: root.artSource === "" || cover.status === Image.Error
              text: "󰝚"
              color: Commons.Util.alpha(Commons.Color.accent, root.playing ? 1.0 : 0.55)
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              fontSize: Style.bar.iconFont
              paintedSize: Math.min(Style.bar.iconSize, root.artSize - Style.space(4))
            }
          }
        }

        // The mask itself: a black circle the layer above reads as its alpha.
        // Antialiased, or the disc's edge stair-steps at the bar's own 18px
        // and every scale above it.
        Rectangle {
          id: discMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          layer.textureSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
            Math.ceil(height * Screen.devicePixelRatio))
          antialiasing: true
          radius: width / 2
          color: "black"
        }

        // The highlight: a two-pixel ring of the theme accent, brighter while
        // the track plays and dimmed when it does not. It sits outside the
        // masked layer, so it never turns with the cover, and it grows
        // outwards by its own width, so the ring never eats into the cover.
        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(2)
          radius: width / 2
          antialiasing: true
          visible: root.coverShown
          color: "transparent"
          border.width: Style.space(2)
          border.color: Commons.Util.alpha(Commons.Color.accent, root.playing ? 0.55 : 0.28)
        }
      }

      // The bar's press router targets this item, which is what gives the
      // column the pointing cursor; the MouseArea below stays for the wheel
      // and the tooltip.
      PressTarget {
        anchors.fill: parent
        surface: "art"
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) { root.handleClick(mouse.button, "art") }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(artContainer, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(artContainer)
      }
    }

    Item {
      id: labelClip
      width: root.effectiveLabelWidth
      // Full bar height for the same reason as the artwork: the label's line
      // box is shorter than the bar.
      height: parent.height
      anchors.verticalCenter: parent.verticalCenter
      visible: root.labelVisible
      clip: true

      Text {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        textFormat: Text.PlainText
        color: root.bar ? root.bar.barForeground : Commons.Color.foreground
        opacity: root.playing ? 0.92 : 0.58
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight

        Behavior on opacity { NumberAnimation { duration: 140 } }
      }

      PressTarget {
        anchors.fill: parent
        surface: "label"
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) { root.handleClick(mouse.button, "label") }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(labelClip, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(labelClip)
      }
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: fittedContentWidth(Style.space(330))
    // Each screen sizes the card to its own content. Quickshell re-anchors the
    // popup when its size changes, so a taller settings screen grows away from
    // the bar instead of overlapping it at the bottom or the side.
    contentHeight: root.page === "settings"
      ? fittedContentHeight(settingsColumn.implicitHeight)
      : fittedContentHeight(infoColumn.implicitHeight)

    Item {
      anchors.fill: parent

      Column {
        id: infoColumn
        width: parent.width
        spacing: Style.space(10)
        visible: root.page === "nowPlaying"

        Item {
          width: parent.width
          implicitHeight: Math.max(nowPlayingHeading.implicitHeight, settingsButton.implicitHeight)

          Text {
            id: nowPlayingHeading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "NOW PLAYING"
            color: root.bar ? root.bar.foreground : Commons.Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒓"
            tooltipText: "Settings"
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.showSettings()
          }
        }

        // Cover beside the text, as the panel concept shows it: a 72px square
        // is enough to recognise a record at a glance and leaves the rest of
        // the card for the words.
        Row {
          width: parent.width
          spacing: Style.space(10)

          Item {
            id: coverFrame
            width: Math.min(Style.space(72), parent.width * 0.4)
            height: width

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              color: root.bar ? Style.normalFillFor(root.bar.barForeground, Commons.Color.accent) : "transparent"
            }

            Image {
              id: panelCover
              anchors.fill: parent
              anchors.margins: 1
              source: root.artSource
              sourceSize.width: Math.round(width * Screen.devicePixelRatio)
              sourceSize.height: Math.round(height * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              smooth: true
            }

            OpticalGlyph {
              anchors.fill: parent
              visible: root.artSource === "" || panelCover.status === Image.Error
              text: "󰝚"
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              fontSize: Style.font.display
              paintedSize: Math.min(width, height) * 0.4
            }
          }

          Column {
            id: detailsColumn
            width: parent.width - coverFrame.width - parent.spacing
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              width: parent.width
              text: root.hasMedia ? root.title : "Nothing is playing"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            // Why there is no track: a player with no metadata, or no player at
            // all. The two look the same on the bar but need different advice.
            // A track without an artist is not a missing track: a local file or
            // a stream has no artist tag, and telling the user to start
            // playback while it is already playing is wrong.
            Text {
              width: parent.width
              visible: !root.hasMedia
              text: root.activePlayer
                ? "Start playback in " + (root.playerName || "your player") + "."
                : "Start a media player or press play in one."
              textFormat: Text.PlainText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            Text {
              width: parent.width
              visible: root.artist !== ""
              text: root.artist
              textFormat: Text.PlainText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.25) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: root.album !== ""
              text: root.album
              textFormat: Text.PlainText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            // Who is playing. Hidden whole when the player exposes no name, so
            // the separator never shows up on its own.
            Text {
              width: parent.width
              visible: root.playerSummary !== ""
              text: root.playerSummary
              textFormat: Text.PlainText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // Transport, duplicated from the bar on purpose: the card is opened
        // precisely so the buttons can be hit without aiming at a 20px target.
        // Every button follows the player's own capabilities, so a browser that
        // cannot skip shows two dead buttons instead of nothing at all.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          visible: root.hasMedia

          Button {
            iconText: "󰒮"
            tooltipText: "Previous"
            iconSize: Style.font.iconLarge
            enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.previous()
          }

          Button {
            iconText: root.playing ? "󰏤" : "󰐊"
            tooltipText: root.playing ? "Pause" : "Play"
            iconSize: Style.font.iconLarge
            enabled: !!(root.activePlayer
              && (root.activePlayer.canPlay || root.activePlayer.canPause
                || root.activePlayer.canTogglePlaying))
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.playPause()
          }

          Button {
            iconText: "󰒭"
            tooltipText: "Next"
            iconSize: Style.font.iconLarge
            enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.next()
          }
        }

        // Progress. Hidden whole when the player reports no length: a bar that
        // sits at zero against a `0:00` total reads as broken, not as idle.
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: root.showProgress

          PanelSlider {
            id: progressSlider
            // Found by name in the capture host, which has other sliders on
            // the hidden settings screen.
            objectName: "progressSlider"
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: Math.max(1, root.trackLength)
            // PanelSlider uses `step` for wheel notches only; dragging maps the
            // pointer position directly. A fraction of the track would make one
            // notch a single second on a long song.
            step: 5
            value: root.livePosition
            // A player that cannot seek still shows where it is; the slider
            // just refuses to move.
            enabled: root.seekable
            opacity: root.seekable ? 1.0 : 0.55
            onDraggingChanged: root.scrubbing = dragging
            onMoved: function(value) { root.livePosition = value }
            onReleased: function(value) { root.seekTo(value) }
          }

          Item {
            width: parent.width
            implicitHeight: elapsedLabel.implicitHeight

            Text {
              id: elapsedLabel
              anchors.left: parent.left
              text: Transport.formatTime(root.livePosition)
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: totalLabel
              anchors.right: parent.right
              text: Transport.formatTime(root.trackLength)
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator {
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        }

        Button {
          width: parent.width
          text: "Open Media"
          bordered: true
          enabled: !!(root.activePlayer && root.activePlayer.canRaise)
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
          accent: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: function() {
            if (!root.activePlayer || !root.activePlayer.canRaise) {
              console.info("[media-play-control.popup] open media unavailable",
                mediaService ? mediaService.playerName : "")
              return
            }
            root.raisePlayer()
            root.close()
          }
        }
      }

      Flickable {
        id: settingsScroll
        anchors.fill: parent
        visible: root.page === "settings"
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: settingsColumn
          width: settingsScroll.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(settingsHeading.implicitHeight, backButton.implicitHeight)

            PanelActionButton {
              id: backButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰁍"
              tooltipText: "Back to now playing"
              foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.showNowPlaying()
            }

            Text {
              id: settingsHeading
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "SETTINGS"
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Toggle {
            width: parent.width
            label: "Adapt to available space"
            description: "Shrink this widget before bar sections overlap."
            checked: root.adaptiveLayout
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("adaptiveLayout", !root.adaptiveLayout)
          }

          Toggle {
            width: parent.width
            label: "Show transport controls"
            description: "Previous, play/pause, and next buttons."
            checked: root.showControls
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("showControls", !root.showControls)
          }

          Toggle {
            width: parent.width
            label: "Show seek buttons"
            description: "Back and forward " + Transport.SEEK_STEP + " seconds, with the transport controls."
            checked: root.showSeekControls
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("showSeekControls", !root.showSeekControls)
          }

          Toggle {
            width: parent.width
            label: "Show album art"
            description: "Keep artwork beside the track label when space allows."
            checked: root.showAlbumArt
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("showAlbumArt", !root.showAlbumArt)
          }

          Toggle {
            width: parent.width
            label: "Show artist"
            description: "Place the artist before the track title."
            checked: root.showArtist
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("showArtist", !root.showArtist)
          }

          Toggle {
            width: parent.width
            label: "Album art only"
            description: "Show only the album artwork in the bar, without label or controls."
            checked: root.albumArtOnly
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("albumArtOnly", !root.albumArtOnly)
          }

          Toggle {
            width: parent.width
            label: "Hide when nothing plays"
            description: "Hide the widget from the bar when no player has media."
            checked: root.hideWhenIdle
            foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.saveSetting("hideWhenIdle", !root.hideWhenIdle)
          }

          SettingSlider {
            label: "Maximum characters"
            suffix: ""
            minimum: 10
            maximum: 120
            step: 1
            currentValue: Number(root.setting("maxCharacters", 48))
            onPreviewed: function(value) { root.previewSetting("maxCharacters", Math.round(value)) }
            onCommitted: function(value) { root.saveSetting("maxCharacters", Math.round(value)) }
          }

          SettingSlider {
            label: "Maximum label width"
            suffix: "px"
            minimum: 80
            maximum: 600
            step: 10
            currentValue: Number(root.setting("maxLabelWidth", 300))
            onPreviewed: function(value) { root.previewSetting("maxLabelWidth", Math.round(value / 10) * 10) }
            onCommitted: function(value) { root.saveSetting("maxLabelWidth", Math.round(value / 10) * 10) }
          }

          SettingSlider {
            label: "Album art size"
            suffix: "px"
            minimum: 12
            maximum: 22
            step: 1
            currentValue: Number(root.setting("albumArtSize", 18))
            onPreviewed: function(value) { root.previewSetting("albumArtSize", Math.round(value)) }
            onCommitted: function(value) { root.saveSetting("albumArtSize", Math.round(value)) }
          }
        }
      }
    }
  }

  // The bar lays its own MouseArea over every widget slot and routes presses
  // from there, so what a widget's own MouseArea says about the cursor never
  // reaches the screen: Bar.moduleClickTargetAt looks for a target with
  // triggerPress() and otherwise paints the arrow cursor. This item gives a
  // region of the widget that contract, exactly as Ui's WidgetButton does.
  component PressTarget: Item {
    id: pressRegion

    // Which surface of the widget this region stands for: "art", "label" or
    // "transport".
    property string surface: "art"
    // Optional per-button handling; when null the surface table decides.
    property var pressHandler: null

    function triggerPress(pressedButton) {
      if (pressHandler) pressHandler(pressedButton)
      else root.handleClick(pressedButton, surface)
    }

    function syncRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget)
        registeredBar.unregisterClickTarget(pressRegion)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget)
        registeredBar.registerClickTarget(pressRegion)
    }

    property var registeredBar: null
    visible: parent ? parent.visible : true
    Component.onCompleted: syncRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(pressRegion)

    // The widget can be moved between bars and monitors; its click target has
    // to follow the bar that is drawing it now.
    Connections {
      target: root
      function onBarChanged() { pressRegion.syncRegistration() }
    }
  }

  component TransportButton: Item {
    id: button

    required property string iconText
    property string tooltip: ""
    signal triggered()

    implicitWidth: Style.space(20)
    // The whole bar column is the hit area, not just the icon's ink box.
    implicitHeight: parent ? parent.height : root.barSize
    opacity: enabled ? 1.0 : 0.32

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: mouse.containsMouse && button.enabled
        ? Style.hoverFillFor(root.bar ? root.bar.barForeground : Commons.Color.foreground, Commons.Color.accent)
        : "transparent"
    }

    // A Text centered in the button centers its line box, and each glyph
    // sits differently in it. Center the painted glyph at the bar's icon
    // size instead, as BarIconButton does.
    OpticalGlyph {
      anchors.fill: parent
      text: button.iconText
      color: root.bar ? root.bar.barForeground : Commons.Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      fontSize: Style.bar.iconFont
      paintedSize: Style.bar.iconSize
    }

    PressTarget {
      anchors.fill: parent
      surface: "transport"
      pressHandler: function(pressedButton) {
        var action = Clicks.actionFor(pressedButton, "transport")
        if (action === Clicks.PLAY_PAUSE) root.playPause()
        else if (action === Clicks.TRIGGER && button.enabled) button.triggered()
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: true
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(event) {
        var action = Clicks.actionFor(event.button, "transport")
        if (action === Clicks.PLAY_PAUSE) root.playPause()
        else if (action === Clicks.TRIGGER && button.enabled) {
          console.debug("[media-play-control.clicks]", "transport", event.button, action)
          button.triggered()
        }
      }
      onWheel: function(wheel) { root.wheelAction(wheel) }
      onEntered: if (root.bar && button.tooltip) root.bar.showTooltip(button, button.tooltip)
      onExited: if (root.bar) root.bar.hideTooltip(button)
    }
  }

  component SettingSlider: Column {
    id: sliderSetting

    required property string label
    property string suffix: ""
    required property real minimum
    required property real maximum
    required property real step
    required property real currentValue

    signal previewed(real value)
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(settingLabel.implicitHeight, settingValue.implicitHeight)

      Text {
        id: settingLabel
        anchors.left: parent.left
        text: sliderSetting.label
        color: root.bar ? root.bar.foreground : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        id: settingValue
        anchors.right: parent.right
        text: Math.round(slider.dragging ? slider.liveValue : sliderSetting.currentValue) + sliderSetting.suffix
        color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: sliderSetting.step
      integer: true
      value: sliderSetting.currentValue
      onMoved: function(value) { sliderSetting.previewed(value) }
      onReleased: function(value) { sliderSetting.committed(value) }
    }
  }
}
