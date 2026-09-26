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
assert "let width = screen.width * 0.78" in panel
assert "let height = min(screen.height * 0.72, screen.height - 120)" in panel
assert "let canvas = UIView(frame: clip.bounds)" in panel
assert panel.index("card.frame = window.bounds") < panel.index("let clip = UIView(frame:")
assert "inFrame:strongSelf.canvas.bounds" in bridge
assert '_UISceneLayerHostContainerView' in bridge
assert "PXSetFrame(mutable, originalFrame)" in bridge
assert 'updateSettings:withTransitionContext:completion:' in bridge
assert 'updateSettings:withTransitionContext:' not in bridge.replace('updateSettings:withTransitionContext:completion:', '')
assert 'com.moxuan.parallelx.scene.log' not in bridge
assert not list(root.rglob("*.dylib")), "The project must not carry Myrtle binaries"
