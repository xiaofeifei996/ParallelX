import UIKit

private let preferenceDomain = "com.moxuan.parallelx"
private let gripMargin: CGFloat = 28
private let gripTop: CGFloat = 28
private let gripBottom: CGFloat = 168
private enum PXMotion {
    static func ease(_ duration: TimeInterval, delay: TimeInterval = 0,
                     options: UIView.AnimationOptions = .curveEaseOut,
                     animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : duration,
                       delay: UIAccessibility.isReduceMotionEnabled ? 0 : delay,
                       options: [options, .allowUserInteraction, .beginFromCurrentState],
                       animations: animations, completion: completion)
    }

    static func spring(_ duration: TimeInterval, animations: @escaping () -> Void,
                       completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : duration,
                       delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 2,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: animations, completion: completion)
    }
}
private let shortcuts: [(id: String, name: String, symbol: String)] = [
    ("px.action.dark", "深色模式", "moon.fill"),
    ("px.action.record", "屏幕录制", "record.circle"),
    ("px.action.rotation", "方向锁定", "lock.rotation"),
    ("px.action.window", "切换全屏/分屏", "rectangle.on.rectangle"),
    ("px.action.screenshot", "截屏", "camera.viewfinder"),
    ("px.action.recent", "最近打开的应用", "clock.arrow.circlepath"),
    ("px.action.kayoko", "呼出 Kayoko", "doc.on.clipboard"),
    ("px.action.brightness", "调节亮度", "sun.max.fill"),
    ("px.action.restart", "重新打开应用", "arrow.clockwise"),
    ("px.action.search", "搜索", "magnifyingglass")
]

private func isShortcut(_ id: String) -> Bool {
    id.hasPrefix("px.action.") || id.hasPrefix("px.url.") || id.hasPrefix("px.recent.") || id.hasPrefix("px.custom.")
}

private func configuredAction(_ id: String) -> [String: Any]? {
    (UserDefaults(suiteName: preferenceDomain)?.array(forKey: "customActions") as? [[String: Any]])?
        .first { $0["id"] as? String == id }
}

private func applicationID(_ id: String) -> String? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        return parts.count == 4 ? String(parts[3]) : nil
    }
    return isShortcut(id) ? nil : id
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
        let fallback = shortcuts.first(where: { $0.id == key })?.symbol ??
            (id.hasPrefix("px.custom.") ? "square.stack.3d.up" : "link")
        return UIImage(systemName: custom ?? fallback) ?? UIImage(systemName: fallback)
    }
    return PXApplicationIcon(id)
}

