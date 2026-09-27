import UIKit

private let preferenceDomain = "com.moxuan.parallelx"
private let gripMargin: CGFloat = 28
private let gripTop: CGFloat = 28
private let gripBottom: CGFloat = 168
private let shortcuts: [(id: String, name: String, symbol: String)] = [
    ("px.action.dark", "深色模式", "moon.fill"),
    ("px.action.record", "屏幕录制", "record.circle"),
    ("px.action.rotation", "方向锁定", "lock.rotation"),
    ("px.action.window", "切换全屏/分屏", "rectangle.on.rectangle"),
    ("px.action.screenshot", "截屏", "camera.viewfinder"),
    ("px.action.recent", "最近打开的应用", "clock.arrow.circlepath"),
    ("px.action.kayoko", "呼出 Kayoko", "doc.on.clipboard"),
    ("px.action.brightness", "调节亮度", "sun.max.fill")
]

private func isShortcut(_ id: String) -> Bool {
    id.hasPrefix("px.action.") || id.hasPrefix("px.url.") || id.hasPrefix("px.recent.")
}

private func panelIcon(_ id: String) -> UIImage? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        if parts.count == 4 { return PXApplicationIcon(String(parts[3])) }
    }
    if isShortcut(id) {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let key = id.hasPrefix("px.recent.") ? "px.action.recent" : id
        let custom = (defaults?.dictionary(forKey: "shortcutSymbols") as? [String: String])?[key]
        let fallback = shortcuts.first(where: { $0.id == key })?.symbol ?? "link"
        return UIImage(systemName: custom ?? fallback) ?? UIImage(systemName: fallback)
    }
    return PXApplicationIcon(id)
}

private final class PXHandleWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === rootViewController?.view ? nil : result
    }
}

private final class PXHostViewController: UIViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { onLayout?() }
    }
}

private final class PXDockedHost {
    let window: UIWindow
    let card: UIView
    let canvas: UIView
    let bridge: PXSceneBridge
    let bundleID: String
    var side: Int
    let sourceSize: CGSize
    let originalFrame: CGRect
    let originalCardFrame: CGRect
    let originalCornerRadius: CGFloat
    let corners: [UIView]
    let topCorners: [UIView]
    let moveGrip: UIView?
    let overlay: UIView

    init(window: UIWindow, card: UIView, canvas: UIView, bridge: PXSceneBridge,
         bundleID: String, side: Int, corners: [UIView], topCorners: [UIView],
         moveGrip: UIView?, overlay: UIView) {
        self.window = window
        self.card = card
        self.canvas = canvas
        self.bridge = bridge
        self.bundleID = bundleID
        self.side = side
        self.sourceSize = bridge.hostedSourceSize()
        self.originalFrame = window.frame
        self.originalCardFrame = card.frame
        self.originalCornerRadius = card.layer.cornerRadius
        self.corners = corners
        self.topCorners = topCorners
        self.moveGrip = moveGrip
        self.overlay = overlay
    }
}

private final class PXPanelViewController: UIViewController {
    var apps: [(id: String, name: String)] = []
    var onBrightnessHold: ((CGPoint) -> Void)?
    var handleCenterY: CGFloat = 0
    var handleCenterX: CGFloat = 0
    var holdDuration: TimeInterval = 0.7
    private let shade = UIView()
    private let pageControl = UIPageControl()
    private let selectionPreview = UIImageView()
    private let brightnessOverlay = UIView()
    private let brightnessTrack = UIView()
    private let brightnessFill = UIView()
    private let brightnessPercent = UILabel()
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let holdFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var buttons: [UIButton] = []
    private var buttonRings: [Int] = []
    private var selectedIndex: Int?
    private var selectedSince: CFTimeInterval?
    private var lastSelectionPoint = CGPoint.zero
    private var holdFeedbackTask: DispatchWorkItem?
    private var page = 0
    private var pageCapacity = 1
    private var lastSize = CGSize.zero
    private var progress: CGFloat = 0
    private let defaults = UserDefaults(suiteName: preferenceDomain)
    private var iconSize: CGFloat {
        min(72, max(36, CGFloat(defaults?.object(forKey: "launcherIconSize") as? Int ?? 52)))
    }
    private var edgeInset: CGFloat {
        min(120, max(0, CGFloat(defaults?.object(forKey: "launcherEdgeInset") as? Int ?? 6)))
    }
    private var ringCounts: [Int] {
        [3, 5, 7, 9].enumerated().map { index, fallback in
            min(max(1, apps.count), max(1, defaults?.object(forKey: "launcherRing\(index + 1)") as? Int ?? fallback))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.14)
        view.addSubview(shade)
        pageControl.isUserInteractionEnabled = false
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        selectionPreview.backgroundColor = .systemGray5
        selectionPreview.contentMode = .scaleAspectFill
        selectionPreview.layer.cornerRadius = 26
        selectionPreview.layer.borderWidth = 6
        selectionPreview.layer.borderColor = UIColor.systemGray5.cgColor
        selectionPreview.clipsToBounds = true
        selectionPreview.isUserInteractionEnabled = false
        selectionPreview.alpha = 0
        view.addSubview(selectionPreview)
        brightnessOverlay.backgroundColor = .secondarySystemBackground
        brightnessOverlay.layer.cornerRadius = 30
        brightnessOverlay.isHidden = true
        let sun = UIImageView(image: UIImage(systemName: "sun.max.fill"))
        sun.tintColor = .label
        sun.contentMode = .scaleAspectFit
        sun.frame = CGRect(x: 42, y: 22, width: 28, height: 28)
        brightnessOverlay.addSubview(sun)
        brightnessTrack.backgroundColor = .systemGray4
        brightnessTrack.layer.cornerRadius = 22
        brightnessTrack.clipsToBounds = true
        brightnessTrack.frame = CGRect(x: 34, y: 64, width: 44, height: 172)
        brightnessOverlay.addSubview(brightnessTrack)
        brightnessFill.backgroundColor = .label
        brightnessTrack.addSubview(brightnessFill)
        brightnessPercent.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        brightnessPercent.textAlignment = .center
        brightnessPercent.frame = CGRect(x: 0, y: 252, width: 112, height: 24)
        brightnessOverlay.addSubview(brightnessPercent)
        view.addSubview(brightnessOverlay)
        if apps.isEmpty {
            let label = UILabel()
            label.text = "请先在设置中添加应用"
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .body)
            label.textAlignment = .center
            label.frame = CGRect(x: 20, y: view.bounds.midY - 30,
                                 width: view.bounds.width - 40, height: 60)
            label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
            view.addSubview(label)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shade.frame = view.bounds
        pageControl.frame = CGRect(x: view.bounds.width - 110,
                                   y: min(view.bounds.maxY - 42,
                                          handleCenterY + min(300, view.bounds.height * 0.38)),
                                   width: 100, height: 26)
        selectionPreview.frame = CGRect(x: view.bounds.midX - 55,
                                        y: max(view.safeAreaInsets.top + 24, view.bounds.height * 0.2 - 55),
                                        width: 110, height: 110)
        brightnessOverlay.frame = CGRect(x: view.bounds.midX - 56,
                                         y: view.bounds.midY - 148, width: 112, height: 296)
        guard lastSize != view.bounds.size else { return }
        lastSize = view.bounds.size
        layoutPage()
    }

