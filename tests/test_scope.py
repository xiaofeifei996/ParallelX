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
assert 'let ringSpacing = size + ringGap' in panel
assert 'previousRadius + (rings.isEmpty ? 0 : ringSpacing)' in panel
assert 'ring.radius * cos(theta)' in panel and 'ring.radius * sin(theta)' in panel
assert 'let angle: CGFloat = .pi / 2' in panel
assert 'let desiredRadius = requested == 1' in panel
assert 'pageCapacity = max(1, rings.reduce' in panel
assert 'let centerX = view.bounds.maxX - size / 2 - edgeInset' in panel
assert 'sheet = UIVisualEffectView' not in panel
assert 'launcherDragDistance' in panel
assert 'updateSelection(at: gesture.location(in: controller.view))' in panel
assert 'selectedSince = next.map { applicationID(apps[$0].id) != nil || apps[$0].id == "px.action.screenshot" }' in panel
assert 'if applicationID(id) != nil || id == "px.action.brightness" || id == "px.action.screenshot"' in panel
assert 'recentApplicationSkipping(excluded, rank: rank)' in panel
assert 'return (1...count).map { rank in' in panel
assert 'id.hasPrefix("px.recent.")' in panel
assert 'hideForScreenshot' in panel and 'PXSceneBridge.setCaptureHidden(hide, for: handle)' in panel
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
assert 'if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped(); return }' in panel
assert 'window.windowLevel = .statusBar + 0.2' in panel
assert 'shadowStrength' in panel and 'shadowBlur' in panel
assert 'card.layer.shadowPath = UIBezierPath' in panel
assert 'let card = UIView(frame: cardFrame)' in panel
assert 'launcherHoldMilliseconds' in panel
assert 'handleWidth' in panel and 'handleHeight' in panel
assert 'showPanel()' not in panel
for count in (3, 5, 7, 12):
    spacing = 62
    radius = spacing / (2 * sin(pi / (2 * (count - 1))))
    assert 2 * radius * sin(pi / (2 * (count - 1))) >= spacing - 1e-6
