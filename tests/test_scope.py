from pathlib import Path
from math import pi, sin

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
assert 'launcherIconSize' in panel and 'launcherRing\\(index + 1)' in panel
assert 'ring.radius * cos(theta)' in panel and 'ring.radius * sin(theta)' in panel
assert 'let angle: CGFloat = .pi / 2' in panel
assert 'let desiredRadius = requested == 1' in panel
assert 'pageCapacity = max(1, rings.reduce' in panel
assert 'let centerX = view.bounds.maxX - size / 2 - edgeInset' in panel
assert 'sheet = UIVisualEffectView' not in panel
assert 'launcherDragDistance' in panel
assert 'updateSelection(at: gesture.location(in: controller.view))' in panel
assert 'selectedSince = (next.map { isShortcut(apps[$0].id) } ?? true) ? nil : CACurrentMediaTime()' in panel
assert 'if !isShortcut(id)' in panel
assert 'recentApplicationSkipping(excluded, rank: rank)' in panel
assert 'return (1...count).map { rank in' in panel
assert 'id.hasPrefix("px.recent.")' in panel
assert 'hideForScreenshot' in panel and 'handleWindow?.isHidden = true' in panel
assert 'hasScene(forApplication: bundleID)' in panel
assert 'launchImage(forApplication: bundleID, size: card.bounds.size)' in panel
assert 'urlShortcuts' in panel and 'shortcutSymbols' in panel
assert '[overlay insertSubview:slot atIndex:0]' in bridge
assert 'recentApplicationSkipping:(NSArray<NSString *> *)excluded rank:(NSInteger)rank' in bridge
assert 'UISelectionFeedbackGenerator()' in panel
assert 'UIImpactFeedbackGenerator(style: .medium)' in panel
assert 'holdFeedbackTask?.cancel()' in panel
assert 'self.selectedIndex == next' in panel
assert 'selectedDuration >= controller.holdDuration' in panel
assert 'handleCenterFraction' in panel and 'handleDragMode == 2' in panel
assert 'buttonRings.append(ringIndex)' in panel and 'controller.animateClosed' in panel
assert 'selectionPreview.layer.cornerRadius = 26' in panel
assert 'width: 110, height: 110' in panel
assert 'selectionPreview.layer.borderWidth = 6' in panel
assert 'shortcuts: [(id: String, name: String, symbol: String)]' in panel
assert 'if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped() }' in panel
assert 'window.windowLevel = .statusBar - 2' in panel
assert 'shadowStrength' in panel and 'shadowBlur' in panel
assert 'card.layer.shadowPath = UIBezierPath' in panel
assert 'let gripTop: CGFloat = 28' in panel
assert 'launcherHoldMilliseconds' in panel
assert 'handleWidth' in panel and 'handleHeight' in panel
assert 'showPanel()' not in panel
for count in (3, 5, 7, 12):
    spacing = 62
    radius = spacing / (2 * sin(pi / (2 * (count - 1))))
    assert 2 * radius * sin(pi / (2 * (count - 1))) >= spacing - 1e-6