    func setProgress(_ progress: CGFloat) {
        self.progress = min(1, max(0, progress))
        shade.alpha = self.progress
        for (index, button) in buttons.enumerated() {
            let step = CGFloat(buttonRings[index]) * 0.12
            let amount = min(1, max(0, (self.progress - step) / (1 - step)))
            button.alpha = amount
            button.transform = CGAffineTransform(translationX: (handleCenterX - button.center.x) * (1 - amount),
                                                 y: (handleCenterY - button.center.y) * (1 - amount))
                .scaledBy(x: 0.72 + 0.28 * amount, y: 0.72 + 0.28 * amount)
        }
        pageControl.alpha = self.progress
        selectionPreview.alpha = selectedIndex == nil ? 0 : self.progress
    }

    private func layoutPage() {
        holdFeedbackTask?.cancel()
        selectedIndex = nil
        selectedSince = nil
        selectionPreview.alpha = 0
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        buttonRings.removeAll()
        let size = iconSize
        let spacing = size + 10
        let centerY = handleCenterY == 0 ? view.bounds.midY : handleCenterY
        let maxRadius = min(view.bounds.width - size - edgeInset - 16,
                            min(centerY - view.safeAreaInsets.top - size / 2 - 12,
                                view.bounds.maxY - view.safeAreaInsets.bottom - centerY - size / 2 - 12))
        let angle: CGFloat = .pi / 2
        var rings: [(count: Int, radius: CGFloat)] = []
        var previousRadius: CGFloat = 0
        for requested in ringCounts {
            let desiredRadius = requested == 1 ? 0 :
                spacing / (2 * sin(.pi / (2 * CGFloat(requested - 1))))
            let radius = max(size * 1.2,
                             max(previousRadius + (rings.isEmpty ? 0 : spacing),
                                 min(desiredRadius, maxRadius)))
            guard radius <= maxRadius else { break }
            let fits = radius + 0.01 >= desiredRadius ? requested :
                Int((.pi / (2 * asin(min(1, spacing / (2 * radius))))).rounded(.down)) + 1
            rings.append((min(requested, fits), radius))
            previousRadius = radius
        }
        pageCapacity = max(1, rings.reduce(0) { $0 + $1.count })
        pageControl.numberOfPages = max(1, (apps.count + pageCapacity - 1) / pageCapacity)
        page = min(page, pageControl.numberOfPages - 1)
        pageControl.currentPage = page
        var appIndex = page * pageCapacity
        let end = min(apps.count, appIndex + pageCapacity)
        let centerX = view.bounds.maxX - size / 2 - edgeInset
        for (ringIndex, ring) in rings.enumerated() {
            let count = min(ring.count, end - appIndex)
            guard count > 0 else { break }
            for slot in 0..<count {
                let theta = count == 1 ? 0 : -angle + 2 * angle * CGFloat(slot) / CGFloat(count - 1)
                let center = CGPoint(x: centerX - ring.radius * cos(theta),
                                     y: centerY + ring.radius * sin(theta))
                let button = UIButton(type: .custom)
                button.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                      width: size, height: size)
                button.tag = appIndex
                button.accessibilityLabel = apps[appIndex].name
                let id = apps[appIndex].id
                let action = isShortcut(id) && !id.hasPrefix("px.recent.") ||
                    (id.hasPrefix("px.recent.") && id.split(separator: ".", maxSplits: 3).count < 4)
                let active = action && PXSceneBridge.shared().shortcutIsActive(id)
                button.backgroundColor = active ? UIColor(white: 0.42, alpha: 1) : .systemGray5
                button.layer.cornerRadius = size / 2
                button.layer.shadowColor = UIColor.black.cgColor
                button.layer.shadowOpacity = 0.12
                button.layer.shadowRadius = 5
                button.layer.shadowOffset = CGSize(width: 0, height: 2)
                let icon = UIImageView(image: panelIcon(id)?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: size * 0.43, weight: .medium)) ?? UIImage(systemName: "app"))
                icon.frame = button.bounds.insetBy(dx: 4, dy: 4)
                icon.tintColor = active ? .white : .label
                icon.contentMode = action ? .center : .scaleAspectFill
                icon.layer.cornerRadius = (size - 8) / 2
                icon.clipsToBounds = true
                icon.isUserInteractionEnabled = false
                button.addSubview(icon)
                view.addSubview(button)
                buttons.append(button)
                buttonRings.append(ringIndex)
                appIndex += 1
            }
        }
        view.bringSubviewToFront(selectionPreview)
        setProgress(progress)
    }

    func advancePage(forDrag verticalDistance: CGFloat) {
        let next = min(pageControl.numberOfPages - 1, max(0, Int(-verticalDistance / 150)))
        guard next > page else { return }
        page = next
        layoutPage()
    }

    func updateSelection(at point: CGPoint) -> String? {
        lastSelectionPoint = point
        let hit = buttons.reversed().first {
            $0.frame.insetBy(dx: -4, dy: -4).contains(point)
        }
        let next = hit?.tag
        if next != selectedIndex {
            holdFeedbackTask?.cancel()
            if let selectedIndex = selectedIndex,
               let old = buttons.first(where: { $0.tag == selectedIndex }) {
                UIView.animate(withDuration: 0.16) { old.subviews.first?.transform = .identity }
            }
            selectedIndex = next
            selectedSince = (next.map { isShortcut(apps[$0].id) } ?? true) ? nil : CACurrentMediaTime()
            if let hit = hit, let next = next {
                selectionFeedback.selectionChanged()
                selectionFeedback.prepare()
                let id = apps[next].id
                if !isShortcut(id) || id == "px.action.brightness" {
                    holdFeedback.prepare()
                    let task = DispatchWorkItem { [weak self] in
                        guard let self = self, self.selectedIndex == next else { return }
                        if id == "px.action.brightness" {
                            self.onBrightnessHold?(self.lastSelectionPoint)
                        } else { self.holdFeedback.impactOccurred() }
                    }
                    holdFeedbackTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
                }
                selectionPreview.image = panelIcon(id)?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 52, weight: .medium)) ?? UIImage(systemName: "app")
                let symbol = !id.hasPrefix("px.recent.") || id.split(separator: ".", maxSplits: 3).count < 4
                selectionPreview.contentMode = isShortcut(id) && symbol ? .center : .scaleAspectFill
                selectionPreview.tintColor = PXSceneBridge.shared().shortcutIsActive(id) ? .white : .label
                selectionPreview.backgroundColor = PXSceneBridge.shared().shortcutIsActive(id) ?
                    UIColor(white: 0.42, alpha: 1) : .systemGray5
                selectionPreview.transform = CGAffineTransform(scaleX: 0.76, y: 0.76)
                UIView.animate(withDuration: 0.28, delay: 0,
                               usingSpringWithDamping: 0.72, initialSpringVelocity: 0,
                               options: .beginFromCurrentState) {
                    hit.subviews.first?.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                    self.selectionPreview.transform = .identity
                    self.selectionPreview.alpha = self.progress
                }
            } else {
                UIView.animate(withDuration: 0.12) { self.selectionPreview.alpha = 0 }
            }
        }
        return next.map { apps[$0].id }
    }

    var selectedDuration: CFTimeInterval {
        selectedSince.map { CACurrentMediaTime() - $0 } ?? 0
    }

    func cancelSelectionFeedback() { holdFeedbackTask?.cancel() }

    func showBrightness(_ value: CGFloat) {
        cancelSelectionFeedback()
        buttons.forEach { $0.alpha = 0 }
        selectionPreview.alpha = 0
        pageControl.alpha = 0
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        brightnessOverlay.isHidden = false
        updateBrightness(value)
    }

    func updateBrightness(_ value: CGFloat) {
        let amount = min(1, max(0, value))
        let height = brightnessTrack.bounds.height * amount
        brightnessFill.frame = CGRect(x: 0, y: brightnessTrack.bounds.height - height,
                                      width: brightnessTrack.bounds.width, height: height)
        brightnessPercent.text = "亮度 \(Int((amount * 100).rounded()))%"
    }

    func animateClosed(completion: @escaping () -> Void) {
        cancelSelectionFeedback()
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.25
        let outer = buttonRings.max() ?? 0
        for (index, button) in buttons.enumerated() {
            UIView.animate(withDuration: duration, delay: Double(outer - buttonRings[index]) * 0.035,
                           options: [.curveEaseIn, .beginFromCurrentState]) {
                button.alpha = 0
                button.transform = CGAffineTransform(translationX: self.handleCenterX - button.center.x,
                                                     y: self.handleCenterY - button.center.y)
                    .scaledBy(x: 0.72, y: 0.72)
            }
        }
        UIView.animate(withDuration: duration + Double(outer) * 0.035) {
            self.shade.alpha = 0
            self.pageControl.alpha = 0
            self.selectionPreview.alpha = 0
            self.brightnessOverlay.alpha = 0
        } completion: { _ in completion() }
    }
}