assert 'bridge.close()' in panel
assert 'screen.width * initialWidthFraction / source.width' in panel
assert "CGSize(width: source.width * scale, height: source.height * scale)" in panel
assert "let canvas = UIView(frame: clip.bounds)" in panel
assert panel.index("root.view.addSubview(card)") < panel.index("let clip = UIView(frame:")
assert "private func refreshHost()" in panel
assert "height: start.height * scale" in panel
assert "#selector(resizeHost(_:))" in panel
assert "if gesture.state == .began { fullscreenTapped() }" in panel
fullscreen = panel.split('@objc private func fullscreenTapped()', 1)[1].split('@objc private func moveGripHeld', 1)[0]
assert fullscreen.index('PXMotion.spring(') < fullscreen.index('openFullscreenApplication(bundleID)')
assert 'card.frame = cardFrame' in fullscreen
assert fullscreen.index('openFullscreenApplication(bundleID)') < fullscreen.index('self.closeHost(animated: false)')
assert 'readyTicks >= 2 || ticks >= 15' in fullscreen
assert 'deadline: .now() + 0.75' not in fullscreen
assert 'exposeSystemHomeIndicator' not in panel
close_host = panel.split('private func closeHost(animated: Bool)', 1)[1]
assert close_host.index('window.isHidden = true\n            if self?.hostWindow == nil') < close_host.index('window.rootViewController = nil\n        }')
assert "#selector(moveHost(_:))" in panel
assert "card.layer.cornerRadius" in panel and '"cornerRadius"' in panel
assert 'resizePreview = (scale, x, start.minY)\n                applyResizePreview()' in panel
resize = panel.split('private func resizeHost', 1)[1].split('private func applyResizePreview', 1)[0]
assert 'card.layer.shadowOpacity = 0' not in resize
assert 'card.layer.cornerRadius = resizeStartRadius / preview.scale' in panel
assert 'let change = (horizontal + vertical) / 2' in panel
assert 'abs(horizontal) > abs(vertical)' not in panel
assert 'PXCornerGrip' not in panel and 'path.addQuadCurve' not in panel
assert 'corner.isOpaque = false' in panel
assert 'corner.backgroundColor = debug ?' in panel
assert 'for side in [-1, 1]' in panel
assert 'root.view.addSubview(corner)' in panel
assert 'root.view.addSubview(moveGrip)' in panel
assert 'window.frame = scene.coordinateSpace.bounds' in panel
assert 'window.isUserInteractionEnabled = false' in panel
assert 'hostMoveGrip?.frame = CGRect' in panel
assert 'gestureWidth' in panel and 'gestureHeight' in panel and 'gestureOffset' in panel
assert 'gestureDebug' in panel and 'moveLine' not in panel
assert 'moveGrip.backgroundColor = .clear' in panel
assert 'corner.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear' in panel
assert 'top.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear' in panel
assert panel.count('PXSceneBridge.keepTransparentGestureViewHittable(') == 3
assert 'PXSetBool(view.layer, @"setHitTestsAsOpaque:", YES)' in bridge
assert 'hostCorners.forEach { $0.removeFromSuperview() }' in panel
assert 'moveGrip.addGestureRecognizer(doubleTap)' in panel
assert 'numberOfTapsRequired = 2' in panel
assert '#selector(moveGripHeld(_:))' in panel
assert 'let clip = UIView(frame: card.bounds)' in panel
assert 'let toolbarWidth' not in panel
assert 'layoutHostControls()' in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert 'private func layoutHostControls()' in panel
assert 'self?.screenGeometryChanged()' in panel and 'self?.layoutHostControls()' in panel
assert 'let root = PXHostViewController()' in panel.split('private func presentHost')[1]
assert 'layoutHostControls()' in panel.split('private func matchHostAspect()')[1].split('private func layoutHostControls()')[0]
assert 'let window = PXHandleWindow(windowScene: scene)' in panel
assert 'panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()' in panel
assert '"↙"' not in panel and '"↘"' not in panel
assert 'prepareWindow(for: bundleID, wasFullscreen: true)' in panel
assert panel.index('prepareWindow(for: bundleID, wasFullscreen: true)') < panel.index('self.presentHost(bundleID, wasFullscreen: false)')
assert 'UIScene.willDeactivateNotification' in panel
assert 'needsHostRefresh' in panel
assert 'BOOL shouldReturnHome = wasFullscreen && [currentID isEqualToString:bundleID]' in bridge
assert 'screen.maxX' not in panel.split('@objc private func moveHost')[1].split('private func closeHost')[0]
assert "PXSetSceneFrame(mutable, PXServerFrameSize(mutable))" in bridge
assert 'PXRect(PXCall(settings, @"displayConfiguration"), @"bounds")' in bridge
assert "CGFloat scale = MIN(target.width / source.width, target.height / source.height)" in bridge
assert "host.transform = CGAffineTransformMakeScale(scale, scale)" in bridge
assert 'CGAffineTransformRotate' not in bridge
assert 'layer.frame = host.bounds' in bridge
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
assert prepare.index('_returnToHomeScreenWithCompletion:') < prepare.index('performSinglePressUpActions')
assert 'finish(NO);' in prepare
assert 'objc_msgSend)(controller, selector, ^{ finish(YES); })' in prepare
assert "host.autoresizingMask" not in bridge
assert '_UISceneLayerHostContainerView' in bridge
assert 'updateSettings:withTransitionContext:completion:' in bridge
assert 'updateSettings:withTransitionContext:' not in bridge.replace('updateSettings:withTransitionContext:completion:', '')
entry = (root / "Tweak.m").read_text(encoding="utf-8")
assert 'MSHookMessageEx(scene, update' in entry
assert 'protectedSettings:settings forAnyScene:scene' in entry
assert 'PXSceneBridge relocateAnyKeyboardView:view' in entry
assert 'private func layoutDocks(animated: Bool = true)' in panel and 'private func restoreDock(' in panel
assert 'dock.card.transform = CGAffineTransform(scaleX: scale, y: scale)' in panel
assert 'dock.card.transform = .identity' in panel
assert 'dock.card.frame = CGRect(origin: .zero, size: frame.size)' not in panel
assert 'if hostWindow != nil { parkMain(side: defaultDockSide) }' in panel
assert 'dock.side = sender.direction == .left ? -1 : 1' in panel
assert 'overlay.addGestureRecognizer(swipe)' in panel
park = panel.split('private func parkMain(side: Int)', 1)[1].split('private func layoutDocks(', 1)[0]
assert 'root.addSubview(overlay)' in park and 'controls.addSubview(overlay)' not in park
assert 'window.windowLevel = .statusBar + 0.1' in park
assert 'card.layer.shadowOpacity = 0' in park
assert 'let overlay = UIView(frame: card.frame)' in park
assert 'dock.overlay.frame = frame' in panel
assert 'dock.window.windowLevel = .statusBar + 0.2' in panel
assert 'dock.window.isUserInteractionEnabled = true' in panel
assert 'activeBridge.setHostedInteractionEnabled(false)' in panel
assert 'dock.bridge.setHostedInteractionEnabled(true)' in panel
assert bridge.count('setAllowsSelection:", !self.suppressSelection') == 2
assert 'host.userInteractionEnabled = !strongSelf.suppressSelection' in bridge
assert 'shared.removeDock(dock, fullscreenHandoff: true)' in panel
assert 'dock.bridge.closeForFullscreen()' in panel
assert 'activateApplication:fromIcon:location:activationSettings:actions:' in entry
assert 'applicationActivated:' in entry
assert 'self.fullscreenHandoff = YES;\n    [self close];' in bridge
assert 'hostTopCorners' in panel and '#selector(dockTapped(_:))' in panel
assert 'PXDockController.swift' in (root / 'prefs' / 'Makefile').read_text(encoding='utf-8')
dock_prefs = (root / 'prefs' / 'PXDockController.swift').read_text(encoding='utf-8')
assert 'UISegmentedControl(items: ["左侧", "右侧"])' in dock_prefs
assert 'forKey: "dockSide"' in dock_prefs
assert 'parkMain(side: defaultDockSide)' in panel.split('private func dockTapped', 1)[1].split('private func parkMain', 1)[0]
assert 'parkMain(side: sender.tag)' not in panel
assert 'com.apple.springboard.lockstate' in entry
assert 'guard !deviceLocked, needsHostRefresh' in panel
assert 'bool(forKey: "clearOnLock")' in panel
assert 'for dock in Array(dockedHosts) { removeDock(dock) }' in panel
assert 'recordDockTouch' not in panel and 'touchProbe' not in panel
assert 'overlay.backgroundColor = UIColor(white: 1, alpha: 0.02)' in panel
assert 'max(35, min(requested' in panel
dock_settings = (root / 'prefs' / 'PXDockController.swift').read_text(encoding='utf-8')
assert 'widthSlider.minimumValue = 35' in dock_settings
assert 'onBrightnessHold' in panel and 'start.value + (start.y - y)' in panel
assert 'setBrightnessLevel:(float)level' in bridge
picker = (root / 'prefs' / 'PXAppPickerController.swift').read_text(encoding='utf-8')
assert 'px.action.brightness' in panel and 'px.action.brightness' in picker
assert all(action in panel and action in picker for action in ('px.action.restart', 'px.action.search'))
assert 'kill(pid, SIGKILL)' in bridge and 'pid == getpid()' in bridge
assert 'private func showSearch()' in panel and 'private func hideSearch()' in panel
assert 'root.view.addSubview(top)' in panel and 'top.addSubview(mark)' not in panel
assert 'initialCardFrame(in: screen, size:' in panel.split('private func restoreDock', 1)[1]
assert 'root.bounds.height * 0.405' in panel
assert 'PXApplicationIconLarge(id)' in panel
assert 'navigationItem.searchController = search' in picker
assert 'localizedCaseInsensitiveContains(query)' in picker
assert 'CGSize(width: 32, height: 32)' in picker
root_plist = (root / 'prefs' / 'Resources' / 'Root.plist').read_text(encoding='utf-8')
assert 'cell = PSLinkCell; label = "应用、快捷操作与排序"' in root_plist
assert 'key = "clearOnLock"' in root_plist
assert 'self.canvas.window.windowLevel + 1' in bridge
assert 'self.keyboardOverlay.window.windowLevel = self.keyboardWindowLevel' in bridge
assert 'self.relocatingKeyboard' in bridge
assert 'PXSetSceneFrame(mutable, PXServerFrameSize(mutable))' in bridge
assert 'UILaunchStoryboardName' in bridge and 'renderInContext:context' in bridge
assert 'NSClassFromString(@"LSApplicationProxy")' in bridge
assert 'codes.aurora.kayoko.core.show' in bridge
assert 'keepHostedProcessAlive' in bridge
assert 'applicationDisplayItemWithBundleIdentifier:sceneIdentifier:' in bridge
assert 'addAppLayoutForDisplayItem:completion:' in bridge
assert 'createApplicationProcessForBundleID:' not in bridge
assert bridge.index('completion(YES);') < bridge.index('[strongSelf registerSceneInSwitcher:scene bundleID:bundleID]')
assert 'if (strongSelf.generation == generation)\n                            [strongSelf registerSceneInSwitcher:scene bundleID:bundleID];' in bridge
assert 'deadline: .now() + 0.16' not in panel
assert 'while dockedHosts.count >= limit, let oldest = dockedHosts.first { removeDock(oldest) }' in park
assert 'captureOutsideKeyboard' not in panel and 'isKeyboardRelocated()' in panel
assert 'private final class PXKeyboardDismissLayer: UIControl' not in panel
assert 'let window = PXOverlayWindow(windowScene: scene)' in panel.split('private func refreshKeyboardDismissLayer()', 1)[1]
assert 'keyboardDismissWindow?.rootViewController?.view.backgroundColor = UIColor.black.withAlphaComponent(dim)' in panel
assert 'keyboardDismissWindow?.windowLevel = host.windowLevel - 0.5' in panel
assert '(keyboardDismissWindow as? PXOverlayWindow)?.applySystemOrientation()' in panel
assert 'excludedRects' not in panel
assert 'if (visible == self.keyboardWasVisible) return;' in bridge
assert 'name: Notification.Name("PXKeyboardStateChanged")' in panel
assert 'removeKeyboardDismissLayer()' in close_host
assert 'gesture.velocity(in: window.rootViewController?.view).y < -500' in panel
assert 'if hostWindow != nil, hostedBundleID != bundleID { parkMain(side: defaultDockSide) }' in panel
open_fullscreen = panel.split('private func openFullscreen(', 1)[1].split('private func performShortcut', 1)[0]
assert open_fullscreen.index('closeHost(animated: false)') < open_fullscreen.index('openFullscreenApplication(bundleID)')
assert 'px.action.screenshot.copy' in panel and 'px.action.screenshot.copy' in bridge
copy_shot = bridge.split('if ([identifier isEqualToString:@"px.action.screenshot.copy"])', 1)[1].split('if ([identifier isEqualToString:@"px.action.screenshot"])', 1)[0]
assert '_UICreateScreenUIImage' in copy_shot and 'UIPasteboard.generalPasteboard.image = image' in copy_shot
assert 'takeScreenshot' not in copy_shot and 'UIImageWriteToSavedPhotosAlbum' not in copy_shot
assert 'urlSplitExcluded' in entry and 'URL 分屏黑名单' in root_plist
assert '!notification && link ? [defaults stringArrayForKey:@"urlSplitExcluded"] : nil' in entry
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
assert '"initialWidthPercent"' in radius and '"initialWidthPercent"' in panel
gesture = (root / "prefs" / "PXGestureAreaController.swift").read_text(encoding="utf-8")
assert all(key in gesture for key in ("gestureWidth", "gestureHeight", "gestureOffset", "gestureDebug"))
assert "PXGestureAreaController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
launcher = (root / "prefs" / "PXLauncherController.swift").read_text(encoding="utf-8")
assert all(key in launcher for key in ("launcherIconSize", "launcherRing1", "launcherRing4"))
assert 'launcherRingGap' in launcher and '"环间距"' in launcher
assert all(key in launcher for key in ("launcherEdgeInset", "launcherHoldMilliseconds", "handleWidth", "handleHeight"))
assert "PXLauncherController.swift" in (root / "prefs" / "Makefile").read_text(encoding="utf-8")
picker = (root / "prefs" / "PXAppPickerController.swift").read_text(encoding="utf-8")
assert 'moveRowAt sourceIndexPath' in picker and 'selected.insert(id, at: destinationIndexPath.row)' in picker
assert 'numberOfSections(in tableView: UITableView) -> Int { 3 }' in picker
assert 'px.action.window' in picker
assert 'px.action.recent' in picker and 'urls.count < 10' in picker
assert 'px.action.kayoko' in picker
assert 'key = "hideForScreenshot"' in (root / 'prefs' / 'Resources' / 'Root.plist').read_text(encoding='utf-8')
assert 'closeOutsideWithKeyboard' in panel and 'key = "closeOutsideWithKeyboard"' in root_plist
assert panel.count('initialCardFrame(in: screen, size:') == 3
assert 'initialRightInset' in panel
assert 'mask = hidden ? mask | 0x12 : mask & ~0x12' in bridge
assert 'com.moxuan.parallelx.capture-updated' in entry and 'PostNotification' in root_plist
blacklist = (root / 'prefs' / 'PXExternalBlacklistController.swift').read_text(encoding='utf-8')
assert 'PXApplicationIcon(app.id)' in blacklist and 'CGSize(width: 32, height: 32)' in blacklist
assert 'self.animateFullscreenReady()' in panel
assert 'fullscreenReadyView?.removeFromSuperview()' in panel
assert 'guard !UIAccessibility.isReduceMotionEnabled else { return }' in panel
for screen_width, card_width, saved_inset in ((390, 304.2, 12), (390, 304.2, 120), (320, 300, -5)):
    inset = min(max(0, screen_width - card_width), max(0, saved_inset))
    x = screen_width - card_width - inset
    assert x >= 0 and x + card_width <= screen_width