assert 'bridge.close()' in panel
assert "let width = screen.width * 0.78" in panel
assert "let height = width * screen.height / screen.width" in panel
assert "let canvas = UIView(frame: clip.bounds)" in panel
assert panel.index("root.view.addSubview(card)") < panel.index("let clip = UIView(frame:")
assert "private func refreshHost()" in panel
assert "height: start.height * scale" in panel
assert "#selector(resizeHost(_:))" in panel
assert "if gesture.state == .began { fullscreenTapped() }" in panel
fullscreen = panel.split('@objc private func fullscreenTapped()', 1)[1].split('@objc private func moveGripHeld', 1)[0]
assert fullscreen.index('UIView.animate(') < fullscreen.index('openFullscreenApplication(bundleID)')
assert 'card.frame = cardFrame' in fullscreen
assert fullscreen.index('openFullscreenApplication(bundleID)') < fullscreen.index('self.closeHost(animated: false)')
assert 'readyTicks >= 2 || ticks >= 15' in fullscreen
assert 'deadline: .now() + 0.75' not in fullscreen
assert 'exposeSystemHomeIndicator' not in panel
close_host = panel.split('private func closeHost(animated: Bool)', 1)[1]
assert close_host.index('window.isHidden = true\n            if self?.hostWindow == nil') < close_host.index('window.rootViewController = nil\n        }')
assert "#selector(moveHost(_:))" in panel
assert "card.layer.cornerRadius" in panel and '"cornerRadius"' in panel
assert 'CADisplayLink(target: self, selector: #selector(applyResizePreview))' in panel
assert 'card.layer.cornerRadius = resizeStartRadius / preview.scale' in panel
assert 'let change = (horizontal + vertical) / 2' in panel
assert 'abs(horizontal) > abs(vertical)' not in panel
assert 'PXCornerGrip' not in panel and 'path.addQuadCurve' not in panel
assert 'corner.isOpaque = false' in panel
assert 'corner.backgroundColor = debug ?' in panel
assert 'for side in [-1, 1]' in panel
assert 'root.view.addSubview(corner)' in panel
assert 'root.view.addSubview(moveGrip)' in panel
assert 'let gripBottom: CGFloat = 168' in panel
assert 'window.isUserInteractionEnabled = false' in panel
assert 'hostMoveGrip?.frame = CGRect' in panel
assert 'gestureWidth' in panel and 'gestureHeight' in panel and 'gestureOffset' in panel
assert 'gestureDebug' in panel and 'moveLine' not in panel
assert 'moveGrip.backgroundColor = UIColor(white: 1, alpha: 0.02)' in panel
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
assert 'BOOL shouldReturnHome = wasFullscreen && [currentID isEqualToString:bundleID]' in bridge
assert 'screen.maxX' not in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert "PXSetSceneFrame(mutable, sourceSize)" in bridge
assert 'PXRect(PXCall(settings, @"displayConfiguration"), @"bounds")' in bridge
assert "CGFloat scale = MIN(target.width / source.width, target.height / source.height)" in bridge
assert "host.transform = CGAffineTransformMakeScale(scale, scale)" in bridge
assert "host.transform = CGAffineTransformIdentity" not in bridge
assert 'relocateKeyboardView:(UIView *)view' in bridge
assert 'self.keyboardOverlay = keyboardOverlay' in bridge
assert 'slot.opaque = NO' in bridge
assert 'screen.height * 0.55' in bridge and 'screen.height * 0.4' not in bridge
assert 'Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView")' in (root / "Tweak.m").read_text(encoding="utf-8")
assert "openFullscreenApplication:" in (root / "PXSceneBridge.h").read_text(encoding="utf-8")
assert 'if (self.scene && [self.bundleID isEqualToString:bundleID])' in bridge
assert 'activateApplication:fromIcon:location:activationSettings:actions:' in bridge
assert 'PXProbeFullscreenRuntime' not in bridge
assert 'performShortcut:(NSString *)identifier' in bridge
assert all(action in bridge for action in ('px.action.dark', 'px.action.record',
                                          'px.action.rotation', 'px.action.screenshot'))
