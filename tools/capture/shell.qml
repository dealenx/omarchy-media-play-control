// Isolated screenshot host: the production bar widget and Omarchy's own Ui
// kit, fed synthetic now-playing fixtures. Run by capture.py.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

ShellRoot {
  id: host

  readonly property string pluginDir: Quickshell.env("MPRIS_PLUGIN")
  readonly property string outputDir: Quickshell.env("MPRIS_OUTPUT")
  readonly property bool composing: Quickshell.env("MPRIS_MODE") === "compose"
  readonly property string coverUrl: "file://" + outputDir + "/cover.png"
  property bool coverReady: false

  Component.onCompleted: Style.cornerRadius = 10

  // Self-drawn abstract album cover (no real artwork).
  FloatingWindow {
    visible: !host.composing
    implicitWidth: 96; implicitHeight: 96
    color: "transparent"
    Item {
      id: cover
      width: 96; height: 96
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "#f6b26b" }
          GradientStop { position: 0.55; color: "#d0603d" }
          GradientStop { position: 1.0; color: "#3a1f3d" }
        }
      }
      Rectangle { x: 18; y: 14; width: 46; height: 46; radius: 23; color: "#fde9c8"; opacity: 0.9 }
      Rectangle { x: -10; y: 62; width: 120; height: 14; rotation: -8; color: "#2a1630"; opacity: 0.75 }
      Rectangle { x: -10; y: 78; width: 120; height: 30; rotation: -8; color: "#1b0f20" }
    }
  }

  component FakeShell: QtObject {
    property var service: null
    function serviceFor(id) { return id === "dealenx.media-play-control" ? service : null }
  }

  component Api: PluginBarApi {
    id: api
    position: Quickshell.env("MPRIS_BAR_POSITION") || "top"
    pluginId: "dealenx.media-play-control"
    moduleName: "dealenx.media-play-control"
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    background: Commons.Color.bar.background
    urgent: Commons.Color.bar.active
    fontFamily: Style.font.family
    barSize: Style.bar.sizeHorizontal
    foregroundAnimationEnabled: false
    _requestPopout: function(owner) { activePopout = owner }
    _releasePopout: function(owner) { if (activePopout === owner) activePopout = null }
    // The bar's real registerClickTarget keeps the widget's own items; here
    // the strip owns the list, so it is reached through the closure below.
    _registerClickTarget: function(target) { api.noteClickTarget(api, target, true) }
    _unregisterClickTarget: function(target) { api.noteClickTarget(api, target, false) }

    // Set by BarStrip so registration lands on the strip's own list.
    property var clickTargetOwner: null

    function noteClickTarget(self, target, adding) {
      var owner = self.clickTargetOwner
      if (!owner) return
      var at = owner.clickTargets.indexOf(target)
      if (adding && at === -1) owner.clickTargets.push(target)
      else if (!adding && at !== -1) owner.clickTargets.splice(at, 1)
    }
  }

  // A slot shaped like Bar.qml's ModuleSlot (region + activeItem), which is
  // what the widget's adaptive layout measures.
  component Slot: Item {
    property string region: "right"
    property Item activeItem: null
    width: activeItem && activeItem.visible ? activeItem.implicitWidth : 0
    height: Style.bar.sizeHorizontal
  }

  // Stand-ins for the neighbouring built-in modules, drawn with the bar's
  // font and colors. Only the media widget is the plugin.
  component Glyphs: Row {
    property alias model: repeater.model
    property real dim: 1
    spacing: Style.space(12)
    leftPadding: Style.space(6)
    rightPadding: Style.space(6)
    height: Style.bar.sizeHorizontal
    Repeater {
      id: repeater
      Text {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.text
        opacity: modelData.dim ? 0.45 : 1
        color: Commons.Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  component BarStrip: Item {
    id: strip
    property alias widget: widgetLoader.item
    readonly property real clockX: clockSlot.x
    property var service
    property string clock: "Wed 21:40"
    property var clickTargets: []
    readonly property Api api: Api {
      shell: FakeShell { service: strip.service }
      clickTargetOwner: strip
    }
    height: Style.bar.sizeHorizontal

    Rectangle { anchors.fill: parent; color: Commons.Color.bar.background }

    Slot {
      region: "left"
      x: Style.space(8)
      activeItem: children[0]
      Glyphs { model: [{ text: "1" }, { text: "2", dim: true }, { text: "3", dim: true }, { text: "4", dim: true }] }
    }

    Slot {
      id: clockSlot
      region: "center"
      anchors.horizontalCenter: parent.horizontalCenter
      activeItem: children[0]
      Glyphs { model: [{ text: strip.clock }] }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      Slot {
        id: mediaSlot
        Loader {
          id: widgetLoader
          source: "file://" + host.pluginDir + "/BarWidget.qml"
          onLoaded: {
            item.bar = strip.api
            mediaSlot.activeItem = item
          }
        }
      }
      Slot {
        activeItem: children[0]
        Glyphs { model: [{ text: "󰂯" }, { text: "󰤨" }, { text: "󰕾" }, { text: "󰁹" }] }
      }
    }
  }

  FakeService {
    id: playingService
    playing: true
    artist: "Vela Coast"
    title: "Glasswork"
    album: "Low Tide Signals"
    artUrl: host.coverReady ? host.coverUrl : ""
  }

  FakeService {
    id: pausedService
    playing: false
    artist: "Vela Coast"
    title: "Paper Satellites"
    album: "Low Tide Signals"
    artUrl: host.coverReady ? host.coverUrl : ""
  }

  FloatingWindow {
    id: wideWindow
    visible: !host.composing
    implicitWidth: 853; implicitHeight: Style.bar.sizeHorizontal
    color: "transparent"
    BarStrip { id: wide; width: parent.width; service: playingService }
  }

  FloatingWindow {
    id: narrowWindow
    visible: !host.composing
    implicitWidth: 560; implicitHeight: Style.bar.sizeHorizontal
    color: "transparent"
    BarStrip { id: narrow; width: parent.width; service: pausedService; clock: "Thu 08:15" }
  }

  function settingsPopup() {
    var data = wide.widget ? wide.widget.data : []
    for (var i = 0; i < data.length; i++) {
      if (data[i] && typeof data[i].fittedContentWidth === "function") return data[i]
    }
    return null
  }

  // Every MouseArea the widget exposes, with the surface it represents.
  function clickAreas(widget) {
    var found = []
    var stack = [widget]
    while (stack.length > 0) {
      var item = stack.pop()
      if (!item) continue
      if (item.acceptedButtons !== undefined && item.cursorShape !== undefined
          && item.onClicked !== undefined) found.push(item)
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return found
  }

  function hitHeights(widget) {
    var areas = clickAreas(widget)
    var out = []
    for (var i = 0; i < areas.length; i++) out.push(Math.round(areas[i].height))
    return out
  }

  function hitCursors(widget) {
    var areas = clickAreas(widget)
    var out = []
    for (var i = 0; i < areas.length; i++) out.push(areas[i].cursorShape === Qt.PointingHandCursor)
    return out
  }

  function state(strip) {
    var w = strip.widget
    return {
      visible: w.visible, stage: w.adaptiveStage, width: w.implicitWidth,
      budget: w.adaptiveWidthBudget, stripWidth: strip.width,
      label: w.displayText, labelWidth: w.effectiveLabelWidth,
      previousNext: w.previousNextVisible, playPause: w.playPauseVisible,
      art: w.albumArtVisible, labelVisible: w.labelVisible, opened: w.opened,
      page: w.page, albumOnly: w.albumArtOnly, playerSummary: w.playerSummary,
      showProgress: w.showProgress, seekable: w.seekable,
      // The artwork: a round disc that turns only while the track plays.
      artShape: "circle", artSpinning: w.artSpinning, artAngle: w.artDisc ? Math.round(w.artDisc.rotation) : 0,
      // Hit areas must cover the whole bar column, not just the artwork.
      barSize: w.barSize,
      clickTargets: strip.clickTargets.length,
      clickTargetHeights: strip.clickTargets.map(function(t) { return Math.round(t.height) })
    }
  }

  // Everything the popup's progress row claims, so the capture can assert it
  // instead of trusting a screenshot. The card lives in its own window, so the
  // walk starts at the popup rather than at the bar widget.
  function transportButtons() {
    var popup = settingsPopup()
    var names = ["Previous", "Play", "Pause", "Next"]
    var found = []
    // PopupCard's default property aliases `contentItem` to its holder's
    // children, so this is a list of items, not a single one.
    var holders = popup ? popup.contentItem : []
    var stack = []
    for (var h = 0; h < holders.length; h++) stack.push(holders[h])
    while (stack.length > 0) {
      var item = stack.pop()
      if (!item) continue
      if (item.tooltipText !== undefined && names.indexOf(item.tooltipText) !== -1) {
        found.push({ icon: item.iconText, tooltip: item.tooltipText, enabled: item.enabled })
      }
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return found
  }

  function timeline(widget) {
    var w = widget || wide.widget
    var snap = w.timelineSnapshot()
    return {
      showProgress: snap.showProgress, seekable: snap.seekable,
      position: snap.position, length: snap.length, fraction: snap.fraction,
      elapsed: snap.elapsed, total: snap.total, state: snap.state,
      ticking: w.timelineTicking,
      title: w.title,
      reportedLength: w.reportedLength,
      rememberedLength: w.rememberedLength,
      rememberedKey: w.rememberedLengthTrackKey,
      trackKey: w.timelineKey(w.timelinePlayer),
      seekOffsets: playingService.seekOffsets.slice(),
      absoluteSeeks: playingService.absoluteSeeks.slice(),
      transport: transportButtons()
    }
  }

  // Composition: real captures over Omarchy's Ristretto wallpaper.
  FloatingWindow {
    visible: host.composing
    implicitWidth: 2560; implicitHeight: 1600
    color: "#090503"
    Item {
      id: composition
      width: 2560; height: 1600
      Image {
        anchors.fill: parent
        source: host.composing ? Quickshell.env("MPRIS_WALLPAPER") : ""
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 0.8 }
      }
      Rectangle { anchors.fill: parent; color: "#9e000000" }
      Repeater {
        model: host.composing ? JSON.parse(Quickshell.env("MPRIS_LAYOUT")) : []
        Item {
          id: placed
          required property var modelData
          x: modelData.x; y: modelData.y
          width: modelData.width; height: modelData.height
          layer.enabled: true
          layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowOpacity: 0.65; shadowVerticalOffset: 18 }
          Rectangle {
            id: mask
            anchors.fill: parent
            radius: placed.modelData.radius || 0
            visible: false
            layer.enabled: true
          }
          Image {
            anchors.fill: parent
            source: "file://" + host.outputDir + "/" + placed.modelData.file
            sourceClipRect: placed.modelData.clip ? Qt.rect(placed.modelData.clip[0], placed.modelData.clip[1],
              placed.modelData.clip[2], placed.modelData.clip[3]) : undefined
            smooth: true; mipmap: true
            layer.enabled: !!placed.modelData.radius
            layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "capture"
    function ready(): bool {
      if (host.composing) return true
      return !!wide.widget && !!narrow.widget && !!settingsPopup()
    }
    function drawCover(): bool {
      return cover.grabToImage(result => {
        result.saveToFile(host.outputDir + "/cover.png")
        host.coverReady = true
      })
    }
    function setNarrowWidth(width: int): string {
      // An offscreen window keeps its first size; remap it at the new width.
      narrowWindow.visible = false
      narrowWindow.implicitWidth = width
      narrowWindow.visible = true
      narrow.widget.refreshAdaptiveWidthBudget()
      return JSON.stringify(state(narrow))
    }
    function setWidgetSetting(key: string, value: string): string {
      var settings = { id: wide.widget.moduleName }
      var current = wide.widget.settings || {}
      for (var name in current) if (name !== "id") settings[name] = current[name]
      settings[key] = value === "true" ? true : value === "false" ? false : Number(value)
      wide.widget.settings = settings
      narrow.widget.settings = settings
      wide.widget.refreshAdaptiveWidthBudget()
      narrow.widget.refreshAdaptiveWidthBudget()
      return JSON.stringify(state(wide))
    }
    function setPlaying(value: bool): string {
      playingService.playing = value
      return JSON.stringify({ playing: playingService.playing })
    }
    // The shell-wide switch behind `omarchy toggle animations`; the spin has
    // to obey it like every other animation in the shell.
    function setReduceMotion(value: bool): string {
      Commons.Style.reduceMotion = value
      return JSON.stringify(state(wide))
    }
    function setIdle(): string {
      playingService.title = ""
      playingService.artist = ""
      playingService.artUrl = ""
      return JSON.stringify(state(wide))
    }
    function states(): string {
      return JSON.stringify({ wide: state(wide), narrow: state(narrow), coverStatus: host.coverReady })
    }
    function openSettings(): string {
      wide.widget.open()
      var popup = settingsPopup()
      return JSON.stringify({ opened: wide.widget.opened, popupVisible: popup.visible,
        width: popup.implicitWidth, height: popup.implicitHeight, page: wide.widget.page })
    }
    // Flip what the fake player can do, and report what the popup makes of it.
    // `qs ipc call` passes every argument as text, so the flag is parsed here
    // rather than relying on the bool annotation.
    function setTimeline(position: real, length: real, seekable: string): string {
      playingService.position = position
      playingService.length = length
      playingService.canSeek = seekable === "true"
      playingService.syncPlayer()
      wide.widget.syncTimeline("manual")
      return JSON.stringify(timeline())
    }
    function timelineState(): string {
      return JSON.stringify(timeline())
    }
    // A browser that cannot skip tracks: the buttons stay, disabled.
    function setTransportCapabilities(previous: string, next: string): string {
      playingService.canGoPrevious = previous === "true"
      playingService.canGoNext = next === "true"
      return JSON.stringify(timeline())
    }
    // Drive the release of a drag, as the slider does when the pointer lifts.
    function seekPopup(seconds: real): string {
      wide.widget.seekTo(seconds)
      return JSON.stringify(timeline())
    }
    // Walk the popup for the progress bar, so the capture can drive the real
    // signal sequence instead of calling the widget's seek directly. Matched by
    // objectName: the hidden settings screen carries sliders of the same type.
    function progressSlider() {
      var holders = settingsPopup() ? settingsPopup().contentItem : []
      var stack = []
      for (var h = 0; h < holders.length; h++) stack.push(holders[h])
      while (stack.length > 0) {
        var item = stack.pop()
        if (!item) continue
        if (item.objectName === "progressSlider") return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
      }
      return null
    }
    // A full pointer drag: press, move, release. This is the sequence that
    // hid the offset bug, because the move already writes the target into the
    // playhead before the release computes the seek.
    function dragPopup(seconds: real): string {
      var slider = progressSlider()
      if (!slider) return JSON.stringify({ error: "no slider" })
      var target = Math.max(slider.minimum, Math.min(slider.maximum, seconds))
      slider.dragging = true
      slider.moved(target)
      slider.liveValue = target
      slider.dragging = false
      slider.released(target)
      return JSON.stringify(timeline())
    }
    // A wheel notch: PanelSlider emits moved then released with no drag at all,
    // so the playhead is overwritten before the seek is computed.
    function wheelPopup(): string {
      var slider = progressSlider()
      if (!slider) return JSON.stringify({ error: "no slider" })
      var target = Math.max(slider.minimum,
        Math.min(slider.maximum, slider.liveValue + slider.step))
      slider.liveValue = target
      slider.moved(target)
      slider.released(target)
      return JSON.stringify(timeline())
    }
    // A track change as the player reports it: new metadata, a new length, and
    // a playhead that starts over.
    function changeTrack(title: string, length: real): string {
      // Title first: a player publishes new metadata before the length, and the
      // widget keys its remembered length on the track identity. Setting the
      // length first would let the old key claim the new value.
      playingService.title = title
      playingService.position = 0
      playingService.length = length
      playingService.syncPlayer()
      return JSON.stringify(timeline())
    }
    // A browser whose MPRIS clock dies after a seek: it keeps claiming to play
    // and reports 0 forever, as Firefox does on Linux.
    function breakPlayerClock(): string {
      playingService.positionClockBroken = true
      playingService.syncPlayer()
      wide.widget.syncTimeline("manual")
      return JSON.stringify(timeline())
    }
    function repairPlayerClock(): string {
      playingService.positionClockBroken = false
      playingService.position = 72
      playingService.syncPlayer()
      return JSON.stringify(timeline())
    }
    function showSettingsPage(): string {
      wide.widget.open()
      wide.widget.showSettings()
      var popup = settingsPopup()
      return JSON.stringify({ page: wide.widget.page, popupVisible: popup.visible,
        width: popup.implicitWidth, height: popup.implicitHeight })
    }
    function showNowPlayingPage(): string {
      wide.widget.showNowPlaying()
      return JSON.stringify({ page: wide.widget.page })
    }
    // Closing must stop the playhead too, not just hide the card.
    function closePopup(): string {
      wide.widget.close()
      return JSON.stringify({ page: wide.widget.page, opened: wide.widget.opened,
        ticking: wide.widget.timelineTicking })
    }
    function widgetGeometry(): string {
      var w = wide.widget
      var p = w.mapToItem(null, 0, 0)
      return JSON.stringify({ x: p.x, width: w.width, barWidth: wideWindow.width,
        compactClockX: narrow.clockX })
    }
    function grab(which: string, path: string): string {
      var item = which === "wide" ? wide : which === "narrow" ? narrow
        : which === "settings" || which === "panel"
          ? settingsPopup().contentItem[0].parent.parent : null
      if (!item) return "No item " + which
      return item.grabToImage(result => result.saveToFile(path)) ? "ok" : "Capture failed"
    }
    function grabPreview(path: string): bool {
      return composition.grabToImage(result => result.saveToFile(path))
    }
  }
}