assert 'systemService:handleOpenApplicationRequest:withCompletion:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert '_handleTrustedOpenRequestForApplication:options:activationSettings:origin:withResult:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'FBSOpenApplicationOptionKeyActivateSuspended' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'externalOpenApplication:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'externalPendingBundleID' in panel
assert 'func completeOpening()' in panel
assert 'withRenderingMode(.alwaysOriginal)' in panel

catalog = (root / 'PXAppCatalog.m').read_text(encoding='utf-8')
action_picker = (root / 'prefs' / 'PXActionPickerController.swift').read_text(encoding='utf-8')
assert 'sqlite3_open_v2' in catalog and 'SQLITE_OPEN_READONLY' in catalog
assert 'fetchApplicationShortcutItemsOfTypes:forBundleIdentifier:withCompletionHandler:' in catalog
assert 'setUserInfo:' in catalog and 'entry[@"userInfo"]' in catalog
assert 'WFSpringBoardWorkflowRunnerClient' in bridge and 'initWithWorkflowIdentifier:' in bridge
assert 'UIHandleApplicationShortcutAction' in bridge and 'initWithSBSShortcutItem:' in bridge
assert 'px.custom.' in panel and 'customActions' in picker
assert 'groupMenuActive' in panel and 'selectedGroupAction' in panel
assert 'cancel.text = "取消"' in panel and 'scroll.scrollRectToVisible(groupRows[next].frame, animated: false)' in panel
assert 'groupScrollLink' not in panel
assert 'menu.frame = CGRect(x: view.bounds.maxX - width - 10' in panel
assert 'handleCenterY - height / 2' in panel
assert 'groupOriginY = menu.frame.midY' in panel
assert 'guard menu.bounds.contains(local) else' in panel
assert 'let delta = point.y - groupOriginY' in panel
assert 'let step = min(36, max(8, scroll.bounds.height / CGFloat(groupItems.count + 1)))' in panel
assert 'let row = min(groupItems.count, max(0, groupItems.count / 2 + Int(delta / step)))' in panel
assert 'max(150, ceil(widest) + 32)' in panel and 'label.textAlignment = .center' in panel
assert 'groupItems.count + 1' in panel and 'let moved = abs(delta) >= 8' in panel
assert 'private enum PXMotion' in panel and panel.count('PXMotion.spring(') >= 7
assert panel.count('PXMotion.ease(') >= 7
assert 'multiple && indexPath.section == 0' in action_picker
assert 'chosen.insert(chosen.remove(at: sourceIndexPath.row)' in action_picker
assert 'shade.frame = view.bounds' in panel
assert 'doubleTap.numberOfTapsRequired = 2' in panel
assert 'UIResponder.keyboardWillChangeFrameNotification' in panel
assert 'UIResponder.keyboardDidHideNotification' in panel
assert 'activeBridge.isKeyboardRelocated()' in panel.split('private func refreshKeyboardDismissLayer()', 1)[1].split('private func fadeKeyboardDismissLayer()', 1)[0]
assert 'keyboardDismissSuppressed' in panel and 'fadeKeyboardDismissLayer()' in panel
assert 'PXKeyboardFrameChanged' in bridge
assert 'self.keyboardHostView.window' in bridge and 'view.hidden || view.alpha <= 0.01' in bridge
assert 'PXDismissOpenedNotificationBanner(options);' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert (root / 'Tweak.m').read_text(encoding='utf-8').count('PXDismissOpenedNotificationBanner(options);') == 2

