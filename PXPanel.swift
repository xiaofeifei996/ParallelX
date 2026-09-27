import UIKit

private let preferenceDomain = "com.moxuan.parallelx"
private let gripMargin: CGFloat = 28
private let gripBottom: CGFloat = 168

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
}

private final class PXPanelViewController: UIViewController {
    var apps: [(id: String, name: String)] = []
    var choose: ((String) -> Void)?
    var dismiss: (() -> Void)?
    private let shade = UIControl()
    private let sheet = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let scroll = UIScrollView()
    private var width: CGFloat = 154

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        shade.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(shade)
        sheet.layer.cornerRadius = 23
        sheet.layer.cornerCurve = .continuous
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        sheet.clipsToBounds = true
        view.addSubview(sheet)
        scroll.showsVerticalScrollIndicator = false
        sheet.contentView.addSubview(scroll)
        for (index, app) in apps.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.accessibilityLabel = app.name
            button.addTarget(self, action: #selector(appTapped(_:)), for: .touchUpInside)
            let icon = UIImageView(image: PXApplicationIcon(app.id) ?? UIImage(systemName: "app"))
            icon.contentMode = .scaleAspectFit
            icon.frame = CGRect(x: 57, y: 7, width: 40, height: 40)
            button.addSubview(icon)
            let label = UILabel(frame: CGRect(x: 5, y: 49, width: 144, height: 20))
            label.text = app.name
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 11)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.72
            button.addSubview(label)
            scroll.addSubview(button)
        }
        if apps.isEmpty {
            let label = UILabel()
            label.text = "请先在设置中添加应用"
            label.textColor = .secondaryLabel
            label.font = .systemFont(ofSize: 12)
            label.textAlignment = .center
            label.numberOfLines = 2
            label.frame = CGRect(x: 12, y: 18, width: width - 24, height: 56)
            scroll.addSubview(label)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shade.frame = view.bounds
        let safeTop = view.safeAreaInsets.top + 24
        let safeBottom = view.safeAreaInsets.bottom + 24
        let height = min(CGFloat(max(apps.count, 1)) * 74 + 20,
                         view.bounds.height - safeTop - safeBottom)
        sheet.frame = CGRect(x: view.bounds.width - width,
                             y: (view.bounds.height - height) / 2,
                             width: width, height: height)
        scroll.frame = sheet.bounds
        scroll.contentSize = CGSize(width: width, height: CGFloat(apps.count) * 74 + 20)
        for (index, button) in scroll.subviews.compactMap({ $0 as? UIButton }).enumerated() {
            button.frame = CGRect(x: 0, y: CGFloat(index) * 74 + 10, width: width, height: 74)
        }
    }

    func setProgress(_ progress: CGFloat) {
        let value = min(1, max(0, progress))
        shade.alpha = value
        sheet.transform = CGAffineTransform(translationX: width * (1 - value), y: 0)
    }

    @objc private func closeTapped() { dismiss?() }
    @objc private func appTapped(_ sender: UIButton) {
        guard apps.indices.contains(sender.tag) else { return }
        choose?(apps[sender.tag].id)
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
    private var hostMoveGrip: UIView?
    private weak var hostCanvas: UIView?
    private var panel: PXPanelViewController?
    private var handle: UIView?
    private var hostedBundleID: String?
    private var panelFrontmostBundleID: String?
    private var resizeStartFrame: CGRect?
    private var moveStartFrame: CGRect?
    private var needsHostRefresh = false

    @objc public static func start() {
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
        shared.installHandle()
    }

    @objc private func sceneDeactivated(_ notification: Notification) {
        if (notification.object as? UIWindowScene) === hostWindow?.windowScene {
            needsHostRefresh = true
        }
    }

    @objc private func sceneActivated(_ notification: Notification) {
        installHandle()
        guard needsHostRefresh, let window = hostWindow,
              (notification.object as? UIWindowScene) === window.windowScene,
              let bundleID = hostedBundleID, let canvas = hostCanvas,
              let controls = handleWindow?.rootViewController?.view else { return }
        needsHostRefresh = false
        PXSceneBridge.shared().openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            if success { self.matchHostAspect() }
            else { self.closeHost(animated: false) }
        }
    }

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func installHandle() {
        guard handleWindow == nil, let scene = activeScene() else { return }
        let window = PXHandleWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        let pill = UIView(frame: CGRect(x: window.bounds.width - 18,
                                        y: window.bounds.midY - 43,
                                        width: 18, height: 86))
        pill.backgroundColor = UIColor(white: 0.27, alpha: 0.86)
        pill.layer.cornerRadius = 9
        pill.layer.cornerCurve = .continuous
        pill.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        let mark = UIView(frame: CGRect(x: 7, y: 15, width: 3, height: 56))
        mark.backgroundColor = .white
        mark.layer.cornerRadius = 1.5
        pill.addSubview(mark)
        pill.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
        root.view.addSubview(pill)
        window.isHidden = false
        handle = pill
        handleWindow = window
    }

    private func selectedApps() -> [(id: String, name: String)] {
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let ids = defaults?.stringArray(forKey: "applications") ?? []
        let names = defaults?.dictionary(forKey: "applicationNames") as? [String: String] ?? [:]
        return ids.map { (id: $0, name: names[$0] ?? $0) }
    }

    private func beginPanel() {
        guard panelWindow == nil, let scene = handleWindow?.windowScene else { return }
        panelFrontmostBundleID = PXSceneBridge.shared().frontmostBundleID()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        let controller = PXPanelViewController()
        controller.apps = selectedApps()
        controller.dismiss = { [weak self] in self?.hidePanel() }
        controller.choose = { [weak self] id in
            self?.hidePanel { self?.openHost(id) }
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
        guard let root = handleWindow?.rootViewController?.view else { return }
        let distance = -gesture.translation(in: root).x
        switch gesture.state {
        case .began:
            beginPanel()
            fallthrough
        case .changed:
            panel?.setProgress(distance / 154)
        case .ended:
            let speed = -gesture.velocity(in: root).x
            if distance > 45 || speed > 650 { showPanel() }
            else { hidePanel() }
        case .cancelled, .failed:
            hidePanel()
        default: break
        }
    }

    private func showPanel() {
        guard let window = panelWindow, let controller = panel else { return }
        handleWindow?.isHidden = true
        window.isUserInteractionEnabled = true
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.34,
                       delay: 0, usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            controller.setProgress(1)
        }
    }

    private func hidePanel(_ completion: (() -> Void)? = nil) {
        guard let window = panelWindow, let controller = panel else {
            completion?()
            return
        }
        window.isUserInteractionEnabled = false
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22,
                       delay: 0, options: [.beginFromCurrentState]) {
            controller.setProgress(0)
        } completion: { [weak self] _ in
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
        let wasFullscreen = panelFrontmostBundleID == bundleID
        panelFrontmostBundleID = nil
        presentHost(bundleID, wasFullscreen: wasFullscreen)
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
        window.frame = CGRect(x: cardFrame.minX - gripMargin, y: cardFrame.minY,
                              width: width + 2 * gripMargin, height: height + gripBottom)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = PXHostViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        let card = UIView(frame: CGRect(x: gripMargin, y: 0, width: width, height: height))
        card.backgroundColor = .secondarySystemBackground
        let savedRadius = UserDefaults(suiteName: preferenceDomain)?.object(forKey: "cornerRadius") as? NSNumber
        card.layer.cornerRadius = CGFloat(min(60, max(0, savedRadius?.doubleValue ?? 20)))
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        root.view.addSubview(card)
        let clip = UIView(frame: card.bounds)
        clip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
        let defaults = UserDefaults(suiteName: preferenceDomain)
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
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        window.isUserInteractionEnabled = false
        PXSceneBridge.shared().openApplication(bundleID, in: canvas,
                                               keyboardOverlay: controls) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            spinner.stopAnimating()
            guard success else { self.closeHost(animated: false); return }
            self.matchHostAspect()
            PXSceneBridge.shared().prepareWindow(for: bundleID, wasFullscreen: wasFullscreen) { [weak self, weak window] ready in
                guard let self = self, self.hostWindow === window else { return }
                guard ready else { self.closeHost(animated: false); return }
                window?.isUserInteractionEnabled = true
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3,
                               delay: 0, usingSpringWithDamping: 0.88,
                               initialSpringVelocity: 0, options: .beginFromCurrentState) {
                    card.alpha = 1
                    card.transform = .identity
                } completion: { [weak self] _ in self?.layoutHostControls() }
            }
        }
    }

    private func matchHostAspect() {
        guard let window = hostWindow, let card = hostCard else { return }
        let source = PXSceneBridge.shared().hostedSourceSize()
        guard source.width > 0, source.height > 0 else { return }
        let screen = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
        let width = min(screen.width * 0.78,
                        (screen.height - 80) * source.width / source.height)
        let height = width * source.height / source.width
        window.frame = CGRect(x: screen.midX - width / 2 - gripMargin,
                              y: screen.midY - height / 2,
                              width: width + 2 * gripMargin, height: height + gripBottom)
        card.frame = CGRect(x: gripMargin, y: 0, width: width, height: height)
        card.layoutIfNeeded()
        layoutHostControls()
        PXSceneBridge.shared().layoutHost()
    }

    private func layoutHostControls() {
        guard let card = hostCard, hostWindow != nil else { return }
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
        let defaults = UserDefaults(suiteName: preferenceDomain)
        let width = min(360, max(120, CGFloat(truncating: defaults?.object(forKey: "gestureWidth") as? NSNumber ?? 300)))
        let height = min(120, max(36, CGFloat(truncating: defaults?.object(forKey: "gestureHeight") as? NSNumber ?? 80)))
        let offset = min(40, max(-30, CGFloat(truncating: defaults?.object(forKey: "gestureOffset") as? NSNumber ?? 0)))
        hostMoveGrip?.frame = CGRect(x: frame.midX - width / 2, y: frame.maxY + offset,
                                     width: width, height: height)
    }

    @objc private func closeTapped() { closeHost(animated: true) }

    @objc private func fullscreenTapped() {
        guard let bundleID = hostedBundleID,
              PXSceneBridge.shared().openFullscreenApplication(bundleID) else { return }
        closeHost(animated: false)
    }

    @objc private func moveGripHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { fullscreenTapped() }
    }

    @objc private func resizeHost(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow, let card = hostCard else { return }
        if gesture.state == .began {
            resizeStartFrame = CGRect(x: window.frame.minX + gripMargin,
                                      y: window.frame.minY, width: card.bounds.width,
                                      height: card.bounds.height)
        }
        guard let start = resizeStartFrame else { return }
        if gesture.state == .changed || gesture.state == .ended {
            let translation = gesture.translation(in: handleWindow)
            let horizontal = (gesture.view?.tag == -1 ? -translation.x : translation.x) / start.width
            let vertical = translation.y / start.height
            let change = abs(horizontal) > abs(vertical) ? horizontal : vertical
            let screen = window.windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds
            let horizontalRoom = gesture.view?.tag == -1 ?
                start.maxX - screen.minX - 12 : screen.maxX - start.minX - 12
            let maximum = min(horizontalRoom / start.width,
                              (screen.maxY - start.minY - 20) / start.height)
            let scale = min(max(1 + change, 220 / start.width), max(220 / start.width, maximum))
            let size = CGSize(width: start.width * scale, height: start.height * scale)
            let x = gesture.view?.tag == -1 ? start.maxX - size.width : start.minX
            window.frame = CGRect(x: x - gripMargin, y: start.minY,
                                  width: size.width + 2 * gripMargin,
                                  height: size.height + gripBottom)
            card.frame = CGRect(x: gripMargin, y: 0, width: size.width, height: size.height)
            card.layoutIfNeeded()
            layoutHostControls()
            PXSceneBridge.shared().layoutHost()
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            resizeStartFrame = nil
        }
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
        hostCorners.forEach { $0.removeFromSuperview() }
        hostMoveGrip?.removeFromSuperview()
        window.isUserInteractionEnabled = false
        hostWindow = nil
        hostCard = nil
        hostCanvas = nil
        hostCorners = []
        hostMoveGrip = nil
        hostedBundleID = nil
        resizeStartFrame = nil
        moveStartFrame = nil
        needsHostRefresh = false
        PXSceneBridge.shared().close()
        let finish = {
            window.isHidden = true
            window.rootViewController = nil
        }
        if animated, let card = window.rootViewController?.view {
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2,
                           animations: {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }, completion: { _ in finish() })
        } else { finish() }
    }
}