@objc(PXPanelEntry)
public final class PXPanelEntry: NSObject {
    private static let shared = PXPanelEntry()
    private var handleWindow: PXHandleWindow?
    private var panelWindow: UIWindow?
    private var hostWindow: UIWindow?
    private var hostCard: UIView?
    private var hostCorners: [UIView] = []
    private var hostTopCorners: [UIView] = []
    private var dockedHosts: [PXDockedHost] = []
    private var activeBridge: PXSceneBridge = .shared()
    private var hostMoveGrip: UIView?
    private weak var hostCanvas: UIView?
    private var panel: PXPanelViewController?
    private var handle: UIView?
    private var hostedBundleID: String?
    private var panelFrontmostBundleID: String?
    private var resizeStartFrame: CGRect?
    private var resizeStartRadius: CGFloat = 0
    private var resizeLink: CADisplayLink?
    private var resizePreview: (scale: CGFloat, x: CGFloat, y: CGFloat)?
    private var moveStartFrame: CGRect?
    private var needsHostRefresh = false
    private var deviceLocked = false
    private var panelDragProgress: CGFloat = 0
    private var handleDragMode = 0 // 0 undecided, 1 panel, 2 vertical placement
    private var handleDragStartY: CGFloat = 0
    private var brightnessStart: (y: CGFloat, value: CGFloat)?