app_picker = (root / 'prefs' / 'PXAppPickerController.swift').read_text(encoding='utf-8')
action_picker = (root / 'prefs' / 'PXActionPickerController.swift').read_text(encoding='utf-8')
catalog = (root / 'PXAppCatalog.m').read_text(encoding='utf-8')
assert 'if indexPath.section == 0 { return }' in app_picker
assert 'indexPath.section == 0 ? .delete : .none' in app_picker
assert 'commit editingStyle: UITableViewCell.EditingStyle' in app_picker
assert 'PXApplicationHasActions(id)' in action_picker
assert 'PXStaticActions(bundleID).count' in catalog
assert 'PXFetchApplicationActions(app.id)' in action_picker
assert 'kind == "apps" { onSave?([item]) }' in action_picker
assert 'localizedStringForKey:title value:title table:@"InfoPlist"' in catalog
assert 'keyboardDimOpacity' in panel and 'keyboardDimOpacity' in root_plist
assert 'frontDisplayDidChange:' in (root / 'Tweak.m').read_text(encoding='utf-8')
assert 'PXOriginalFrontDisplayDidChange(springBoard, selector, application)' in (root / 'Tweak.m').read_text(encoding='utf-8')

for count in (1, 6, 20):
    height = min(6, count) * 52
    step = min(36, max(8, height / (count + 1)))
    middle = count // 2
    assert min(count, max(0, middle + int(step / step))) == min(count, middle + 1)
    assert min(count, max(0, middle + int(-step / step))) == max(0, middle - 1)