private func panelPreviewIcon(_ id: String) -> UIImage? {
    if id.hasPrefix("px.recent.") {
        let parts = id.split(separator: ".", maxSplits: 3)
        if parts.count == 4 { return PXApplicationIconLarge(String(parts[3])) }
    }
    return isShortcut(id) ? panelIcon(id) : PXApplicationIconLarge(id)
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
    private var fullscreenReadyView: UIView?
    private var groupMenu: UIView?
    private var groupScroll: UIScrollView?
    private var groupRows: [UILabel] = []
    private var groupItems: [[String: Any]] = []
    private var groupSelected: Int?
    private var groupOriginY: CGFloat = 0
    private var groupCancel: UILabel?
    var groupMenuActive: Bool { groupMenu != nil }
    private var page = 0
    private var pageCapacity = 1
    private var lastSize = CGSize.zero
    private var progress: CGFloat = 0
    private var opening = false
    private let defaults = UserDefaults(suiteName: preferenceDomain)
    private var iconSize: CGFloat {
        min(72, max(36, CGFloat(defaults?.object(forKey: "launcherIconSize") as? Int ?? 52)))
    }
    private var edgeInset: CGFloat {
        min(120, max(0, CGFloat(defaults?.object(forKey: "launcherEdgeInset") as? Int ?? 6)))
    }
    private var ringGap: CGFloat {
        min(60, max(0, CGFloat(defaults?.object(forKey: "launcherRingGap") as? Int ?? 10)))
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

    func completeOpening() {
        guard !opening else { return }
        opening = true
        PXMotion.spring(0.23) { self.setProgress(1) }
    }

    private func layoutPage() {
        cancelSelectionFeedback()
        selectedIndex = nil
        selectedSince = nil
        selectionPreview.alpha = 0
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        buttonRings.removeAll()
        let size = iconSize
        let spacing = size + 10
        let ringSpacing = size + ringGap
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
                             max(previousRadius + (rings.isEmpty ? 0 : ringSpacing),
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
            fullscreenReadyView?.removeFromSuperview()
            fullscreenReadyView = nil
            if let selectedIndex = selectedIndex,
               let old = buttons.first(where: { $0.tag == selectedIndex }) {
                PXMotion.ease(0.13) { old.subviews.first?.transform = .identity }
            }
            selectedIndex = next
            selectedSince = next.map { applicationID(apps[$0].id) != nil || apps[$0].id == "px.action.screenshot" } == true ? CACurrentMediaTime() : nil
            if let hit = hit, let next = next {
                selectionFeedback.selectionChanged()
                selectionFeedback.prepare()
                let id = apps[next].id
                let group = configuredAction(id)
                if applicationID(id) != nil || id == "px.action.brightness" || id == "px.action.screenshot" || group?["kind"] as? String == "group" {
                    holdFeedback.prepare()
                    let task = DispatchWorkItem { [weak self] in
                        guard let self = self, self.selectedIndex == next else { return }
                        self.holdFeedback.impactOccurred()
                        if id == "px.action.brightness" {
                            self.onBrightnessHold?(self.lastSelectionPoint)
                        } else if group?["kind"] as? String == "group" {
                            self.showGroupMenu(group?["items"] as? [[String: Any]] ?? [], at: self.lastSelectionPoint)
                        } else if applicationID(id) != nil {
                            self.animateFullscreenReady()
                        }
                    }
                    holdFeedbackTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
                }
                let symbol = isShortcut(id) && (!id.hasPrefix("px.recent.") ||
                    id.split(separator: ".", maxSplits: 3).count < 4)
                let preview = panelPreviewIcon(id)
                selectionPreview.image = (symbol ? preview?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 52, weight: .medium)) : preview) ??
                    UIImage(systemName: "app")
                selectionPreview.contentMode = symbol ? .center : .scaleAspectFill
                selectionPreview.tintColor = PXSceneBridge.shared().shortcutIsActive(id) ? .white : .label
                selectionPreview.backgroundColor = PXSceneBridge.shared().shortcutIsActive(id) ?
                    UIColor(white: 0.42, alpha: 1) : .systemGray5
                selectionPreview.transform = CGAffineTransform(scaleX: 0.76, y: 0.76)
                PXMotion.spring(0.23) {
                    hit.subviews.first?.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                    self.selectionPreview.transform = .identity
                    self.selectionPreview.alpha = self.progress
                }
            } else {
                PXMotion.ease(0.10) { self.selectionPreview.alpha = 0 }
            }
        }
        return next.map { apps[$0].id }
    }

    var selectedDuration: CFTimeInterval {
        selectedSince.map { CACurrentMediaTime() - $0 } ?? 0
    }

    private func animateFullscreenReady() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let trail = UIView(frame: view.bounds.insetBy(dx: 8, dy: 8))
        trail.isUserInteractionEnabled = false
        trail.backgroundColor = .clear
        trail.layer.cornerRadius = 40
        trail.layer.cornerCurve = .continuous
        trail.layer.borderWidth = 3
        trail.layer.borderColor = UIColor.label.withAlphaComponent(0.22).cgColor
        trail.transform = CGAffineTransform(translationX: selectionPreview.center.x - view.bounds.midX,
                                            y: selectionPreview.center.y - view.bounds.midY)
            .scaledBy(x: 110 / trail.bounds.width, y: 110 / trail.bounds.height)
        view.addSubview(trail)
        fullscreenReadyView = trail
        PXMotion.ease(0.32, animations: {
            trail.transform = .identity
            trail.alpha = 0
        }, completion: { [weak self, weak trail] _ in
            trail?.removeFromSuperview()
            if self?.fullscreenReadyView === trail { self?.fullscreenReadyView = nil }
        })
    }

    func cancelSelectionFeedback() {
        holdFeedbackTask?.cancel()
        fullscreenReadyView?.removeFromSuperview()
        fullscreenReadyView = nil
    }

    private func showGroupMenu(_ items: [[String: Any]], at point: CGPoint) {
        guard !items.isEmpty else { return }
        cancelSelectionFeedback()
        groupItems = items
        buttons.forEach { $0.alpha = 0 }
        selectionPreview.alpha = 0
        pageControl.alpha = 0
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        let menu = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        menu.layer.cornerRadius = 24
        menu.layer.cornerCurve = .continuous
        menu.layer.borderWidth = 1 / UIScreen.main.scale
        menu.layer.borderColor = UIColor.separator.cgColor
        menu.clipsToBounds = true
        let font = UIFont.preferredFont(forTextStyle: .body)
        let widest = items.map { (($0["title"] as? String ?? "快捷指令") as NSString)
            .size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(view.bounds.width - 48, max(150, ceil(widest) + 32))
        let availableHeight = max(96, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 20)
        let height = min(availableHeight, CGFloat(min(6, items.count)) * 52 + 104)
        let top = view.safeAreaInsets.top + 10
        let bottom = view.bounds.maxY - view.safeAreaInsets.bottom - 10
        menu.frame = CGRect(x: view.bounds.maxX - width - 10,
                            y: min(max(top, handleCenterY - height / 2), bottom - height),
                            width: width, height: height)
        let heading = UILabel(frame: CGRect(x: 16, y: 0, width: width - 32, height: 56))
        heading.text = "上下滑动选择，松手运行"
        heading.textAlignment = .center
        heading.numberOfLines = 2
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.textColor = .secondaryLabel
        menu.contentView.addSubview(heading)
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 56, width: width, height: height - 104))
        scroll.isUserInteractionEnabled = false
        scroll.contentSize = CGSize(width: width, height: CGFloat(items.count) * 52)
        menu.contentView.addSubview(scroll)
        groupRows = items.enumerated().map { index, entry in
            let label = UILabel(frame: CGRect(x: 0, y: CGFloat(index) * 52, width: width, height: 52))
            label.text = entry["title"] as? String ?? "快捷指令"
            label.textAlignment = .center
            label.font = font
            label.textColor = .label
            let separator = UIView(frame: CGRect(x: 16, y: 51, width: width - 32, height: 1 / UIScreen.main.scale))
            separator.backgroundColor = .separator
            label.addSubview(separator)
            scroll.addSubview(label)
            return label
        }
        let cancel = UILabel(frame: CGRect(x: 0, y: height - 48, width: width, height: 48))
        cancel.text = "取消"
        cancel.textAlignment = .center
        cancel.textColor = .systemRed
        cancel.font = .preferredFont(forTextStyle: .body)
        cancel.accessibilityTraits = .button
        menu.contentView.addSubview(cancel)
        view.addSubview(menu)
        groupMenu = menu
        groupScroll = scroll
        groupCancel = cancel
        groupOriginY = menu.frame.midY
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        PXMotion.ease(0.18) {
            menu.alpha = 1; menu.transform = .identity
        }
        updateGroupSelection(at: point)
    }

    func updateGroupSelection(at point: CGPoint) {
        lastSelectionPoint = point
        guard let menu = groupMenu, let scroll = groupScroll else { return }
        let local = menu.convert(point, from: view)
        guard menu.bounds.contains(local) else {
            groupSelected = nil
            groupRows.forEach { $0.backgroundColor = .clear; $0.textColor = .label }
            groupCancel?.backgroundColor = .clear
            return
        }
        let delta = point.y - groupOriginY
        let step = min(36, max(8, scroll.bounds.height / CGFloat(groupItems.count + 1)))
        let row = min(groupItems.count, max(0, groupItems.count / 2 + Int(delta / step)))
        let moved = abs(delta) >= 8
        let next: Int? = moved && groupItems.indices.contains(row) ? row : nil
        if next != groupSelected {
            selectionFeedback.selectionChanged()
            groupSelected = next
        }
        for (index, label) in groupRows.enumerated() {
            label.backgroundColor = index == next ? UIColor.systemBlue.withAlphaComponent(0.16) : .clear
            label.textColor = index == next ? .systemBlue : .label
        }
        groupCancel?.backgroundColor = moved && row == groupItems.count ?
            UIColor.systemRed.withAlphaComponent(0.12) : .clear
        if let next = next { scroll.scrollRectToVisible(groupRows[next].frame, animated: false) }
    }

    var selectedGroupAction: [String: Any]? { groupSelected.map { groupItems[$0] } }

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
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.20
        let outer = buttonRings.max() ?? 0
        for (index, button) in buttons.enumerated() {
            PXMotion.ease(duration, delay: Double(outer - buttonRings[index]) * 0.028,
                          options: .curveEaseIn) {
                button.alpha = 0
                button.transform = CGAffineTransform(translationX: self.handleCenterX - button.center.x,
                                                     y: self.handleCenterY - button.center.y)
                    .scaledBy(x: 0.72, y: 0.72)
            }
        }
        PXMotion.ease(duration + Double(outer) * 0.028, options: .curveEaseIn, animations: {
            self.shade.alpha = 0
            self.pageControl.alpha = 0
            self.selectionPreview.alpha = 0
            self.brightnessOverlay.alpha = 0
            self.groupMenu?.alpha = 0
        }, completion: { _ in completion() })
    }
}

