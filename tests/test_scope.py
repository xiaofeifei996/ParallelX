from pathlib import Path

root = Path(__file__).resolve().parents[1]
control = (root / "control").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")
panel = (root / "PXPanel.swift").read_text(encoding="utf-8")
bridge = (root / "PXSceneBridge.m").read_text(encoding="utf-8")

assert "Package: com.moxuan.parallelx" in control
assert "firmware (<< 16.0)" in control
assert "PXPanel.swift" in makefile and "PXSceneBridge.m" in makefile
assert 'stringArray(forKey: "applications")' in panel
assert 'dictionary(forKey: "applicationNames")' in panel
assert "PXSceneBridge.shared().close()" in panel
assert "let height = source.height * scale + 44" in panel
assert "canvas.transform = CGAffineTransform(scaleX: scale, y: scale)" in panel
assert panel.index("openApplication(bundleID, in: canvas)") < panel.index("canvas.transform = CGAffineTransform")
assert '_UIContextLayerHostView' in bridge
assert not list(root.rglob("*.dylib")), "The project must not carry Myrtle binaries"