    @objc public static func start() {
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
        shared.installHandle()
        NotificationCenter.default.addObserver(shared,
            selector: #selector(lockStateChanged), name: Notification.Name("PXLockStateChanged"), object: nil)
    }

    @objc public static func applicationActivated(_ bundleID: String) {
        DispatchQueue.main.async {
            for dock in shared.dockedHosts.filter({ $0.bundleID == bundleID }) {
                shared.removeDock(dock, fullscreenHandoff: true)
            }
        }
    }

    @objc private func lockStateChanged(_ notification: Notification) {
        let locked = notification.userInfo?["locked"] as? Bool ?? false
        guard locked != deviceLocked else { return }
        deviceLocked = locked
        if locked {
            if UserDefaults(suiteName: preferenceDomain)?.bool(forKey: "clearOnLock") == true {
                closeHost(animated: false)
                for dock in Array(dockedHosts) { removeDock(dock) }
                return
            }
            hostWindow?.isHidden = true
            if hostWindow != nil {
                needsHostRefresh = true
                activeBridge.close()
            }
            for dock in dockedHosts {
                dock.window.isHidden = true
                dock.overlay.isHidden = true
                dock.bridge.close()
            }
        } else {
            refreshHost()
            guard let controls = handleWindow?.rootViewController?.view else { return }
            for dock in dockedHosts {
                dock.bridge.openApplication(dock.bundleID, in: dock.canvas,
                                            keyboardOverlay: controls) { [weak self, weak dock] success in
                    guard let dock = dock, self?.dockedHosts.contains(where: { $0 === dock }) == true else { return }
                    if success {
                        dock.window.isHidden = false
                        dock.overlay.isHidden = false
                        dock.bridge.layoutHost()
                    } else { self?.removeDock(dock) }
                }
            }
        }
    }

    @objc private func sceneDeactivated(_ notification: Notification) {
        if (notification.object as? UIWindowScene) === hostWindow?.windowScene {
            needsHostRefresh = true
        }
    }

    @objc private func sceneActivated(_ notification: Notification) {
        installHandle()
        if (notification.object as? UIWindowScene) === hostWindow?.windowScene { refreshHost() }
        if !dockedHosts.isEmpty { layoutDocks() }
    }

    private func refreshHost() {
        guard !deviceLocked, needsHostRefresh, let window = hostWindow,
              let bundleID = hostedBundleID, let canvas = hostCanvas,
              let controls = handleWindow?.rootViewController?.view else { return }
        needsHostRefresh = false
        activeBridge.openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            if success {
                self.activeBridge.layoutHost()
                self.hostCard?.alpha = 1
                self.hostCard?.transform = .identity
                window?.isUserInteractionEnabled = true
                window?.isHidden = false
            }
            else { self.closeHost(animated: false) }
        }
    }

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func installHandle() {
        if handleWindow != nil { updateHandleAppearance(); return }
        guard let scene = activeScene() else { return }
        let window = PXHandleWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar - 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        let pill = UIView(frame: .zero)
        pill.backgroundColor = .secondarySystemBackground
        pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth = 1 / UIScreen.main.scale
        pill.layer.borderColor = UIColor.separator.cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.18
        pill.layer.shadowRadius = 6
        pill.layer.shadowOffset = CGSize(width: -2, height: 1)
        pill.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        let mark = UIView(frame: .zero)
        mark.backgroundColor = UIColor.label.withAlphaComponent(0.55)
        mark.layer.cornerRadius = 2
        pill.addSubview(mark)
        pill.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
        root.view.addSubview(pill)
        window.isHidden = false
        handle = pill
        handleWindow = window
        updateHandleAppearance()
    }

    private func updateHandleAppearance() {
        guard let window = handleWindow, let pill = handle else { return }
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let width = min(52, max(12, CGFloat(defaults?.object(forKey: "handleWidth") as? Int ?? 24)))
        let height = min(160, max(44, CGFloat(defaults?.object(forKey: "handleHeight") as? Int ?? 86)))
        window.frame = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let fraction = min(0.78, max(0.22,
            CGFloat(defaults?.object(forKey: "handleCenterFraction") as? Double ?? 0.5)))
        pill.frame = CGRect(x: window.bounds.maxX - width,
                            y: window.bounds.height * fraction - height / 2, width: width, height: height)
        pill.layer.cornerRadius = min(width / 2, 16)
        let markHeight = height * 0.46
        pill.subviews.first?.frame = CGRect(x: (width - 4) / 2,
                                           y: (height - markHeight) / 2,
                                           width: 4, height: markHeight)
    }

    private func selectedApps() -> [(id: String, name: String)] {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let ids = defaults?.stringArray(forKey: "applications") ?? []
        let names = defaults?.dictionary(forKey: "applicationNames") as? [String: String] ?? [:]
        let excluded = ids.filter { !isShortcut($0) }
        return ids.flatMap { id -> [(id: String, name: String)] in
            if id == "px.action.recent" {
                let count = min(20, max(1, defaults?.integer(forKey: "recentAppRank") ?? 1))
                return (1...count).map { rank in
                    let bundleID = PXSceneBridge.shared().recentApplicationSkipping(excluded, rank: rank)
                    return (id: bundleID.map { "px.recent.\(rank).\($0)" } ?? "px.recent.\(rank)",
                            name: bundleID ?? "最近应用为空")
                }
            }
            return [(id: id, name: names[id] ?? shortcuts.first(where: { $0.id == id })?.name ?? id)]
        }
    }

