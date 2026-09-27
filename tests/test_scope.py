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
assert "let height = width * screen.height / screen.width" in panel
assert "let canvas = UIView(frame: clip.bounds)" in panel
assert panel.index("root.view.addSubview(card)") < panel.index("let clip = UIView(frame:")
assert "if success { self.matchHostAspect() }" in panel
assert "height: start.height * scale" in panel
assert "#selector(resizeHost(_:))" in panel
assert "if gesture.state == .began { fullscreenTapped() }" in panel
assert "#selector(moveHost(_:))" in panel
assert "card.layer.cornerRadius" in panel and '"cornerRadius"' in panel
assert 'PXCornerGrip' in panel and 'path.addQuadCurve' in panel
assert 'corner.isOpaque = false' in panel and 'corner.backgroundColor = .clear' in panel
assert 'for side in [-1, 1]' in panel
assert 'root.view.addSubview(corner)' in panel
assert 'root.view.addSubview(moveGrip)' in panel
assert 'let gripBottom: CGFloat = 168' in panel
assert 'window.isUserInteractionEnabled = false' in panel
assert 'hostMoveGrip?.frame = CGRect' in panel
assert 'gestureWidth' in panel and 'gestureHeight' in panel and 'gestureOffset' in panel
assert 'gestureDebug' in panel and 'moveLine' not in panel
assert 'hostCorners.forEach { $0.removeFromSuperview() }' in panel
assert 'moveGrip.addGestureRecognizer(doubleTap)' in panel
assert 'numberOfTapsRequired = 2' in panel
assert '#selector(moveGripHeld(_:))' in panel
assert 'let clip = UIView(frame: card.bounds)' in panel
assert 'let toolbarWidth' not in panel
assert 'layoutHostControls()' in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert 'private func layoutHostControls()' in panel
assert 'root.onLayout = { [weak self] in self?.layoutHostControls() }' in panel
assert 'let root = PXHostViewController()' in panel.split('private func presentHost')[1]
assert 'layoutHostControls()' in panel.split('private func matchHostAspect()')[1].split('private func layoutHostControls()')[0]
assert 'let window = PXHandleWindow(windowScene: scene)' in panel
assert 'panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()' in panel
assert '"↙"' not in panel and '"↘"' not in panel
assert 'prepareWindow(for: bundleID, wasFullscreen: wasFullscreen)' in panel
assert panel.index('openApplication(bundleID, in: canvas') < panel.index('prepareWindow(for: bundleID')
assert 'UIScene.willDeactivateNotification' in panel
assert 'needsHostRefresh' in panel
assert 'BOOL shouldReturnHome = wasFullscreen || [currentID isEqualToString:bundleID]' in bridge
assert 'screen.maxX' not in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert "PXSetSceneFrame(mutable, sourceSize)" in bridge
assert 'PXRect(PXCall(settings, @"displayConfiguration"), @"bounds")' in bridge
assert "CGFloat scale = MIN(target.width / source.width, target.height / source.height)" in bridge
assert "host.transform = CGAffineTransformMakeScale(scale, scale)" in bridge
assert "host.transform = CGAffineTransformIdentity" not in bridge
assert 'relocateKeyboardView:(UIView *)view' in bridge
assert 'self.keyboardOverlay = keyboardOverlay' in bridge
assert 'slot.opaque = NO' in bridge
assert 'Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView")' in (root / "Tweak.m").read_text(encoding="utf-8")
assert "openFullscreenApplication:" in (root / "PXSceneBridge.h").read_text(encoding="utf-8")
assert "_returnToHomeScreenWithCompletion:" in bridge
prepare = bridge.split("- (void)prepareWindowForBundleID:", 1)[1].split("- (void)layoutHost", 1)[0]
assert "id controller = UIApplication.sharedApplication;" in prepare
assert "SBHomeHardwareButtonActions" in prepare and "performSinglePressUpActions" in prepare
assert 'else finish(NO)' in prepare
assert 'objc_msgSend)(controller, selector, nil)' in prepare
assert "host.autoresizingMask" not in bridge
assert '_UISceneLayerHostContainerView' in bridge
assert 'updateSettings:withTransitionContext:completion:' in bridge
assert 'updateSettings:withTransitionContext:' not in bridge.replace('updateSettings:withTransitionContext:completion:', '')
entry = (root / "Tweak.m").read_text(encoding="utf-8")
assert 'MSHookMessageEx(scene, update' in entry
assert 'protectedSettings:settings forScene:scene' in entry
assert 'keepHostedProcessAlive' in bridge
assert 'self.processAssertion = nil' in bridge
assert 'com.moxuan.parallelx.scene.log' not in bridge
assert 'com.moxuan.parallelx.transition.log' not in bridge
assert not list(root.rglob("*.dylib")), "The project must not carry Myrtle binaries"
assert 'com.apple.springboard' in (root / "ParallelX.plist").read_text(encoding="utf-8")
assert not (root / "ParallelXSupport.plist").exists(), "Only SpringBoard may be injected"
radius = (root / "prefs" / "PXCornerRadiusController.swift").read_text(encoding="utf-8")
assert "UISlider()" in radius and "UILongPressGestureRecognizer" in radius
gesture = (root / "prefs" / "PXGestureAreaController.swift").read_text(encoding="utf-8")
assert all(key in gesture for key in ("gestureWidth", "gestureHeight", "gestureOffset", "gestureDebug"))
assert "PXGestureAreaController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
