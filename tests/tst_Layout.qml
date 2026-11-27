import QtQuick
import QtTest
import "../Layout.js" as Layout

TestCase {
  name: "Layout"

  // Geometry of the real widget at Style defaults, plus the switches each
  // case needs. Tests override one key at a time.
  function base(overrides) {
    var state = {
      horizontalPadding: 12,
      buttonWidth: 20,
      contentSpacing: 4,
      artLabelGap: 2,
      artSize: 18,
      barSize: 26,
      preferredLabelWidth: 200,
      minimumLabelWidth: 80,
      adaptiveWidthBudget: 100000,
      hasLabel: true,
      hasMedia: true,
      showAlbumArt: true,
      showControls: true,
      showSeekControls: false,
      adaptiveLayout: true,
      albumArtOnly: false,
      vertical: false
    }
    for (var key in overrides) state[key] = overrides[key]
    return state
  }

  function fullWidth(state) {
    // prev + play + next + art + label floor, four gaps plus the art/label one
    return 12 + 3 * 20 + 18 + 80 + 4 * 4 + 2
  }

  function test_albumArtOnlyKeepsArtworkWidthAtAnyBudget() {
    var state = base({ albumArtOnly: true })
    compare(Layout.stageFor(2000, state), 0)
    compare(Layout.stageFor(40, state), 0)
    compare(Layout.width(state, 0), 12 + 18)
    compare(Layout.showsArt(state, 0), true)
    compare(Layout.showsLabel(state, 0), false)
    compare(Layout.showsPlayPause(state, 0), false)
    compare(Layout.showsPreviousNext(state, 0), false)
  }

  function test_idleKeepsArtworkWidthWithoutControls() {
    var state = base({ hasMedia: false, hideWhenIdle: false })
    compare(Layout.stageFor(2000, state), 0)
    compare(Layout.width(state, 0), 12 + 18)
    compare(Layout.showsArt(state, 0), true)
    compare(Layout.showsLabel(state, 0), false)
    compare(Layout.showsPlayPause(state, 0), false)
  }

  function test_fullLadder() {
    var state = base()
    var floor = Layout.minimalHitWidth(state)
    compare(Layout.stageFor(2000, state), 0)
    compare(Layout.showsPreviousNext(state, 0), true)
    compare(Layout.stageFor(fullWidth(state) - 1, state), 1)
    compare(Layout.showsPreviousNext(state, 1), false)
    compare(Layout.showsPlayPause(state, 1), true)
    compare(Layout.showsLabel(state, 1), true)
    compare(Layout.showsArt(state, 2), true)
    compare(Layout.showsLabel(state, 3), true)
    compare(Layout.showsPlayPause(state, 4), true)
    compare(Layout.stageFor(floor - 1, state), Layout.HIDDEN_STAGE)
  }

  function test_seekButtonsNeedTheWidestStage() {
    var plain = base()
    var seeking = base({ showSeekControls: true })
    compare(Layout.showsSeek(plain, 0), false)
    compare(Layout.showsSeek(seeking, 0), true)
    compare(Layout.showsSeek(seeking, 1), false)
    verify(Layout.stageFor(300, seeking) <= Layout.stageFor(300, plain))
  }

  function test_verticalBarShowsControlsOnly() {
    var state = base({ vertical: true })
    compare(Layout.stageFor(1000, state), 0)
    compare(Layout.width(state, 0), 26)
    compare(Layout.showsLabel(state, 0), false)
    compare(Layout.showsArt(state, 0), false)
    compare(Layout.showsPlayPause(state, 0), true)
  }

  function test_verticalAlbumArtOnlyShowsTheArtwork() {
    var state = base({ vertical: true, albumArtOnly: true })
    compare(Layout.stageFor(1000, state), 0)
    compare(Layout.width(state, 0), 26)
    compare(Layout.showsArt(state, 0), true)
    compare(Layout.showsPlayPause(state, 0), false)
  }

  function test_labelWidthNeverGoesNegative() {
    var state = base({ adaptiveWidthBudget: 20 })
    compare(Layout.effectiveLabelWidth(state, 3) >= 0, true)
    compare(Layout.effectiveLabelWidth(state, Layout.HIDDEN_STAGE), 0)
  }

  function test_widthNeverExceedsTheBudget() {
    for (var budget = 40; budget <= 1200; budget += 37) {
      var state = base({ adaptiveWidthBudget: budget })
      var stage = Layout.stageFor(budget, state)
      if (stage === Layout.HIDDEN_STAGE) continue
      verify(Layout.width(state, stage) <= budget,
        "budget " + budget + " stage " + stage + " width " + Layout.width(state, stage))
    }
  }

  function test_artToLabelGapOnlyAppliesWhenBothShow() {
    var both = base()
    var coverOnly = base({ hasLabel: false })
    var labelOnly = base({ showAlbumArt: false })
    compare(Layout.widthFor(both, 0, true, true, 100), 12 + 18 + 100 + 4 + 2)
    compare(Layout.widthFor(coverOnly, 0, true, false, 100), 12 + 18)
    compare(Layout.widthFor(labelOnly, 0, false, true, 100), 12 + 100)
    // The old three-argument arithmetic stays valid for callers without the key.
    compare(Layout.widthFor(base({ artLabelGap: undefined }), 0, true, true, 100),
      12 + 18 + 100 + 4)
  }

  function test_missingLabelLeavesNoGap() {
    var state = base({ hasLabel: false, adaptiveWidthBudget: 100000 })
    compare(Layout.showsLabel(state, 0), false)
    compare(Layout.effectiveLabelWidth(state, 0), 0)
  }
}
