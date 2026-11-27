#!/usr/bin/python3
"""Capture the production bar widget with synthetic now-playing data.

Never touches a real media player: Service.qml is replaced by a fixture with
no MPRIS import. Runs fully offscreen with its own HOME and runtime directory.
Refuses a software-rendered capture.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
SCALE = 6
WALLPAPER = "/usr/share/omarchy/themes/ristretto/backgrounds/0-launch.webp"


def wait_for(predicate, description, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError("Timed out: " + description)


def complete_png(path):
    if not path.exists() or path.stat().st_size < 12: return False
    with path.open("rb") as image:
        image.seek(-12, 2)
        return image.read() == b'\x00\x00\x00\x00IEND\xaeB`\x82'


def png_size(path):
    with path.open("rb") as image:
        header = image.read(24)
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def prepare(work):
    home, shell, plugin = (work / name for name in ["home", "shell", "plugin"])
    # A private runtime directory holds only Quickshell's IPC socket; keep its
    # path short enough for a Unix socket.
    runtime = Path(tempfile.mkdtemp(prefix="mpris-", dir=os.environ.get("XDG_RUNTIME_DIR")))
    shell.mkdir()
    plugin.mkdir()
    theme = home / ".local/state/omarchy/current/next-theme"
    theme.mkdir(parents=True)
    shutil.copy("/usr/share/omarchy/themes/ristretto/colors.toml", theme / "colors.toml")
    env = dict(HOME=str(home), PATH="/usr/bin:/bin", LANG="C.UTF-8",
               XDG_RUNTIME_DIR=str(runtime), OMARCHY_PATH="/usr/share/omarchy",
               DISPLAY=os.environ.get("DISPLAY", ":0"))
    if "XAUTHORITY" in os.environ: env["XAUTHORITY"] = os.environ["XAUTHORITY"]
    subprocess.run(["omarchy-theme-set-templates"], env=env, check=True, stdout=subprocess.DEVNULL)
    shutil.copytree(theme, theme.with_name("theme"))
    fonts = home / ".config/fontconfig"
    fonts.mkdir(parents=True)
    (fonts / "fonts.conf").write_text('''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>
<match target="pattern"><test name="family"><string>monospace</string></test>
<edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit></match>
</fontconfig>''')
    for name in ["Commons", "Ui"]:
        shutil.copytree(Path("/usr/share/omarchy/shell") / name, shell / name)
    # Production widget files; the MPRIS service is swapped for the fixture.
    for name in ["BarWidget.qml", "BarGeometry.js", "Clicks.js", "Layout.js",
                 "Player.js", "ServiceSource.qml", "TextLimit.js", "Transport.js"]:
        shutil.copy(ROOT / name, plugin / name)
    shutil.copy(TOOLS / "FakeService.qml", plugin / "Service.qml")
    shutil.copy(TOOLS / "FakeService.qml", shell / "FakeService.qml")
    shutil.copy(TOOLS / "shell.qml", shell / "shell.qml")
    return env, shell, plugin, runtime


def run_host(env, shell, log, body):
    def call(method, *args):
        result = subprocess.run(["qs", "ipc", "-p", str(shell), "call", "--", "capture", method, *map(str, args)],
                                env=env, capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            if method != "ready": print(result.stderr, file=sys.stderr, flush=True)
            return ""
        return result.stdout.strip()
    with log.open("w") as stream:
        proc = subprocess.Popen(["qs", "-p", str(shell)], env=env, stdout=stream, stderr=subprocess.STDOUT)
        try:
            wait_for(lambda: call("ready") == "true", "capture host")
            body(call)
        except Exception:
            print(log.read_text()[-6000:], file=sys.stderr)
            raise
        finally:
            proc.terminate()
            proc.wait(timeout=5)
    text = log.read_text()
    for line in text.splitlines():
        if "OpenGL VENDOR" in line or "OpenGL RENDERER" in line or "WARN" in line or "ERROR" in line:
            print(line, file=sys.stderr)
    renderers = [line for line in text.splitlines() if "OpenGL RENDERER" in line or "RENDERER:" in line]
    if not renderers or any(soft in line for line in renderers for soft in ("llvmpipe", "softpipe", "Software")):
        raise RuntimeError("Capture must use GPU rendering; inspect " + str(log))
    return text


def grab(call, which, path):
    path.unlink(missing_ok=True)
    result = call("grab", which, str(path))
    if result != "ok": raise RuntimeError(which + ": " + result)
    wait_for(lambda: complete_png(path), which)
    print(path, file=sys.stderr, flush=True)


def main():
    with tempfile.TemporaryDirectory(prefix="mpris-capture-", dir=os.environ.get("MPRIS_CAPTURE_TMP")) as work_path:
        work = Path(work_path)
        # Individual captures and logs go to the optional output directory
        # argument, or are discarded with the temporary host.
        output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else work / "captures"
        output.mkdir(parents=True, exist_ok=True)
        env, shell, plugin, runtime = prepare(work)
        try:
            capture_all(work, env, shell, plugin, output)
        finally:
            shutil.rmtree(runtime, ignore_errors=True)


def capture_all(work, env, shell, plugin, output):
    (work / "screen.json").write_text(json.dumps({"screens": [dict(
        name="CAPTURE", x=0, y=0, width=1200 * SCALE, height=800 * SCALE,
        logicalDpi=96, logicalBaseDpi=96, dpr=1)]}))
    env.update(QT_QPA_PLATFORM=f"offscreen:configfile={work / 'screen.json'}",
               QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", QSG_INFO="1",
               QT_SCALE_FACTOR=str(SCALE), MPRIS_PLUGIN=str(plugin), MPRIS_OUTPUT=str(output),
               MPRIS_MODE="capture")
    geometry = {}

    def capture(call):
        assert call("drawCover") == "true"
        wait_for(lambda: complete_png(output / "cover.png"), "cover")
        wait_for(lambda: json.loads(call("states"))["coverStatus"], "cover loaded")
        time.sleep(.5)
        wide = json.loads(call("states"))["wide"]
        assert wide["visible"] and wide["stage"] == 0 and wide["previousNext"] and wide["art"], wide
        # The bar draws the pointing cursor over registered click targets and
        # routes presses to them; a widget that registers none keeps the arrow
        # cursor however its own MouseAreas are configured.
        assert wide["clickTargets"] > 0, wide
        heights = wide["clickTargetHeights"]
        assert heights and all(h >= wide["barSize"] for h in heights), (heights, wide)
        print("click targets", wide["clickTargets"], heights, file=sys.stderr)
        # The artwork is a disc that turns only while the track plays. Sample
        # the angle twice with real time in between: an animation that is
        # merely scheduled shows the same number, a paused one does too.
        assert wide["artShape"] == "circle" and wide["artSpinning"], wide
        first = json.loads(call("states"))["wide"]["artAngle"]
        time.sleep(1.2)
        second = json.loads(call("states"))["wide"]["artAngle"]
        assert second != first, (first, second)
        print("art angle", first, "->", second, file=sys.stderr)
        # Paused, the disc holds the angle it reached instead of snapping back.
        json.loads(call("setPlaying", "false"))
        time.sleep(.2)
        held = json.loads(call("states"))["wide"]
        assert not held["artSpinning"], held
        time.sleep(1.2)
        still = json.loads(call("states"))["wide"]["artAngle"]
        assert still == held["artAngle"], (held["artAngle"], still)
        json.loads(call("setPlaying", "true"))
        # Reduced motion is the shell-wide animation switch; the spin obeys it.
        off = json.loads(call("setReduceMotion", "true"))
        assert not off["artSpinning"], off
        on = json.loads(call("setReduceMotion", "false"))
        assert on["artSpinning"], on
        print("art spin gated by reduceMotion", file=sys.stderr)
        # Narrow the second bar until the real adaptive layout drops
        # previous/next but keeps play/pause, artwork, and a usable label.
        for width in range(560, 853, 2):
            narrow = json.loads(call("setNarrowWidth", width))
            time.sleep(.35)
            narrow = json.loads(call("states"))["narrow"]
            if narrow["stage"] == 1 and narrow["labelWidth"] >= 110: break
        else:
            raise RuntimeError("No compact width found: " + json.dumps(narrow))
        assert narrow["playPause"] and narrow["art"] and not narrow["previousNext"], narrow
        print("narrow", width, narrow, file=sys.stderr)
        time.sleep(.5)
        grab(call, "wide", output / "bar.png")
        grab(call, "narrow", output / "bar-compact.png")
        geometry.update(json.loads(call("widgetGeometry")))
        opened = json.loads(call("openSettings"))
        assert opened["opened"] and opened["popupVisible"], opened
        assert opened["page"] == "nowPlaying", opened
        time.sleep(.8)
        # The popup owns the playhead: a full timeline shows the bar, the
        # transport follows the player's own capabilities, and a seek lands.
        bars = json.loads(call("timelineState"))
        print("timeline", bars, file=sys.stderr)
        assert bars["showProgress"] and bars["seekable"] and bars["ticking"], bars
        assert bars["elapsed"] == "1:12" and bars["total"] == "3:28", bars
        assert bars["fraction"] > 0.3 and bars["fraction"] < 0.4, bars
        grab(call, "panel", output / "now-playing.png")
        # A real drag, not a direct seek: press, move, release. The move writes
        # the target into the playhead first, which is what used to make the
        # release compute a zero offset and get refused.
        seeked = json.loads(call("dragPopup", 170))
        assert seeked.get("position", 0) > 169 and seeked.get("position", 0) < 171, seeked
        # The seek must be absolute: a relative offset is measured from an
        # estimate of the player's position, and every millisecond of that
        # estimate is an error in where the track actually lands.
        assert 170 in seeked.get("absoluteSeeks", []), seeked
        # A wheel notch emits moved then released with no drag.
        time.sleep(1.4)
        wheeled = json.loads(call("wheelPopup"))
        assert wheeled["absoluteSeeks"][-1] > 170, wheeled
        # After next/previous the mirror still holds the old track's position;
        # the slider must not inherit it, and seeking must measure from the
        # player's own position for the new track.
        time.sleep(1.4)
        changed = json.loads(call("changeTrack", "Second Track", 95))
        time.sleep(.3)
        changed = json.loads(call("timelineState"))
        assert changed["length"] == 95 and changed["position"] < 95, changed
        after = json.loads(call("dragPopup", 60))
        assert 60 in after.get("absoluteSeeks", []), after
        json.loads(call("changeTrack", "Glasswork", 208))
        # A browser whose MPRIS clock dies after a seek must not freeze the
        # slider at the start. Firefox still moves its audio on Seek and only
        # its Position reporting is broken, so the widget keeps its own anchor
        # and keeps seeking with offsets measured from that estimate.
        time.sleep(1.4)
        broken = json.loads(call("breakPlayerClock"))
        assert broken["position"] > 0, broken
        first = broken["position"]
        time.sleep(1.2)
        later = json.loads(call("timelineState"))
        assert later["position"] > first, (first, later)
        recovered = json.loads(call("dragPopup", 120))
        # Even with a dead clock the target is exact, because the jump is
        # absolute and never consults the player's position.
        assert 120 in recovered.get("absoluteSeeks", []), recovered
        json.loads(call("repairPlayerClock"))
        # A track that never reports a length (a live stream) gets no progress
        # row at all. A track that already reported one and then stops keeps
        # its bar, which the broken-clock block above covers.
        json.loads(call("changeTrack", "Live Stream", 0))
        no_length = json.loads(call("setTimeline", 0, 0, "false"))
        print("live", no_length, file=sys.stderr)
        assert not no_length["showProgress"] and not no_length["seekable"], no_length
        # A player that can be read but not moved keeps the row, frozen.
        json.loads(call("changeTrack", "Glasswork", 208))
        frozen = json.loads(call("setTimeline", 72, 208, "false"))
        assert frozen["showProgress"] and not frozen["seekable"], frozen
        json.loads(call("setTimeline", 72, 208, "true"))
        # Past the post-seek grace, so the mirror re-anchors on the fresh
        # reading and the screenshot shows the fixture's own position.
        time.sleep(1.6)
        json.loads(call("timelineState"))
        time.sleep(.4)
        grab(call, "panel", output / "now-playing.png")
        # A browser that cannot skip shows the buttons disabled, not missing.
        limited = json.loads(call("setTransportCapabilities", "false", "false"))
        assert len(limited["transport"]) == 3, limited
        skip = [b for b in limited["transport"] if b["tooltip"] in ("Previous", "Next")]
        assert all(not b["enabled"] for b in skip), limited
        play = [b for b in limited["transport"] if b["tooltip"] in ("Play", "Pause")]
        assert play and play[0]["enabled"], limited
        json.loads(call("setTransportCapabilities", "true", "true"))
        # The settings screen lives behind the gear; the preview shows it there.
        settings_page = json.loads(call("showSettingsPage"))
        assert settings_page["page"] == "settings", settings_page
        # The playhead belongs to the now-playing screen: leaving it stops the
        # timer rather than re-reading the player behind another screen.
        off = json.loads(call("timelineState"))
        assert not off["ticking"], off
        time.sleep(.8)
        grab(call, "settings", output / "settings.png")
        # And closing the card stops it outright.
        closed = json.loads(call("closePopup"))
        assert not closed["opened"] and not closed["ticking"], closed
        state = json.loads(call("states"))["wide"]
        print("panel", state, file=sys.stderr)
        assert "Mozilla firefox" in state["playerSummary"], state
        # Album-art-only mode: the bar shows the artwork and nothing else.
        album_only = json.loads(call("setWidgetSetting", "albumArtOnly", "true"))
        time.sleep(.6)
        album_only = json.loads(call("states"))["wide"]
        assert album_only["albumOnly"] and album_only["art"], album_only
        assert not album_only["labelVisible"] and not album_only["playPause"], album_only
        assert album_only["width"] <= 30, album_only
        grab(call, "wide", output / "bar-album-only.png")
        # Idle: no media, the placeholder artwork still holds the slot.
        json.loads(call("setWidgetSetting", "albumArtOnly", "false"))
        idle = json.loads(call("setIdle"))
        time.sleep(.6)
        idle = json.loads(call("states"))["wide"]
        print("idle", idle, file=sys.stderr)
        assert idle["visible"] and idle["art"], idle
        assert not idle["labelVisible"] and not idle["playPause"], idle
        assert not idle["artSpinning"], idle
        grab(call, "wide", output / "bar-idle.png")
        # Playing a track that has no cover at all: the note takes the cover's
        # place inside the same round slot and turns at the same speed.
        json.loads(call("setPlaying", "true"))
        time.sleep(.3)
        uncovered = json.loads(call("states"))["wide"]
        assert uncovered["visible"] and uncovered["artSpinning"], uncovered
        assert uncovered["artKind"] == "note", uncovered
        # The text must not touch the disc: the row's 4px gap alone reads as
        # none next to a round edge that pokes past its own box.
        assert wide["artLabelGap"] >= 2, wide
        print("uncovered note spinning", file=sys.stderr)
        grab(call, "wide", output / "bar-nocover.png")
        json.loads(call("setPlaying", "false"))
        # "Hide when nothing plays" brings back the upstream behavior.
        hidden = json.loads(call("setWidgetSetting", "hideWhenIdle", "true"))
        time.sleep(.6)
        hidden = json.loads(call("states"))["wide"]
        assert not hidden["visible"] and hidden["width"] == 0, hidden
        json.loads(call("setWidgetSetting", "hideWhenIdle", "false"))

    log_text = run_host(env, shell, work / "capture.log", capture)
    (output / "capture.log").write_text(log_text)
    (output / "cover.png").unlink(missing_ok=True)

    # Compose the 2560x1600 marketplace preview. The marketplace card shows
    # only a strip about 2.7 times as wide as it is tall from the vertical
    # middle, and websites crop to 16:9, so the widget is shown large in the
    # middle band: the bar from just before the widget to its right edge,
    # flush with the canvas edge like the real bar, and the appearance panel
    # opening under it and running off the bottom.
    sizes = {name: png_size(output / name) for name in ["bar.png", "now-playing.png"]}
    bar_w, bar_h = sizes["bar.png"]
    settings_w, settings_h = sizes["now-playing.png"]
    margin = 5 * SCALE  # Style.gapsOut between bar and popup.
    clip_x = round((geometry["x"] - 14) * SCALE)
    # The rounded right end runs off the canvas, inside the tray margin.
    bar_x, bar_y = 2560 - (bar_w - clip_x) + 10 * SCALE, 120
    # The panel is shown at 80% so its text starts inside the crops, and
    # high enough that the whole card lands in the 16:9 window.
    card_w, card_h = round(settings_w * .66), round(settings_h * .66)
    widget_center = bar_x + round((geometry["x"] + geometry["width"] / 2) * SCALE) - clip_x
    card_x = max(40, min(widget_center - card_w // 2, 2560 - card_w - 40))
    card_y = bar_y + bar_h + margin
    layout = [
        dict(file="bar.png", x=bar_x, y=bar_y, width=bar_w - clip_x, height=bar_h,
             clip=[clip_x, 0, bar_w - clip_x, bar_h], radius=10 * SCALE),
        dict(file="now-playing.png", x=card_x, y=card_y, width=card_w, height=card_h),
    ]
    print("layout", layout, file=sys.stderr)
    env.update(QT_QPA_PLATFORM=f"offscreen:configfile={work / 'compose.json'}", QT_SCALE_FACTOR="1",
               MPRIS_MODE="compose", MPRIS_WALLPAPER=WALLPAPER, MPRIS_LAYOUT=json.dumps(layout))
    (work / "compose.json").write_text(json.dumps({"screens": [dict(
        name="COMPOSE", x=0, y=0, width=2800, height=1800, logicalDpi=96, logicalBaseDpi=96, dpr=1)]}))
    preview = ROOT / "preview.png"

    def compose(call):
        time.sleep(1.5)
        preview.unlink(missing_ok=True)
        assert call("grabPreview", str(preview)) == "true"
        wait_for(lambda: complete_png(preview), "preview")
        print(preview, png_size(preview), file=sys.stderr)

    run_host(env, shell, work / "compose.log", compose)


if __name__ == "__main__": main()