# Preferences must instantiate a native host, not a Swift subclass of the private controller.
prefs_host = (root / 'prefs' / 'PXRootListController.m').read_text(encoding='utf-8')
assert '@interface PXPageHostController : PSViewController' in prefs_host
assert 'initForContentSize:(CGSize)contentSize' in prefs_host
assert '[super initWithNibName:nil bundle:nil]' in prefs_host
assert root_plist.count('detail = PXPageHostController') == 6
for name in ('AppPicker', 'Launcher', 'CornerRadius', 'Dock', 'GestureArea'):
    assert ': UIViewController' in (root / 'prefs' / f'PX{name}Controller.swift').read_text(encoding='utf-8')
assert 'canvas.traitCollection.userInterfaceStyle' in bridge
assert 'activeBridge.updateAppearance(for: card.traitCollection.userInterfaceStyle)' in panel
assert 'button.contentHorizontalAlignment = .left' in panel
import plistlib
prefs_info = plistlib.loads((root / 'prefs' / 'Resources' / 'Info.plist').read_bytes())
assert prefs_info['NSPrincipalClass'] == 'PXRootListController'
assert 'overridePrincipalClass = 1' in (root / 'layout' / 'Library' / 'PreferenceLoader' / 'Preferences' / 'ParallelX.plist').read_text()
assert '- (void)setSpecifier:(PSSpecifier *)specifier' in prefs_host
assert 'if (self.contentController || !self.specifier) return;' in prefs_host

