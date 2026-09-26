import UIKit

private let preferenceDomain = "com.moxuan.parallelx"

private final class PXHandleWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === rootViewController?.view ? nil : result
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
    private weak var previousKeyWindow: UIWindow?
    private var panel: PXPanelViewController?
    private var handle: UIView?

    @objc public static func start() {
        NotificationCenter.default.addObserver(shared,
            selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        shared.installHandle()
    }

    @objc private func sceneActivated() { installHandle() }

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
        previousKeyWindow = window.windowScene?.windows.first(where: { $0.isKeyWindow })
        handleWindow?.isHidden = true
        window.isUserInteractionEnabled = true
        window.makeKey()
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
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22,
                       delay: 0, options: [.beginFromCurrentState]) {
            controller.setProgress(0)
        } completion: { [weak self] _ in
            guard let self = self, self.panelWindow === window else { return }
            window.isHidden = true
            window.rootViewController = nil
            self.panelWindow = nil
            self.panel = nil
            self.previousKeyWindow?.makeKey()
            self.handleWindow?.isHidden = false
            completion?()
        }
    }

    private func openHost(_ bundleID: String) {
        guard let scene = activeScene() else { return }
        closeHost(animated: false)
        let screen = scene.coordinateSpace.bounds
        let source = UIScreen.main.bounds.size
        let scale = min(screen.width * 0.78 / source.width,
                        (screen.height - 160 - 44) / source.height)
        let width = source.width * scale
        let height = source.height * scale + 44
        let frame = CGRect(x: (screen.width - width) / 2,
                           y: (screen.height - height) / 2,
                           width: width, height: height)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        let card = root.view!
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        window.rootViewController = root
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 44))
        bar.autoresizingMask = .flexibleWidth
        let title = UILabel(frame: CGRect(x: 16, y: 0, width: width - 74, height: 44))
        title.text = selectedApps().first(where: { $0.id == bundleID })?.name ?? bundleID
        title.font = .systemFont(ofSize: 14, weight: .medium)
        bar.addSubview(title)
        let close = UIButton(type: .system)
        close.frame = CGRect(x: width - 48, y: 2, width: 44, height: 40)
        close.autoresizingMask = .flexibleLeftMargin
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.accessibilityLabel = "关闭分屏窗口"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        bar.addSubview(close)
        card.addSubview(bar)
        let clip = UIView(frame: CGRect(x: 0, y: 44, width: width, height: height - 44))
        clip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        clip.clipsToBounds = true
        card.addSubview(clip)
        let canvas = UIView(frame: CGRect(origin: .zero, size: source))
        canvas.center = CGPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        canvas.alpha = 0
        clip.addSubview(canvas)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.center = CGPoint(x: width / 2, y: height / 2)
        spinner.startAnimating()
        card.addSubview(spinner)
        window.isHidden = false
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        hostWindow = window
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3,
                       delay: 0, usingSpringWithDamping: 0.88,
                       initialSpringVelocity: 0, options: .beginFromCurrentState) {
            card.alpha = 1
            card.transform = .identity
        }
        PXSceneBridge.shared().openApplication(bundleID, in: canvas) { [weak self, weak window] success in
            guard let self = self, self.hostWindow === window else { return }
            spinner.stopAnimating()
            if success {
                UIView.performWithoutAnimation {
                    canvas.transform = CGAffineTransform(scaleX: scale, y: scale)
                    canvas.alpha = 1
                }
            } else { self.closeHost(animated: true) }
        }
    }

    @objc private func closeTapped() { closeHost(animated: true) }

    private func closeHost(animated: Bool) {
        guard let window = hostWindow else { return }
        hostWindow = nil
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
