import QtQuick
import QtTest
import "../Clicks.js" as Clicks

TestCase {
  name: "Clicks"

  function test_rightButtonTogglesPlaybackEverywhere() {
    compare(Clicks.actionFor(Clicks.RIGHT, "art"), Clicks.PLAY_PAUSE)
    compare(Clicks.actionFor(Clicks.RIGHT, "label"), Clicks.PLAY_PAUSE)
    compare(Clicks.actionFor(Clicks.RIGHT, "transport"), Clicks.PLAY_PAUSE)
  }

  function test_leftButtonOpensNowPlaying() {
    compare(Clicks.actionFor(Clicks.LEFT, "art"), Clicks.INFO)
    compare(Clicks.actionFor(Clicks.LEFT, "label"), Clicks.INFO)
  }

  function test_leftButtonOnTransportTriggersTheButton() {
    compare(Clicks.actionFor(Clicks.LEFT, "transport"), Clicks.TRIGGER)
  }

  function test_middleButtonSkipsBack() {
    compare(Clicks.actionFor(Clicks.MIDDLE, "art"), Clicks.PREVIOUS)
    compare(Clicks.actionFor(Clicks.MIDDLE, "label"), Clicks.PREVIOUS)
    compare(Clicks.actionFor(Clicks.MIDDLE, "transport"), Clicks.NONE)
  }

  function test_unknownSurfaceAndButtonDoNothing() {
    compare(Clicks.actionFor(Clicks.LEFT, "elsewhere"), Clicks.NONE)
    compare(Clicks.actionFor(Clicks.MIDDLE, "elsewhere"), Clicks.NONE)
    compare(Clicks.actionFor(8, "art"), Clicks.NONE)
    compare(Clicks.actionFor(undefined, "art"), Clicks.NONE)
  }

  function test_rightButtonNeverOpensThePanel() {
    var surfaces = ["art", "label", "transport", "elsewhere", ""]
    for (var i = 0; i < surfaces.length; i++)
      verify(Clicks.actionFor(Clicks.RIGHT, surfaces[i]) !== Clicks.INFO,
        "right click on " + surfaces[i])
  }
}