    private func beginPanel() {
        guard panelWindow == nil, let scene = handleWindow?.windowScene else { return }
        panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        let controller = PXPanelViewController()
        controller.apps = selectedApps()
        controller.handleCenterY = handle?.center.y ?? window.bounds.midY
        controller.handleCenterX = handle?.center.x ?? window.bounds.maxX
        let holdMillis = UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "launcherHoldMilliseconds") as? Int ?? 700
        controller.holdDuration = Double(min(2000, max(300, holdMillis))) / 1000
        controller.onBrightnessHold = { [weak self, weak controller] point in
            guard let self = self, self.handleDragMode == 1 else { return }
            let value = CGFloat(UIScreen.main.brightness)
            self.brightnessStart = (point.y, value)
            controller?.showBrightness(value)
        }
        window.rootViewController = controller
        _ = controller.view
        controller.view.layoutIfNeeded()
        controller.setProgress(0)
        window.isHidden = false
        window.isUserInteractionEnabled = false
        panel = controller
        panelWindow = window
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let root = handleWindow?.rootViewController?.view, let pill = handle else { return }
        let translation = gesture.translation(in: root)
        let distance = -translation.x
        let savedDistance = UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "launcherDragDistance") as? Int ?? 120
        let threshold = min(240, max(10, CGFloat(savedDistance)))
        switch gesture.state {
        case .began:
            panelDragProgress = 0
            brightnessStart = nil
            handleDragMode = 0
            handleDragStartY = pill.center.y
            fallthrough
        case .changed:
            if handleDragMode == 0, max(abs(translation.x), abs(translation.y)) > 5 {
                handleDragMode = abs(translation.y) > abs(translation.x) ? 2 : 1
                if handleDragMode == 1 { beginPanel() }
            }
            if handleDragMode == 2 {
                pill.center.y = min(root.bounds.height * 0.78,
                                    max(root.bounds.height * 0.22, handleDragStartY + translation.y))
                return
            }
            guard handleDragMode == 1 else { return }
            if let start = brightnessStart, let controller = panel {
                let y = gesture.location(in: controller.view).y
                let value = min(1, max(0, start.value + (start.y - y) / (root.bounds.height * 0.45)))
                controller.updateBrightness(value)
                _ = PXSceneBridge.shared().setBrightnessLevel(Float(value))
                return
            }
            panelDragProgress = max(panelDragProgress, min(1, max(0, distance / threshold)))
            panel?.setProgress(panelDragProgress)
            if panelDragProgress >= 0.8 {
                panel?.advancePage(forDrag: gesture.translation(in: root).y)
                if let controller = panel {
                    _ = controller.updateSelection(at: gesture.location(in: controller.view))
                }
            }
        case .ended:
            if brightnessStart != nil {
                brightnessStart = nil
                hidePanel()
                return
            }
            if handleDragMode == 2 {
                UserDefaults(suiteName: preferenceDomain)?.set(Double(pill.center.y / root.bounds.height),
                                                                  forKey: "handleCenterFraction")
                handleDragMode = 0
                return
            }
            if panelDragProgress >= 0.8,
               let controller = panel,
               let bundleID = controller.updateSelection(at: gesture.location(in: controller.view)) {
                let fullscreen = controller.selectedDuration >= controller.holdDuration
                if isShortcut(bundleID) {
                    hidePanel { [weak self] in self?.performShortcut(bundleID) }
                } else {
                    hidePanel()
                    if fullscreen {
                        if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped() }
                        else if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
                            restoreDock(dock)
                            fullscreenTapped()
                        }
                        else { _ = PXSceneBridge.shared().openFullscreenApplication(bundleID) }
                    } else { openHost(bundleID) }
                }
            } else { hidePanel() }
        case .cancelled, .failed:
            brightnessStart = nil
            if handleDragMode == 2 { updateHandleAppearance() }
            hidePanel()
        default: break
        }
    }

    private func hidePanel(_ completion: (() -> Void)? = nil) {
        guard let window = panelWindow, let controller = panel else {
            completion?()
            return
        }
        window.isUserInteractionEnabled = false
        controller.animateClosed { [weak self] in
            guard let self = self, self.panelWindow === window else { return }
            window.isHidden = true
            window.rootViewController = nil
            self.panelWindow = nil
            self.panel = nil
            self.handleWindow?.isHidden = false
            completion?()
        }
    }

    private func openHost(_ bundleID: String) {
        if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
            restoreDock(dock)
            return
        }
        let wasFullscreen = panelFrontmostBundleID == bundleID
        panelFrontmostBundleID = nil
        presentHost(bundleID, wasFullscreen: wasFullscreen)
    }

    private func performShortcut(_ id: String) {
        if id == "px.action.brightness" { return }
        if id.hasPrefix("px.recent.") {
            let parts = id.split(separator: ".", maxSplits: 3)
            if parts.count == 4 { openHost(String(parts[3])) }
        } else if id == "px.action.screenshot" &&
                    UserDefaults(suiteName: preferenceDomain)?.bool(forKey: "hideForScreenshot") == true {
            handleWindow?.isHidden = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                _ = PXSceneBridge.shared().performShortcut(id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if self?.deviceLocked == false { self?.handleWindow?.isHidden = false }
                }
            }
        } else if id.hasPrefix("px.url."),
                  let entries = UserDefaults(suiteName: preferenceDomain)?.array(forKey: "urlShortcuts") as? [[String: String]],
                  let text = entries.first(where: { $0["id"] == id })?["url"],
                  let url = URL(string: text) {
            UIApplication.shared.open(url)
        } else if id == "px.action.window" {
            if hostWindow != nil { fullscreenTapped() }
            else if let frontmost = PXSceneBridge.shared().frontmostBundleID() { openHost(frontmost) }
        } else {
            _ = PXSceneBridge.shared().performShortcut(id)
        }
    }

    private func presentHost(_ bundleID: String, wasFullscreen: Bool) {
        guard let scene = activeScene(),
              let controls = handleWindow?.rootViewController?.view else { return }
        closeHost(animated: false)
        hostedBundleID = bundleID
        let screen = scene.coordinateSpace.bounds
        let width = screen.width * 0.78
        let height = width * screen.height / screen.width
        let cardFrame = CGRect(x: (screen.width - width) / 2,
                           y: (screen.height - height) / 2,
                           width: width, height: height)
        let window = PXHandleWindow(windowScene: scene)
        window.frame = CGRect(x: cardFrame.minX - gripMargin, y: cardFrame.minY - gripTop,
                              width: width + 2 * gripMargin, height: height + gripTop + gripBottom)
        window.windowLevel = .statusBar - 2
        window.backgroundColor = .clear
        let root = PXHostViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        let card = UIView(frame: CGRect(x: gripMargin, y: gripTop, width: width, height: height))
        card.backgroundColor = .secondarySystemBackground
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let savedRadius = defaults?.object(forKey: "cornerRadius") as? NSNumber
        card.layer.cornerRadius = CGFloat(min(60, max(0, savedRadius?.doubleValue ?? 20)))
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        let strength = Float(min(50, max(0, defaults?.object(forKey: "shadowStrength") as? Int ?? 22))) / 100
        let blur = CGFloat(min(24, max(0, defaults?.object(forKey: "shadowBlur") as? Int ?? 15)))
        let dark = card.traitCollection.userInterfaceStyle == .dark
        card.layer.shadowColor = dark ? UIColor(white: 1, alpha: 1).cgColor : UIColor.black.cgColor
        card.layer.shadowOpacity = dark ? min(0.35, strength * 0.8) : strength
        card.layer.shadowRadius = dark ? blur + 4 : blur
        card.layer.shadowOffset = CGSize(width: 0, height: 3)
        root.view.addSubview(card)
        let clip = UIView(frame: card.bounds)
        clip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clip.layer.cornerRadius = card.layer.cornerRadius
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        card.addSubview(clip)
        let canvas = UIView(frame: clip.bounds)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clip.addSubview(canvas)
        hostCanvas = canvas
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.center = CGPoint(x: width / 2, y: height / 2)
        spinner.startAnimating()
        card.addSubview(spinner)
        let coldStart = !activeBridge.hasScene(forApplication: bundleID)
        let debug = defaults?.bool(forKey: "gestureDebug") == true
        for side in [-1, 1] {
            let corner = UIView(frame: .zero)
            corner.tag = side
            corner.isOpaque = false
            corner.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) :
                UIColor(white: 1, alpha: 0.02)
            corner.isUserInteractionEnabled = true
            corner.isAccessibilityElement = true
            corner.accessibilityLabel = "拖动调整窗口大小"
            corner.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                               action: #selector(resizeHost(_:))))
            root.view.addSubview(corner)
            hostCorners.append(corner)
            let top = UIControl(frame: .zero)
            top.tag = side
            top.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) :
                UIColor(white: 1, alpha: 0.02)
            top.isAccessibilityElement = true
            top.accessibilityLabel = side < 0 ? "停靠到左上角" : "停靠到右上角"
            let mark = UIImageView(image: UIImage(systemName: "arrow.down.right.and.arrow.up.left"))
            mark.frame = CGRect(x: 12, y: 12, width: 20, height: 20)
            mark.tintColor = .secondaryLabel
            top.addSubview(mark)
            top.addTarget(self, action: #selector(dockTapped(_:)), for: .touchUpInside)
            root.view.addSubview(top)
            hostTopCorners.append(top)
        }
        let moveGrip = UIView(frame: .zero)
        moveGrip.backgroundColor = UIColor(white: 1, alpha: 0.02)
        if debug {
            moveGrip.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
            moveGrip.layer.borderColor = UIColor.systemBlue.cgColor
            moveGrip.layer.borderWidth = 1
        }
        moveGrip.isAccessibilityElement = true
        moveGrip.accessibilityLabel = "拖动移动；双击关闭；长按全屏"
        moveGrip.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                              action: #selector(moveHost(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        doubleTap.numberOfTapsRequired = 2
        moveGrip.addGestureRecognizer(doubleTap)
        moveGrip.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                   action: #selector(moveGripHeld(_:))))
        root.view.addSubview(moveGrip)
        hostMoveGrip = moveGrip
        root.onLayout = { [weak self] in self?.layoutHostControls() }
        window.isHidden = false
        hostWindow = window
        hostCard = card
        layoutHostControls()
        window.isUserInteractionEnabled = false
        card.transform = CGAffineTransform(scaleX: wasFullscreen ? 1.1 : 0.84,
                                            y: wasFullscreen ? 1.1 : 0.84)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.5,
                       delay: 0, usingSpringWithDamping: 0.84,
                       initialSpringVelocity: 0, options: .beginFromCurrentState) {
            card.transform = .identity
        }
        activeBridge.openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            spinner.stopAnimating()
            guard success else { self.closeHost(animated: false); return }
            if let preview = card.subviews.first(where: { $0.tag == 0x50584c }) {
                UIView.animate(withDuration: 0.18, animations: { preview.alpha = 0 }) { _ in
                    preview.removeFromSuperview()
                }
            }
            self.matchHostAspect()
            self.activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen) { [weak self, weak window] ready in
                guard let self = self, self.hostWindow === window else { return }
                guard ready else { self.closeHost(animated: false); return }
                window?.isUserInteractionEnabled = true
                self.layoutHostControls()
            }
        }
        if coldStart, let image = activeBridge.launchImage(forApplication: bundleID, size: card.bounds.size),
           hostWindow === window {
            let preview = UIImageView(image: image)
            preview.tag = 0x50584c
            preview.frame = card.bounds
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            preview.contentMode = .scaleToFill
            preview.layer.cornerRadius = card.layer.cornerRadius
            preview.clipsToBounds = true
            preview.isUserInteractionEnabled = false
            card.addSubview(preview)
        }
    }

    private func matchHostAspect() {
        guard let window = hostWindow, let card = hostCard else { return }
        let source = activeBridge.hostedSourceSize()
        guard source.width > 0, source.height > 0 else { return }
        let screen = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let width = min(screen.width * 0.78,
                        (screen.height - 80) * source.width / source.height)
        let height = width * source.height / source.width
        window.frame = CGRect(x: screen.midX - width / 2 - gripMargin,
                              y: screen.midY - height / 2 - gripTop,
                              width: width + 2 * gripMargin, height: height + gripTop + gripBottom)
        card.frame = CGRect(x: gripMargin, y: gripTop, width: width, height: height)
        card.layoutIfNeeded()
        layoutHostControls()
        activeBridge.layoutHost()
    }

    private func layoutHostControls() {
        guard let card = hostCard, hostWindow != nil else { return }
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let strength = Float(min(50, max(0, defaults?.object(forKey: "shadowStrength") as? Int ?? 22))) / 100
        let blur = CGFloat(min(24, max(0, defaults?.object(forKey: "shadowBlur") as? Int ?? 15)))
        let dark = card.traitCollection.userInterfaceStyle == .dark
        card.layer.shadowColor = dark ? UIColor(white: 1, alpha: 1).cgColor : UIColor.black.cgColor
        card.layer.shadowOpacity = dark ? min(0.35, strength * 0.8) : strength
        card.layer.shadowRadius = dark ? blur + 4 : blur
        if card.layer.shadowPath?.boundingBox != card.bounds {
            card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds,
                                                  cornerRadius: card.layer.cornerRadius).cgPath
        }
        let frame = card.frame
        for corner in hostCorners {
            let radius = max(CGFloat(12), card.layer.cornerRadius)
            let center = CGPoint(x: corner.tag < 0 ? frame.minX + radius : frame.maxX - radius,
                                 y: frame.maxY - radius)
            let middle: CGFloat = corner.tag < 0 ? 3 * .pi / 4 : .pi / 4
            let arcRadius = radius + 3
            let midpoint = CGPoint(x: center.x + arcRadius * cos(middle),
                                   y: center.y + arcRadius * sin(middle))
            corner.frame = CGRect(x: midpoint.x - 22, y: midpoint.y - 22, width: 44, height: 44)
        }
        for corner in hostTopCorners {
            corner.frame = CGRect(x: corner.tag < 0 ? frame.minX - 12 : frame.maxX - 32,
                                  y: frame.minY - 12, width: 44, height: 44)
        }
        let width = min(360, max(120, CGFloat(truncating: defaults?.object(forKey: "gestureWidth") as? NSNumber ?? 300)))
        let height = min(120, max(36, CGFloat(truncating: defaults?.object(forKey: "gestureHeight") as? NSNumber ?? 80)))
        let offset = min(40, max(-30, CGFloat(truncating: defaults?.object(forKey: "gestureOffset") as? NSNumber ?? 0)))
        hostMoveGrip?.frame = CGRect(x: frame.midX - width / 2, y: frame.maxY + offset,
                                     width: width, height: height)
    }

    @objc private func dockTapped(_ sender: UIControl) {
        guard dockedHosts.count < min(4, max(1, UserDefaults(suiteName: preferenceDomain)?
            .integer(forKey: "dockCount") ?? 2)) else { return }
        parkMain(side: sender.tag)
    }

    @discardableResult private func parkMain(side: Int) -> Bool {
        guard let window = hostWindow, let card = hostCard, let canvas = hostCanvas,
              let bundleID = hostedBundleID,
              let controls = handleWindow?.rootViewController?.view else { return false }
        let overlay = UIView(frame: window.frame)
        overlay.backgroundColor = UIColor(white: 1, alpha: 0.02)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(restoreDockTapped(_:))))
        for direction in [UISwipeGestureRecognizer.Direction.up, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dockSwiped(_:)))
            swipe.direction = direction
            overlay.addGestureRecognizer(swipe)
        }
        controls.addSubview(overlay)
        window.isUserInteractionEnabled = false
        canvas.isUserInteractionEnabled = false
        activeBridge.setHostedInteractionEnabled(false)
        let dock = PXDockedHost(window: window, card: card, canvas: canvas,
                                bridge: activeBridge, bundleID: bundleID, side: side,
                                corners: hostCorners, topCorners: hostTopCorners,
                                moveGrip: hostMoveGrip, overlay: overlay)
        dockedHosts.append(dock)
        (hostCorners + hostTopCorners + [hostMoveGrip].compactMap { $0 }).forEach { $0.isHidden = true }
        hostWindow = nil
        hostCard = nil
        hostCanvas = nil
        hostCorners = []
        hostTopCorners = []
        hostMoveGrip = nil
        hostedBundleID = nil
        activeBridge = PXSceneBridge()
        layoutDocks()
        return true
    }

    private func layoutDocks() {
        let screen = activeScene()?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let count = max(1, dockedHosts.count)
        let top = max(50, activeScene()?.windows.first?.safeAreaInsets.top ?? 50) + 12
        let available = max(120, screen.height - top - 40 - CGFloat(count - 1) * 12)
        let requested = CGFloat(UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "dockWidth") as? Int ?? 110)
        for (index, dock) in dockedHosts.enumerated() {
            let ratio = dock.sourceSize.height / max(1, dock.sourceSize.width)
            let width = min(max(64, requested), available / CGFloat(count) / max(1, ratio))
            let height = width * ratio
            let preceding = dockedHosts.prefix(index).reduce(CGFloat.zero) { sum, item in
                let r = item.sourceSize.height / max(1, item.sourceSize.width)
                return sum + min(max(64, requested), available / CGFloat(count) / max(1, r)) * r + 12
            }
            let frame = CGRect(x: dock.side < 0 ? 12 : screen.maxX - width - 12,
                               y: top + preceding, width: width, height: height)
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.86,
                           initialSpringVelocity: 0, options: .beginFromCurrentState) {
                dock.window.frame = frame
                dock.card.frame = CGRect(origin: .zero, size: frame.size)
                dock.overlay.frame = frame
                let radius = dock.originalCornerRadius * width / max(1, dock.originalCardFrame.width)
                dock.card.layer.cornerRadius = radius
                dock.card.subviews.first?.layer.cornerRadius = radius
                dock.card.layer.shadowPath = UIBezierPath(roundedRect: dock.card.bounds,
                                                          cornerRadius: radius).cgPath
                dock.card.layoutIfNeeded()
                dock.bridge.layoutHost()
            }
        }
    }

    @objc private func restoreDockTapped(_ sender: UITapGestureRecognizer) {
        guard let dock = dockedHosts.first(where: { $0.overlay === sender.view }) else { return }
        restoreDock(dock)
    }

    @objc private func dockSwiped(_ sender: UISwipeGestureRecognizer) {
        guard let dock = dockedHosts.first(where: { $0.overlay === sender.view }) else { return }
        if sender.direction == .up {
            removeDock(dock)
        } else {
            dock.side = sender.direction == .left ? -1 : 1
            layoutDocks()
        }
    }

    private func removeDock(_ dock: PXDockedHost, fullscreenHandoff: Bool = false) {
        dockedHosts.removeAll { $0 === dock }
        dock.overlay.removeFromSuperview()
        dock.window.isHidden = true
        if fullscreenHandoff { dock.bridge.closeForFullscreen() }
        else { dock.bridge.close() }
        dock.window.rootViewController = nil
        layoutDocks()
    }

    private func restoreDock(_ dock: PXDockedHost) {
        dockedHosts.removeAll { $0 === dock }
        if hostWindow != nil { parkMain(side: dock.side) }
        dock.overlay.removeFromSuperview()
        dock.window.isUserInteractionEnabled = true
        dock.canvas.isUserInteractionEnabled = true
        dock.bridge.setHostedInteractionEnabled(true)
        activeBridge = dock.bridge
        hostWindow = dock.window
        hostCard = dock.card
        hostCanvas = dock.canvas
        hostCorners = dock.corners
        hostTopCorners = dock.topCorners
        hostMoveGrip = dock.moveGrip
        hostedBundleID = dock.bundleID
        (hostCorners + hostTopCorners + [hostMoveGrip].compactMap { $0 }).forEach { $0.isHidden = false }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0, options: .beginFromCurrentState) {
            dock.window.frame = dock.originalFrame
            dock.card.frame = dock.originalCardFrame
            dock.card.layer.cornerRadius = dock.originalCornerRadius
            dock.card.subviews.first?.layer.cornerRadius = dock.originalCornerRadius
            dock.card.layer.shadowPath = UIBezierPath(roundedRect: dock.card.bounds,
                                                      cornerRadius: dock.originalCornerRadius).cgPath
            dock.card.layoutIfNeeded()
            self.activeBridge.layoutHost()
            self.layoutHostControls()
        }
        layoutDocks()
    }

    @objc private func closeTapped() { closeHost(animated: true) }

    @objc private func fullscreenTapped() {
        guard let bundleID = hostedBundleID, let window = hostWindow,
              let card = hostCard, let scene = window.windowScene else { return }
        let windowFrame = window.frame
        let cardFrame = card.frame
        let cornerRadius = card.layer.cornerRadius
        let shadowOpacity = card.layer.shadowOpacity
        let oldFrame = CGRect(x: window.frame.minX + card.frame.minX,
                              y: window.frame.minY + card.frame.minY,
                              width: card.bounds.width, height: card.bounds.height)
        hostCorners.forEach { $0.isHidden = true }
        hostMoveGrip?.isHidden = true
        window.isUserInteractionEnabled = false
        window.frame = scene.coordinateSpace.bounds
        card.frame = oldFrame
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.48,
                       delay: 0, usingSpringWithDamping: 0.88,
                       initialSpringVelocity: 0, options: .beginFromCurrentState) {
            let screen = scene.coordinateSpace.bounds
            card.transform = CGAffineTransform(scaleX: screen.width / oldFrame.width,
                                                y: screen.height / oldFrame.height)
            card.center = CGPoint(x: screen.midX, y: screen.midY)
            card.layer.cornerRadius = 0
            card.subviews.first?.layer.cornerRadius = 0
            card.layer.shadowOpacity = 0
        } completion: { [weak self, weak window] _ in
            guard let self = self, let window = window, self.hostWindow === window else { return }
            guard self.activeBridge.openFullscreenApplication(bundleID) else {
                card.transform = .identity
                card.frame = cardFrame
                card.layer.cornerRadius = cornerRadius
                card.subviews.first?.layer.cornerRadius = cornerRadius
                card.layer.shadowOpacity = shadowOpacity
                window.frame = windowFrame
                window.isUserInteractionEnabled = true
                self.hostCorners.forEach { $0.isHidden = false }
                self.hostMoveGrip?.isHidden = false
                self.layoutHostControls()
                return
            }
            var ticks = 0
            var readyTicks = 0
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak window] timer in
                guard let self = self, let window = window, self.hostWindow === window else {
                    timer.invalidate()
                    return
                }
                ticks += 1
                readyTicks = PXSceneBridge.shared().frontmostBundleID() == bundleID
                    ? readyTicks + 1 : 0
                if readyTicks >= 2 || ticks >= 15 {
                    timer.invalidate()
                    self.closeHost(animated: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func moveGripHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { fullscreenTapped() }
    }

    @objc private func resizeHost(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow, let card = hostCard else { return }
        if gesture.state == .began {
            resizeStartFrame = CGRect(x: window.frame.minX + gripMargin,
                                      y: window.frame.minY + gripTop, width: card.bounds.width,
                                      height: card.bounds.height)
            resizeStartRadius = card.layer.cornerRadius
            resizeLink?.invalidate()
            resizeLink = CADisplayLink(target: self, selector: #selector(applyResizePreview))
            resizeLink?.add(to: .main, forMode: .common)
        }
        guard let start = resizeStartFrame else { return }
        if gesture.state == .changed || gesture.state == .ended {
            let translation = gesture.translation(in: handleWindow)
            let horizontal = (gesture.view?.tag == -1 ? -translation.x : translation.x) / start.width
            let vertical = translation.y / start.height
            // Project both axes continuously; switching the dominant axis snaps the size.
            let change = (horizontal + vertical) / 2
            let screen = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
            let horizontalRoom = gesture.view?.tag == -1 ?
                start.maxX - screen.minX - 12 : screen.maxX - start.minX - 12
            let maximum = min(horizontalRoom / start.width,
                              (screen.maxY - start.minY - 20) / start.height)
            let scale = min(max(1 + change, 220 / start.width), max(220 / start.width, maximum))
            let size = CGSize(width: start.width * scale, height: start.height * scale)
            let x = gesture.view?.tag == -1 ? start.maxX - size.width : start.minX
            if gesture.state == .changed {
                resizePreview = (scale, x, start.minY)
            } else {
                resizeLink?.invalidate()
                resizeLink = nil
                resizePreview = nil
                UIView.performWithoutAnimation {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    window.transform = .identity
                    window.frame = CGRect(x: x - gripMargin, y: start.minY - gripTop,
                                          width: size.width + 2 * gripMargin,
                                          height: size.height + gripTop + gripBottom)
                    card.frame = CGRect(x: gripMargin, y: gripTop,
                                        width: size.width, height: size.height)
                    card.layer.cornerRadius = resizeStartRadius
                    card.layoutIfNeeded()
                    layoutHostControls()
                    activeBridge.layoutHost()
                    CATransaction.commit()
                }
            }
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            resizeLink?.invalidate()
            resizeLink = nil
            resizePreview = nil
            if gesture.state != .ended {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                window.transform = .identity
                window.frame = CGRect(x: start.minX - gripMargin, y: start.minY - gripTop,
                                      width: start.width + 2 * gripMargin,
                                      height: start.height + gripTop + gripBottom)
                card.layer.cornerRadius = resizeStartRadius
                CATransaction.commit()
            }
            resizeStartFrame = nil
        }
    }

    @objc private func applyResizePreview() {
        guard let window = hostWindow, let card = hostCard, let preview = resizePreview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.transform = CGAffineTransform(scaleX: preview.scale, y: preview.scale)
        window.center = CGPoint(x: preview.x - preview.scale * (gripMargin - window.bounds.midX),
                                y: preview.y - preview.scale * (gripTop - window.bounds.midY))
        card.layer.cornerRadius = resizeStartRadius / preview.scale
        CATransaction.commit()
    }

    @objc private func moveHost(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow else { return }
        if gesture.state == .began { moveStartFrame = window.frame }
        guard let start = moveStartFrame else { return }
        if gesture.state == .changed || gesture.state == .ended {
            let translation = gesture.translation(in: handleWindow)
            window.frame = start.offsetBy(dx: translation.x, dy: translation.y)
            layoutHostControls()
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            moveStartFrame = nil
        }
    }

    private func closeHost(animated: Bool) {
        guard let window = hostWindow else { return }
        let closingCard = hostCard
        resizeLink?.invalidate()
        resizeLink = nil
        resizePreview = nil
        hostCorners.forEach { $0.removeFromSuperview() }
        hostTopCorners.forEach { $0.removeFromSuperview() }
        hostMoveGrip?.removeFromSuperview()
        window.isUserInteractionEnabled = false
        hostWindow = nil
        hostCard = nil
        hostCanvas = nil
        hostCorners = []
        hostTopCorners = []
        hostMoveGrip = nil
        hostedBundleID = nil
        resizeStartFrame = nil
        moveStartFrame = nil
        needsHostRefresh = false
        let bridge = activeBridge
        let finish = { [weak self] in
            window.isHidden = true
            if self?.hostWindow == nil { bridge.close() }
            window.rootViewController = nil
        }
        if animated, let card = closingCard {
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.34,
                           delay: 0, usingSpringWithDamping: 0.88,
                           initialSpringVelocity: 0, options: .beginFromCurrentState) {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            } completion: { _ in finish() }
        } else { finish() }
    }
}
