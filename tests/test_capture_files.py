"""Modules imported by the widget must reach the capture host.

`tools/capture/capture.py` builds a temporary Quickshell host from an explicit
file list. A module that `BarWidget.qml` imports but the list omits only fails
when someone runs the capture, which is exactly when a stale list is least
convenient to discover. This test reads the imports out of the production
widget and checks the list carries every one of them.

Run with: python3 -m unittest discover -s tests
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTURE = os.path.join(ROOT, "tools/capture/capture.py")
WIDGET = os.path.join(ROOT, "BarWidget.qml")

# import "Foo.js" as Foo
LOCAL_IMPORT = re.compile(r'^\s*import\s+"([^"]+\.(?:js|qml))"', re.MULTILINE)
# for name in ["A.qml", "B.js"]  (the copy list in capture.py)
COPY_LIST = re.compile(r'for name in \[(.*?)\]', re.DOTALL)
QUOTED = re.compile(r'"([^"]+)"')


def local_imports(path):
    with open(path, encoding="utf-8") as source:
        return sorted(set(LOCAL_IMPORT.findall(source.read())))


def copied_names(path):
    with open(path, encoding="utf-8") as source:
        text = source.read()
    names = set()
    for body in COPY_LIST.findall(text):
        # Only the widget's own file list matters; other loops copy theme
        # directories ("Commons", "Ui").
        names.update(name for name in QUOTED.findall(body)
                     if name.endswith(".qml") or name.endswith(".js"))
    return names


class CaptureFileListTest(unittest.TestCase):
    def test_every_imported_module_is_copied(self):
        imports = local_imports(WIDGET)
        self.assertIn("Clicks.js", imports)
        self.assertIn("Layout.js", imports)
        copied = copied_names(CAPTURE)
        for name in imports:
            self.assertIn(name, copied, f"BarWidget.qml imports {name} but capture.py never copies it")

    def test_listed_files_exist(self):
        for name in copied_names(CAPTURE):
            self.assertTrue(os.path.isfile(os.path.join(ROOT, name)), name)

    def test_service_is_the_fixture(self):
        # The capture must never load the real MPRIS service.
        with open(CAPTURE, encoding="utf-8") as source:
            text = source.read()
        self.assertIn('shutil.copy(TOOLS / "FakeService.qml", plugin / "Service.qml")', text)
