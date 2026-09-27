import UIKit

@objc(PXLauncherController)
public final class PXLauncherController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let keys = ["launcherIconSize", "launcherRing1", "launcherRing2",
                        "launcherRing3", "launcherRing4"]
    private let titles = ["图标大小", "第一环应用数", "第二环应用数", "第三环应用数", "第四环应用数"]
    private let initial: [Float] = [52, 3, 5, 7, 9]
    private let limits: [(Float, Float)] = [(36, 72), (1, 8), (1, 12), (1, 16), (1, 16)]
    private let labels = (0..<5).map { _ in UILabel() }
    private let sliders = (0..<5).map { _ in UISlider() }
    private let hint = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "半圆应用面板"
        view.backgroundColor = .systemGroupedBackground
        for index in keys.indices {
            let label = labels[index]
            label.font = .preferredFont(forTextStyle: .body)
            view.addSubview(label)
            let slider = sliders[index]
            slider.tag = index
            slider.minimumValue = limits[index].0
            slider.maximumValue = limits[index].1
            slider.value = defaults?.object(forKey: keys[index]) == nil
                ? initial[index] : Float(defaults?.double(forKey: keys[index]) ?? Double(initial[index]))
            slider.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(valueFinished(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            view.addSubview(slider)
            updateLabel(index)
        }
        hint.text = "仅显示已添加的应用。圆心留空；空间不足时自动分页，面板内上下滑动切换。更改在下次呼出面板时生效。"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.numberOfLines = 0
        view.addSubview(hint)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top + 18
        for index in keys.indices {
            let y = top + CGFloat(index) * 82
            labels[index].frame = CGRect(x: 20, y: y, width: view.bounds.width - 40, height: 28)
            sliders[index].frame = CGRect(x: 20, y: y + 34,
                                           width: view.bounds.width - 40, height: 38)
        }
        hint.frame = CGRect(x: 20, y: top + 420, width: view.bounds.width - 40, height: 90)
    }

    private func updateLabel(_ index: Int) {
        labels[index].text = "\(titles[index])：\(Int(sliders[index].value.rounded()))\(index == 0 ? " pt" : " 个")"
    }

    @objc private func valueChanged(_ slider: UISlider) { updateLabel(slider.tag) }

    @objc private func valueFinished(_ slider: UISlider) {
        slider.value = slider.value.rounded()
        updateLabel(slider.tag)
        defaults?.set(Int(slider.value), forKey: keys[slider.tag])
    }
}