private final class PXSearchViewController: UIViewController, UITableViewDataSource, UITextFieldDelegate {
    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    private let backdrop = UIView()
    private let card = UIView()
    private let field = UISearchTextField()
    private let table = UITableView()
    private let apps = PXInstalledApplications().compactMap { item -> (id: String, name: String)? in
        guard let id = item["id"], let name = item["name"] else { return nil }
        return (id, name)
    }
    private var matches: [(id: String, name: String)] = []
    private var keyboardTop: CGFloat?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSearch)))
        view.addSubview(backdrop)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        view.addSubview(card)
        field.placeholder = "搜索应用"
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(filterApps), for: .editingChanged)
        card.addSubview(field)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.rowHeight = 60
        table.keyboardDismissMode = .none
        card.addSubview(table)
        matches = apps
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let bottom = keyboardTop ?? view.bounds.height - view.safeAreaInsets.bottom
        let height = min(330, max(190, bottom * 0.45))
        card.frame = CGRect(x: 12, y: bottom - height - 8,
                            width: view.bounds.width - 24, height: height)
        field.frame = CGRect(x: 16, y: 12, width: card.bounds.width - 32, height: 40)
        table.frame = CGRect(x: 12, y: 60, width: card.bounds.width - 24,
                             height: card.bounds.height - 68)
    }

    func focus() {
        view.layoutIfNeeded()
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 28)
        view.alpha = 1
        field.becomeFirstResponder()
        PXMotion.spring(0.25) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardTop = max(0, view.convert(rect, from: nil).minY)
        PXMotion.ease(0.22) { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    }

    @objc private func filterApps() {
        let query = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        matches = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
    }

    @objc private func dismissSearch() { onDismiss?() }

    @objc private func openResult(_ sender: UIButton) {
        guard matches.indices.contains(sender.tag) else { return }
        onSelect?(matches[sender.tag].id)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let first = matches.first { onSelect?(first.id) }
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        (matches.count + 1) / 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "results") ??
            UITableViewCell(style: .default, reuseIdentifier: "results")
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let row = UIStackView(frame: CGRect(x: 0, y: 3, width: tableView.bounds.width, height: 54))
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        for index in (indexPath.row * 2)..<min(matches.count, indexPath.row * 2 + 2) {
            let app = matches[index]
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(app.name, for: .normal)
            if let icon = PXApplicationIcon(app.id) {
                let size = CGSize(width: 32, height: 32)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    icon.draw(in: CGRect(origin: .zero, size: size))
                }
                button.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
            }
            button.imageView?.contentMode = .scaleAspectFit
            button.titleLabel?.font = .systemFont(ofSize: 14)
            button.setTitleColor(.label, for: .normal)
            button.contentHorizontalAlignment = .center
            button.semanticContentAttribute = .forceLeftToRight
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
            button.backgroundColor = .tertiarySystemBackground
            button.layer.cornerRadius = 12
            button.addTarget(self, action: #selector(openResult(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        if matches.count == indexPath.row * 2 + 1 { row.addArrangedSubview(UIView()) }
        cell.contentView.addSubview(row)
        return cell
    }
}