# Every settings slider has a title/value and a numeric keyboard affordance.
for name in ('CornerRadius', 'Dock', 'GestureArea'):
    page = (root / 'prefs' / f'PX{name}Controller.swift').read_text(encoding='utf-8')
    assert 'inputButtons' in page and 'PXSettingsStyle.inputButton' in page
assert '键盘关闭遮罩深度：%.0f%%' in prefs_host
assert 'setPreferenceValue:@(control.value / 100) specifier:specifier' in prefs_host
assert 'PXScreenGeometryChanged' in panel and 'PXHostedGeometryChanged' in bridge
assert 'handleCenterLandscapeFraction' in panel
assert 'sourceOrientation = orientation' in bridge
client_update = bridge.split('- (void)scene:(id)scene didUpdateClientSettingsWithDiff:', 1)[1].split('- (NSArray *)mainLayersForScene:', 1)[0]
assert 'PXSetSceneFrame(mutable, PXServerFrameSize(mutable))' in client_update
assert 'sb_effectiveInterfaceOrientation' in client_update
# Both sideways orientations fit isotropically; portrait-only apps keep their aspect.
for landscape in (False, True):
    visual = (844, 390) if landscape else (390, 844)
    raw = (visual[1], visual[0]) if landscape else visual
    rotated = (raw[1], raw[0]) if landscape else raw
    assert rotated == visual
    for target in ((600, 300), (300, 650)):
        scale = min(target[0] / visual[0], target[1] / visual[1])
        assert visual[0] * scale <= target[0] + 0.001
        assert visual[1] * scale <= target[1] + 0.001

