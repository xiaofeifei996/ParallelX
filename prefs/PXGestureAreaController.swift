import UIKit

@objc(PXGestureAreaController)
public final class PXGestureAreaController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let keys = ["gestureWidth", "gestureHeight", "gestureOffset"]
    private let titles = ["区域宽度", "区域高度", "垂直偏移"]
    private let initial: [Float] = [300, 80, 0]
    private let limits: [(Float, Float)] = [(120, 360), (36, 120), (-30, 40)]
    private let labels = (0..<3).map { _ in UILabel() }
    private let sliders = (0..<3).map { _ in UISlider() }
    private let debugLabel = UILabel()
    private let debugSwitch = UISwitch()
    private let hint = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "底部手势区域"
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
            slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(sliderFinished(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            view.addSubview(slider)
            updateLabel(index)
        }
        debugLabel.text = "显示手势触发区域"
        debugLabel.font = .preferredFont(forTextStyle: .body)
        view.addSubview(debugLabel)
        debugSwitch.isOn = defaults?.bool(forKey: "gestureDebug") ?? false
        debugSwitch.addTarget(self, action: #selector(debugChanged), for: .valueChanged)
        view.addSubview(debugSwitch)
        hint.text = "透明区域位于分屏窗口下方；双击关闭、长按全屏、拖动移动。更改在下次打开窗口时生效。"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.numberOfLines = 0
        view.addSubview(hint)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let top = view.safeAreaInsets.top + 24
        for index in keys.indices {
            let y = top + CGFloat(index) * 92
            labels[index].frame = CGRect(x: 20, y: y, width: width - 40, height: 28)
            sliders[index].frame = CGRect(x: 20, y: y + 35, width: width - 40, height: 38)
        }
        let row = top + 286
        debugLabel.frame = CGRect(x: 20, y: row, width: width - 110, height: 36)
        debugSwitch.frame.origin = CGPoint(x: width - 20 - debugSwitch.bounds.width, y: row)
        hint.frame = CGRect(x: 20, y: row + 60, width: width - 40, height: 90)
    }

    private func updateLabel(_ index: Int) {
        labels[index].text = "\(titles[index])：\(Int(sliders[index].value.rounded())) pt"
    }

    @objc private func sliderChanged(_ slider: UISlider) { updateLabel(slider.tag) }

    @objc private func sliderFinished(_ slider: UISlider) {
        slider.value = slider.value.rounded()
        updateLabel(slider.tag)
        defaults?.set(Int(slider.value), forKey: keys[slider.tag])
    }

    @objc private func debugChanged() {
        defaults?.set(debugSwitch.isOn, forKey: "gestureDebug")
    }
}