@objc(PXPanelEntry)
public final class PXPanelEntry: NSObject {
    private static let shared = PXPanelEntry()
    private var handleWindow: PXHandleWindow?
    private var panelWindow: UIWindow?
    private var searchWindow: UIWindow?
    private weak var searchPreviousKeyWindow: UIWindow?
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
    private var externalPendingBundleID: String?
    private var panelFrontmostBundleID: String?
    private var resizeStartFrame: CGRect?
    private var resizeStartRadius: CGFloat = 0
    private var resizePreview: (scale: CGFloat, x: CGFloat, y: CGFloat)?
    private var moveStartFrame: CGRect?
    private var needsHostRefresh = false
    private var deviceLocked = false
    private var panelDragProgress: CGFloat = 0
    private var handleDragMode = 0 // 0 undecided, 1 panel, 2 vertical placement
    private var handleDragStartY: CGFloat = 0
    private var brightnessStart: (y: CGFloat, value: CGFloat)?
    private var keyboardDismissWindow: UIWindow?
    private var keyboardDismissSuppressed = false
    private var keyboardDismissFadingOut = false
    private var keyboardAnimationDuration: TimeInterval = 0.25
    private var keyboardAnimationOptions: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]

    @objc public static func start() {
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
        shared.installHandle()
        NotificationCenter.default.addObserver(shared, selector: #selector(refreshKeyboardDismissLayer),
            name: Notification.Name("PXKeyboardStateChanged"), object: nil)
        for name in [Notification.Name("PXKeyboardFrameChanged"), UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(shared, selector: #selector(keyboardFrameChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(shared,
            selector: #selector(lockStateChanged), name: Notification.Name("PXLockStateChanged"), object: nil)
    }

    @objc public static func updateCaptureVisibility() {
        let hide = UserDefaults(suiteName: preferenceDomain)?.bool(forKey: "hideForScreenshot") == true
        if let handle = shared.handle { PXSceneBridge.setCaptureHidden(hide, for: handle) }
        if let view = shared.panel?.view { PXSceneBridge.setCaptureHidden(hide, for: view) }
        shared.refreshKeyboardDismissLayer()
    }

    @objc public static func applicationActivated(_ bundleID: String) {
        let clear = {
            for dock in shared.dockedHosts.filter({ $0.bundleID == bundleID }) {
                shared.removeDock(dock, fullscreenHandoff: true)
            }
        }
        if Thread.isMainThread { clear() }
        else { DispatchQueue.main.async(execute: clear) }
    }

    @objc public static func externalOpenApplication(_ bundleID: String) {
        guard !shared.deviceLocked, shared.activeScene() != nil else { return }
        shared.externalPendingBundleID = bundleID
        shared.panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()
        shared.openHost(bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard shared.externalPendingBundleID == bundleID else { return }
            shared.externalPendingBundleID = nil
            guard shared.hostedBundleID == bundleID, shared.hostWindow != nil else { return }
            shared.closeHost(animated: false)
            _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
        }
    }

    private func externalOpenFailed(_ bundleID: String) {
        guard externalPendingBundleID == bundleID else { return }
        externalPendingBundleID = nil
        _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
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

    @objc private func outsideKeyboardTapped() { closeHost(animated: true) }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        if notification.name == UIResponder.keyboardWillChangeFrameNotification {
            keyboardAnimationDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
            let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
            keyboardAnimationOptions = [.beginFromCurrentState, .allowUserInteraction,
                                        UIView.AnimationOptions(rawValue: curve << 16)]
            if let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardDismissSuppressed = end.intersection(UIScreen.main.bounds).height < 30
            }
        } else if notification.name == UIResponder.keyboardDidHideNotification {
            keyboardDismissSuppressed = true
        } else if notification.name == UIResponder.keyboardDidShowNotification {
            keyboardDismissSuppressed = false
        } else if notification.name == Notification.Name("PXKeyboardStateChanged"), activeBridge.isKeyboardRelocated() {
            keyboardDismissSuppressed = false
        }
        refreshKeyboardDismissLayer()
    }

    @objc private func refreshKeyboardDismissLayer() {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let enabled = defaults?.object(forKey: "closeOutsideWithKeyboard") == nil ||
            defaults?.bool(forKey: "closeOutsideWithKeyboard") == true
        guard enabled, !deviceLocked, !keyboardDismissSuppressed, activeBridge.isKeyboardRelocated(),
              let host = hostWindow, let scene = host.windowScene else {
            fadeKeyboardDismissLayer()
            return
        }
        if keyboardDismissWindow == nil {
            let window = UIWindow(windowScene: scene)
            window.alpha = 0
            window.backgroundColor = .clear
            let root = UIViewController()
            let layer = UIControl()
            layer.backgroundColor = .clear
            layer.accessibilityLabel = "双击关闭分屏"
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(outsideKeyboardTapped))
            doubleTap.numberOfTapsRequired = 2
            layer.addGestureRecognizer(doubleTap)
            root.view = layer
            window.rootViewController = root
            keyboardDismissWindow = window
        }
        keyboardDismissWindow?.frame = scene.coordinateSpace.bounds
        keyboardDismissWindow?.windowLevel = host.windowLevel - 0.5
        keyboardDismissWindow?.isHidden = false
        let configured = (defaults?.object(forKey: "keyboardDimOpacity") as? NSNumber)?.doubleValue ?? 0.12
        let dim = min(0.6, max(0, configured))
        keyboardDismissWindow?.rootViewController?.view.backgroundColor = UIColor.black.withAlphaComponent(dim)
        if let window = keyboardDismissWindow, window.alpha < 1 || keyboardDismissFadingOut {
            keyboardDismissFadingOut = false
            UIView.animate(withDuration: keyboardAnimationDuration, delay: 0,
                           options: keyboardAnimationOptions) { window.alpha = 1 }
        }
    }

    private func fadeKeyboardDismissLayer() {
        guard let window = keyboardDismissWindow, !keyboardDismissFadingOut else { return }
        keyboardDismissFadingOut = true
        UIView.animate(withDuration: keyboardAnimationDuration, delay: 0,
                       options: keyboardAnimationOptions) { window.alpha = 0 } completion: { [weak self, weak window] _ in
            guard let self = self, let window = window, self.keyboardDismissFadingOut,
                  self.keyboardDismissWindow === window else { return }
            self.removeKeyboardDismissLayer()
        }
    }

    private func removeKeyboardDismissLayer() {
        keyboardDismissFadingOut = false
        keyboardDismissWindow?.isHidden = true
        keyboardDismissWindow?.rootViewController = nil
        keyboardDismissWindow = nil
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
        Self.updateCaptureVisibility()
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
        Self.updateCaptureVisibility()
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
            if let controller = panel, controller.groupMenuActive {
                controller.updateGroupSelection(at: gesture.location(in: controller.view))
                return
            }
            if let start = brightnessStart, let controller = panel {
                let y = gesture.location(in: controller.view).y
                let value = min(1, max(0, start.value + (start.y - y) / (root.bounds.height * 0.405)))
                controller.updateBrightness(value)
                _ = PXSceneBridge.shared().setBrightnessLevel(Float(value))
                return
            }
            let prior = panelDragProgress
            panelDragProgress = max(panelDragProgress, min(1, max(0, distance / threshold)))
            if prior < 0.8 && panelDragProgress >= 0.8 { panel?.completeOpening() }
            else if panelDragProgress < 0.8 { panel?.setProgress(panelDragProgress) }
            if panelDragProgress >= 0.8 {
                panel?.advancePage(forDrag: gesture.translation(in: root).y)
                if let controller = panel {
                    _ = controller.updateSelection(at: gesture.location(in: controller.view))
                }
            }
        case .ended:
            if let controller = panel, controller.groupMenuActive {
                controller.updateGroupSelection(at: gesture.location(in: controller.view))
                let entry = controller.selectedGroupAction
                hidePanel { [weak self] in if let entry = entry { self?.runConfiguredAction(entry) } }
                return
            }
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
                if let appID = applicationID(bundleID) {
                    hidePanel()
                    if fullscreen { openFullscreen(appID) }
                    else { openHost(appID) }
                } else {
                    let action = bundleID == "px.action.screenshot" && fullscreen ? "px.action.screenshot.copy" : bundleID
                    hidePanel { [weak self] in self?.performShortcut(action) }
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
        if hostedBundleID == bundleID, hostWindow != nil {
            externalPendingBundleID = nil
            panelFrontmostBundleID = nil
            return
        }
        if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
            restoreDock(dock)
            return
        }
        let wasFullscreen = panelFrontmostBundleID == bundleID
        panelFrontmostBundleID = nil
        presentHost(bundleID, wasFullscreen: wasFullscreen)
    }

    private func openFullscreen(_ bundleID: String) {
        if hostedBundleID == bundleID, hostWindow != nil { fullscreenTapped(); return }
        closeHost(animated: false)
        if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) {
            removeDock(dock, fullscreenHandoff: true)
        }
        panelFrontmostBundleID = nil
        _ = PXSceneBridge.shared().openFullscreenApplication(bundleID)
    }

    private func performShortcut(_ id: String) {
        if id == "px.action.brightness" { return }
        if let entry = configuredAction(id) {
            if entry["kind"] as? String != "group" { runConfiguredAction(entry) }
            return
        }
        if id == "px.action.restart" {
            restartCurrentApplication()
        } else if id == "px.action.search" {
            showSearch()
        } else if id.hasPrefix("px.recent.") {
            let parts = id.split(separator: ".", maxSplits: 3)
            if parts.count == 4 { openHost(String(parts[3])) }
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

    private func restartCurrentApplication() {
        let splitID = hostedBundleID
        guard let bundleID = splitID ?? PXSceneBridge.shared().frontmostBundleID(),
              bundleID != "com.apple.springboard", !bundleID.isEmpty else { return }
        let bridge = PXSceneBridge.shared()
        guard bridge.restartApplication(bundleID, suspended: splitID != nil,
            completion: { [weak self] success in
                guard success, splitID != nil else { return }
                self?.presentHost(bundleID, wasFullscreen: false)
            }) else { return }
        if splitID != nil { closeHost(animated: false) }
    }

    private func runConfiguredAction(_ entry: [String: Any]) {
        if entry["kind"] as? String == "quick", let bundleID = entry["app"] as? String {
            if hostedBundleID == bundleID { closeHost(animated: false) }
            if let dock = dockedHosts.first(where: { $0.bundleID == bundleID }) { removeDock(dock, fullscreenHandoff: true) }
        }
        guard !PXSceneBridge.shared().performConfiguredAction(entry) else { return }
        let alert = UIAlertController(title: "无法运行快捷方式", message: "请确认快捷指令或应用操作仍然存在，并在设置中重新选择。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        handleWindow?.rootViewController?.present(alert, animated: true)
    }

    private func showSearch() {
        guard searchWindow == nil, let scene = activeScene() else { return }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar + 2
        window.backgroundColor = .clear
        let controller = PXSearchViewController()
        controller.onSelect = { [weak self] bundleID in
            self?.hideSearch()
            self?.openHost(bundleID)
        }
        controller.onDismiss = { [weak self] in self?.hideSearch() }
        window.rootViewController = controller
        searchPreviousKeyWindow = scene.windows.first(where: { $0.isKeyWindow })
        searchWindow = window
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        controller.view.alpha = 0
        window.makeKeyAndVisible()
        controller.focus()
    }

    private func hideSearch() {
        searchWindow?.rootViewController?.view.endEditing(true)
        searchWindow?.isHidden = true
        searchWindow?.rootViewController = nil
        searchWindow = nil
        searchPreviousKeyWindow?.makeKey()
    }

    private func presentHost(_ bundleID: String, wasFullscreen: Bool) {
        guard let scene = activeScene(),
              let controls = handleWindow?.rootViewController?.view else { return }
        if hostWindow != nil, hostedBundleID != bundleID { parkMain(side: defaultDockSide) }
        else { closeHost(animated: false) }
        hostedBundleID = bundleID
        let screen = scene.coordinateSpace.bounds
        let width = screen.width * initialWidthFraction
        let height = width * screen.height / screen.width
        let cardFrame = initialCardFrame(in: screen, size: CGSize(width: width, height: height))
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
            corner.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear
            PXSceneBridge.keepTransparentGestureViewHittable(corner)
            corner.isUserInteractionEnabled = true
            corner.isAccessibilityElement = true
            corner.accessibilityLabel = "拖动调整窗口大小"
            corner.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                               action: #selector(resizeHost(_:))))
            root.view.addSubview(corner)
            hostCorners.append(corner)
            let top = UIControl(frame: .zero)
            top.tag = side
            top.backgroundColor = debug ? UIColor.systemBlue.withAlphaComponent(0.25) : .clear
            PXSceneBridge.keepTransparentGestureViewHittable(top)
            top.isAccessibilityElement = true
            top.accessibilityLabel = "停靠到小窗"
            top.addTarget(self, action: #selector(dockTapped(_:)), for: .touchUpInside)
            root.view.addSubview(top)
            hostTopCorners.append(top)
        }
        let moveGrip = UIView(frame: .zero)
        moveGrip.backgroundColor = .clear
        PXSceneBridge.keepTransparentGestureViewHittable(moveGrip)
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
        PXMotion.spring(0.4) {
            card.transform = .identity
        }
        activeBridge.openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            spinner.stopAnimating()
            guard success else {
                self.closeHost(animated: false)
                self.externalOpenFailed(bundleID)
                return
            }
            if let preview = card.subviews.first(where: { $0.tag == 0x50584c }) {
                PXMotion.ease(0.15, animations: { preview.alpha = 0 }) { _ in
                    preview.removeFromSuperview()
                }
            }
            self.matchHostAspect()
            self.activeBridge.prepareWindow(for: bundleID, wasFullscreen: wasFullscreen) { [weak self, weak window] ready in
                guard let self = self, self.hostWindow === window else { return }
                guard ready else {
                    self.closeHost(animated: false)
                    self.externalOpenFailed(bundleID)
                    return
                }
                if self.externalPendingBundleID == bundleID { self.externalPendingBundleID = nil }
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
        let width = min(screen.width * initialWidthFraction,
                        (screen.height - 80) * source.width / source.height)
        let height = width * source.height / source.width
        let frame = initialCardFrame(in: screen, size: CGSize(width: width, height: height))
        window.frame = CGRect(x: frame.minX - gripMargin,
                              y: frame.minY - gripTop,
                              width: width + 2 * gripMargin, height: height + gripTop + gripBottom)
        card.frame = CGRect(x: gripMargin, y: gripTop, width: width, height: height)
        card.layoutIfNeeded()
        layoutHostControls()
        activeBridge.layoutHost()
    }

    private func initialCardFrame(in screen: CGRect, size: CGSize) -> CGRect {
        let saved = UserDefaults(suiteName: preferenceDomain)?.object(forKey: "initialRightInset") as? NSNumber
        let inset = min(max(0, screen.width - size.width), max(0, CGFloat(saved?.doubleValue ?? 12)))
        return CGRect(x: screen.maxX - size.width - inset,
                      y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var initialWidthFraction: CGFloat {
        let saved = UserDefaults(suiteName: preferenceDomain)?.object(forKey: "initialWidthPercent") as? NSNumber
        return CGFloat(min(95, max(35, saved?.doubleValue ?? 78))) / 100
    }

    private var defaultDockSide: Int {
        UserDefaults(suiteName: preferenceDomain)?.integer(forKey: "dockSide") == -1 ? -1 : 1
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
        refreshKeyboardDismissLayer()
    }

    @objc private func dockTapped(_ sender: UIControl) {
        parkMain(side: defaultDockSide)
    }

    @discardableResult private func parkMain(side: Int) -> Bool {
        guard let window = hostWindow, let card = hostCard, let canvas = hostCanvas,
              let bundleID = hostedBundleID,
              let root = window.rootViewController?.view else { return false }
        let limit = min(4, max(1, UserDefaults(suiteName: preferenceDomain)?
            .object(forKey: "dockCount") as? Int ?? 2))
        while dockedHosts.count >= limit, let oldest = dockedHosts.first { removeDock(oldest) }
        let overlay = UIView(frame: root.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor(white: 1, alpha: 0.02)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(restoreDockTapped(_:))))
        for direction in [UISwipeGestureRecognizer.Direction.up, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dockSwiped(_:)))
            swipe.direction = direction
            overlay.addGestureRecognizer(swipe)
        }
        root.addSubview(overlay)
        window.windowLevel = .statusBar - 3
        card.layer.shadowOpacity = 0
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
        refreshKeyboardDismissLayer()
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
            let width = max(35, min(requested, available / CGFloat(count) / max(1, ratio)))
            let height = width * ratio
            let preceding = dockedHosts.prefix(index).reduce(CGFloat.zero) { sum, item in
                let r = item.sourceSize.height / max(1, item.sourceSize.width)
                return sum + max(35, min(requested, available / CGFloat(count) / max(1, r))) * r + 12
            }
            let frame = CGRect(x: dock.side < 0 ? 12 : screen.maxX - width - 12,
                               y: top + preceding, width: width, height: height)
            let scale = width / max(1, dock.originalCardFrame.width)
            let cardOffset = CGPoint(x: dock.originalCardFrame.midX - dock.window.bounds.midX,
                                     y: dock.originalCardFrame.midY - dock.window.bounds.midY)
            PXMotion.spring(0.30) {
                dock.window.transform = CGAffineTransform(scaleX: scale, y: scale)
                dock.window.center = CGPoint(x: frame.midX - cardOffset.x * scale,
                                             y: frame.midY - cardOffset.y * scale)
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
        if hostWindow != nil { parkMain(side: defaultDockSide) }
        dock.overlay.removeFromSuperview()
        dock.window.windowLevel = .statusBar - 2
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
        let screen = dock.window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let width = dock.originalCardFrame.width
        let height = dock.originalCardFrame.height
        let frame = initialCardFrame(in: screen, size: CGSize(width: width, height: height))
        let targetWindow = CGRect(x: frame.minX - gripMargin,
                                  y: frame.minY - gripTop,
                                  width: width + 2 * gripMargin,
                                  height: height + gripTop + gripBottom)
        PXMotion.spring(0.32, animations: {
            dock.window.transform = .identity
            dock.window.center = CGPoint(x: targetWindow.midX, y: targetWindow.midY)
            dock.card.layer.shadowOpacity = 0
        }, completion: { [weak self, weak dock] _ in
            guard let self = self, let dock = dock, self.hostWindow === dock.window else { return }
            self.layoutHostControls()
        })
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
        PXMotion.spring(0.40, animations: {
            let screen = scene.coordinateSpace.bounds
            card.transform = CGAffineTransform(scaleX: screen.width / oldFrame.width,
                                                y: screen.height / oldFrame.height)
            card.center = CGPoint(x: screen.midX, y: screen.midY)
            card.layer.cornerRadius = 0
            card.subviews.first?.layer.cornerRadius = 0
            card.layer.shadowOpacity = 0
        }, completion: { [weak self, weak window] _ in
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
        })
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
                applyResizePreview()
            } else {
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
                    activeBridge.layoutHost()
                    layoutHostControls()
                    CATransaction.commit()
                }
            }
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
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
            layoutHostControls()
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
        let translation = gesture.translation(in: handleWindow)
        if gesture.state == .ended, translation.y < -35,
           -translation.y > abs(translation.x) * 1.2,
           gesture.velocity(in: handleWindow).y < -500 {
            moveStartFrame = nil
            parkMain(side: defaultDockSide)
            return
        }
        if gesture.state == .changed || gesture.state == .ended {
            window.frame = start.offsetBy(dx: translation.x, dy: translation.y)
            layoutHostControls()
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            moveStartFrame = nil
        }
    }

    private func closeHost(animated: Bool) {
        guard let window = hostWindow else { return }
        removeKeyboardDismissLayer()
        let closingCard = hostCard
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
            PXMotion.spring(0.28, animations: {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }, completion: { _ in finish() })
        } else { finish() }
    }
}