# Landscape card is sized by the short screen edge, and reserves the dock lane.
for screen_w, screen_h in ((844, 390), (852, 393), (932, 430)):
    dock_w = max(35, min(110, screen_h * 0.12))
    for source_w, source_h in ((390, 844), (844, 390)):
        scale = min(screen_h * .78 / max(source_w, source_h),
                    (screen_w - dock_w - 48) / source_w)
        width, height = source_w * scale, source_h * scale
        right = screen_w - (dock_w + 24 + 12)
        assert height <= screen_h * .78 + .001
        assert right - width > screen_w / 2
        assert right < screen_w - dock_w - 12
        zoom = max(1, min(1.6, (right - 12) / width))
        assert right - width * zoom >= 12 - .001
        assert abs(width / height - source_w / source_h) < .001
assert 'portraitExternalKeyboard' in root_plist and 'landscapeExternalKeyboard' in root_plist
assert '![self usesExternalKeyboard]' in bridge
assert '[self.keyboardOriginalParent addSubview:view]' in bridge
assert 'activeBridge.isHostedKeyboardVisible()' in panel
assert '!activeBridge.usesExternalKeyboard()' in panel
assert 'let oldFrame = card.frame' in panel
assert 'gesture.translation(in: window.rootViewController?.view)' in panel

# Overlay orientation is explicit and immediate; the app owns surface rotation.
assert 'private final class PXHandleWindow: PXOverlayWindow' in panel
assert 'self.screen.fixedCoordinateSpace.bounds' in bridge
assert 'self.center = center' in bridge and 'root.frame = content' in bridge
assert 'orientation != layoutOrientation' in panel
assert 'pill.autoresizingMask = []' in panel
assert 'dockedHosts.filter { $0.side == dock.side }.count' in panel
assert '[super _rotateWindowToOrientation:orientation updateStatusBar:NO duration:0 skipCallbacks:NO]' in bridge
assert 'didUpdateClientSettingsWithDiff:' in bridge
assert 'if (self.fullscreenHandoff || !scene' in bridge
activation = bridge.split('- (BOOL)openFullscreenApplication:', 1)[1].split('- (BOOL)', 1)[0]
assert activation.index('self.fullscreenHandoff = YES') < activation.index('objc_msgSend)(ui, activate')
# Both halves of a landscape source must map into the fitted card.
for source_w, source_h in ((390, 844), (844, 390)):
    scale = min(300 / source_w, 660 / source_h)
    for fraction in (.25, .75, 1):
        touch_x = source_w * scale * fraction
        assert abs(touch_x / scale - source_w * fraction) < .001
assert 'layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight' in bridge
assert 'keyboardDismissSuppressed = keyboardHideInFlight || !visible' in panel
assert 'indicator.backgroundColor = UIColor(white: 0.65, alpha: 0.65)' in panel
assert 'let ratio = source.height / source.width' in panel
assert '[PXSceneBridge noteSystemOrientation:(UIInterfaceOrientation)orientation]' in entry
assert 'MSHookMessageEx(springBoard, orientation, (IMP)PXOrientationChanged' in entry
assert '_SBAppTransitionManager' not in entry
assert '_postActiveInterfaceOrientationChangedNotificationAnimated:' in entry
orientation_reader = bridge.split('+ (UIInterfaceOrientation)systemOrientation', 1)[1].split('- (void)updateAppearanceForStyle:', 1)[0]
assert orientation_reader.index('return PXSystemOrientation') < orientation_reader.index('activeInterfaceOrientation')
assert 'sceneForBundleID' not in orientation_reader
# A new system target wins even while the old desktop/app scene is portrait.
for target in (1, 2, 3, 4):
    cached_target, stale_scene = target, 1
    resolved = cached_target if cached_target in (1, 2, 3, 4) else stale_scene
    screen = (844, 390) if resolved in (3, 4) else (390, 844)
    handle_x = screen[0] - 24
    assert handle_x == (820 if target in (3, 4) else 366)
