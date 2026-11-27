import QtQuick
import QtTest
import "../Player.js" as Player

TestCase {
  name: "Player"

  function player(identity, desktopEntry) {
    return { identity: identity, desktopEntry: desktopEntry }
  }

  function test_identityWinsOverDesktopEntry() {
    compare(Player.label(player("Spotify", "spotify")), "Spotify")
    compare(Player.label(player("Mozilla firefox", "firefox")), "Mozilla firefox")
  }

  function test_fallsBackToDesktopEntry() {
    compare(Player.label(player("", "mpv")), "mpv")
    compare(Player.label(player(undefined, "mpv")), "mpv")
  }

  function test_trimsWhitespace() {
    compare(Player.label(player("  mpv  ", "")), "mpv")
    compare(Player.label(player("   ", "vlc")), "vlc")
  }

  function test_emptyWhenThePlayerHasNoName() {
    compare(Player.label(player("", "")), "")
    compare(Player.label(player(null, null)), "")
    compare(Player.label(null), "")
    compare(Player.label(undefined), "")
  }

  function test_stateText() {
    compare(Player.stateText(true), "Playing")
    compare(Player.stateText(false), "Paused")
  }

  function test_summary() {
    compare(Player.summary(player("Mozilla firefox", ""), true),
      "Mozilla firefox · Playing")
    compare(Player.summary(player("spotify", ""), false), "spotify · Paused")
  }

  function test_summaryIsEmptyWithoutAName() {
    compare(Player.summary(player("", ""), true), "")
    compare(Player.summary(null, false), "")
  }
}