assert "_returnToHomeScreenWithCompletion:" in bridge
prepare = bridge.split("- (void)prepareWindowForBundleID:", 1)[1].split("- (void)layoutHost", 1)[0]
assert "id controller = UIApplication.sharedApplication;" in prepare
assert "SBHomeHardwareButtonActions" in prepare and "performSinglePressUpActions" in prepare
assert prepare.index('performSinglePressUpActions') < prepare.index('_returnToHomeScreenWithCompletion:')
assert 'finish(NO);' in prepare
assert 'objc_msgSend)(controller, selector, nil)' in prepare
assert "host.autoresizingMask" not in bridge
assert '_UISceneLayerHostContainerView' in bridge
assert 'updateSettings:withTransitionContext:completion:' in bridge
assert 'updateSettings:withTransitionContext:' not in bridge.replace('updateSettings:withTransitionContext:completion:', '')
entry = (root / "Tweak.m").read_text(encoding="utf-8")
assert 'MSHookMessageEx(scene, update' in entry
assert 'protectedSettings:settings forAnyScene:scene' in entry
assert 'PXSceneBridge relocateAnyKeyboardView:view' in entry
assert 'private func layoutDocks()' in panel and 'private func restoreDock(' in panel
assert 'dock.card.layer.shadowPath = UIBezierPath(roundedRect: dock.card.bounds' in panel
assert 'dock.card.layer.cornerRadius = radius' in panel
assert 'if hostWindow != nil { parkMain(side: dock.side) }' in panel
assert 'dock.side = sender.direction == .left ? -1 : 1' in panel
assert 'overlay.addGestureRecognizer(swipe)' in panel
assert 'hostTopCorners' in panel and '#selector(dockTapped(_:))' in panel
assert 'PXDockController.swift' in (root / 'prefs' / 'Makefile').read_text(encoding='utf-8')
assert 'com.apple.springboard.lockstate' in entry
assert 'guard !deviceLocked, needsHostRefresh' in panel
assert 'self.canvas.window.windowLevel + 1' in bridge
assert 'self.keyboardOverlay.window.windowLevel = self.keyboardWindowLevel' in bridge
assert 'self.relocatingKeyboard' in bridge
assert 'PXSetSceneFrame(mutable, self.sourceSize)' in bridge
assert 'UILaunchStoryboardName' in bridge and 'renderInContext:context' in bridge
assert 'NSClassFromString(@"LSApplicationProxy")' in bridge
assert 'codes.aurora.kayoko.core.show' in bridge
assert 'keepHostedProcessAlive' in bridge
assert 'applicationDisplayItemWithBundleIdentifier:sceneIdentifier:' in bridge
assert 'addAppLayoutForDisplayItem:completion:' in bridge
assert 'createApplicationProcessForBundleID:' not in bridge
assert bridge.index('completion(YES);') < bridge.index('[strongSelf registerColdSceneInSwitcher:scene bundleID:bundleID]')
assert 'displayItemWithType:bundleIdentifier:uniqueIdentifier:' not in bridge
assert 'self.processAssertion = nil' in bridge
assert 'com.moxuan.parallelx.scene.log' not in bridge
assert 'com.moxuan.parallelx.transition.log' not in bridge
assert not list(root.rglob("*.dylib")), "The project must not carry Myrtle binaries"
assert 'com.apple.springboard' in (root / "ParallelX.plist").read_text(encoding="utf-8")
assert not (root / "ParallelXSupport.plist").exists(), "Only SpringBoard may be injected"
radius = (root / "prefs" / "PXCornerRadiusController.swift").read_text(encoding="utf-8")
assert "UISlider()" in radius and "UILongPressGestureRecognizer" in radius
assert '"shadowStrength"' in radius and '"shadowBlur"' in radius
gesture = (root / "prefs" / "PXGestureAreaController.swift").read_text(encoding="utf-8")
assert all(key in gesture for key in ("gestureWidth", "gestureHeight", "gestureOffset", "gestureDebug"))
assert "PXGestureAreaController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
launcher = (root / "prefs" / "PXLauncherController.swift").read_text(encoding="utf-8")
assert all(key in launcher for key in ("launcherIconSize", "launcherRing1", "launcherRing4"))
assert all(key in launcher for key in ("launcherEdgeInset", "launcherHoldMilliseconds", "handleWidth", "handleHeight"))
assert "PXLauncherController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
picker = (root / "prefs" / "PXAppPickerController.swift").read_text(encoding="utf-8")
assert 'moveRowAt sourceIndexPath' in picker and 'selected.insert(id, at: destinationIndexPath.row)' in picker
assert 'numberOfSections(in tableView: UITableView) -> Int { 3 }' in picker
assert 'px.action.window' in picker
assert 'px.action.recent' in picker and 'urls.count < 10' in picker
assert 'px.action.kayoko' in picker
assert 'key = "hideForScreenshot"' in (root / 'prefs' / 'Resources' / 'Root.plist').read_text(encoding='utf-8')