assert 'layoutDocks(animated: false)' in panel
assert 'card.transform = CGAffineTransform(scaleX: zoom, y: zoom)' in panel

# Device rotation must not replace a still-supported hosted orientation.
protected = bridge.split('- (id)protectedSettings:(id)settings forScene:', 1)[1].split('- (void)scene:', 1)[0]
assert 'self.sourceOrientation = orientation' not in protected
assert 'PXSetHostedOrientation(mutable, self.sourceOrientation)' in protected
assert 'setDeviceOrientation:' in bridge and 'BSCanonicalOrientationMapResolver' in bridge
assert 'supportedInterfaceOrientations' in client_update
assert 'if (!appRequestedChange && !clientConfirmedChange && !clientInterfaceChange &&' in client_update
assert 'clientOrientation != oldClientOrientation' in client_update
assert 'effectiveOrientation != oldEffective' in client_update
assert 'requested != oldPreferred' in client_update
assert 'PXPreferredHostedOrientation(self.bundleID, PXCall(scene, @"clientSettings"))' in bridge
assert 'CGSize sourceSize = PXSourceSize(mutable)' in bridge
assert 'row.autoresizingMask = [.flexibleWidth]' in panel
assert 'let edge: CGFloat = landscape ? 27 : 12' in panel
assert 'window.windowLevel = .statusBar + 0.5' in panel
for source, screen, old_effective, effective, expected in (
    (1, 1, 1, 3, True),   # Portrait device, app enters landscape video.
    (1, 3, 1, 3, False),  # Device rotation alone does not turn the hosted app.
    (1, 1, 0, 3, False),  # Incomplete startup settings are not a rotation request.
):
    confirmed = old_effective in (1, 2, 3, 4) and effective != old_effective and \
        effective != source and (screen in (3, 4)) == (source in (3, 4))
    assert confirmed == expected
for screen_landscape in (False, True):
    for app_mask, expected_landscape in ((2, False), (2 | 8 | 16, False), (8 | 16, True)):
        orientation = next(value for value in (1, 2, 3, 4) if app_mask & (1 << value))
        assert (orientation in (3, 4)) == expected_landscape
        source = (844, 390) if expected_landscape else (390, 844)
        screen = (844, 390) if screen_landscape else (390, 844)
        scale = min(screen[0] / source[0], screen[1] / source[1])
        assert abs((source[0] * scale) / scale - source[0]) < .001
for current, mask, requested, expected in ((1, 30, 3, 1), (1, 24, 3, 3), (3, 2, 1, 1), (1, 0, 3, 1)):
    result = current if not mask or mask & (1 << current) else requested
    assert result == expected
for key in ('portraitInitialWidthPercent', 'portraitCornerRadius',
            'portraitLandscapeInitialWidthPercent', 'portraitLandscapeCornerRadius'):
    assert key in panel and key in radius
assert 'configuredCornerRadius(in: screen, source: source)' in panel
dismiss = panel.split('private func refreshKeyboardDismissLayer()', 1)[1].split('private func fadeKeyboardDismissLayer()', 1)[0]
assert 'guard enabled, activeBridge.usesExternalKeyboard()' in dismiss
assert '$0.session.persistentIdentifier == "com.apple.springboard"' in panel
assert '!kind.contains("keyboard") && !kind.contains("aperture")' in panel
for landscape in (False, True):
    width, height = (844, 390) if landscape else (390, 844)
    x, y, w, h = width - 90 - 140, (height - 303) / 2, 140, 303
    zoom = min(1.6, (x + w - 12) / w) if landscape else 1
    target_x, target_y = x + w - w * zoom, y + h - h * zoom
    assert abs(target_x + w * zoom - (x + w)) < .001
    assert abs(target_y + h * zoom - (y + h)) < .001
    if landscape:
        assert zoom == 1.6
