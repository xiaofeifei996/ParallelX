import UIKit

@objc(PXLauncherController)
public final class PXLauncherController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let keys = ["launcherIconSize", "launcherRing1", "launcherRing2",
                        "launcherRing3", "launcherRing4", "launcherDragDistance"]
    private let titles = ["图标大小", "第一环应用数", "第二环应用数", "第三环应用数",
                          "第四环应用数", "手柄滑动距离"]
    private let initial = [52, 3, 5, 7, 9, 120]
    private let limits: [(Float, Float)] = [(36, 72), (1, 30), (1, 30),
                                            (1, 30), (1, 30), (50, 240)]
    private let labels = (0..<6).map { _ in UILabel() }
    private let sliders = (0..<6).map { _ in UISlider() }
    private let hint = UILabel()
    private var values = [52, 3, 5, 7, 9, 120]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "半圆应用面板"
        view.backgroundColor = .systemGroupedBackground
        for index in keys.indices {
            let label = labels[index]
            label.font = .preferredFont(forTextStyle: .body)
            if (1...4).contains(index) {
                label.tag = index
                label.isUserInteractionEnabled = true
                label.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                         action: #selector(editRingCount(_:))))
            }
            view.addSubview(label)
            let slider = sliders[index]
            slider.tag = index
            slider.minimumValue = limits[index].0
            slider.maximumValue = limits[index].1
            values[index] = defaults?.object(forKey: keys[index]) as? Int ?? initial[index]
            slider.value = Float(values[index])
            slider.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(valueFinished(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            view.addSubview(slider)
            updateLabel(index)
        }
        hint.text = "圆心留空。长按环容量文字可输入数量；屏幕放不下时分多次呼出，按住手柄上滑切换页。滑到图标松手打开，空白处松手收回。"
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
        hint.frame = CGRect(x: 20, y: top + 500, width: view.bounds.width - 40, height: 95)
    }

    private func updateLabel(_ index: Int) {
        labels[index].text = "\(titles[index])：\(values[index])\(index == 0 || index == 5 ? " pt" : " 个")"
    }

    @objc private func valueChanged(_ slider: UISlider) {
        values[slider.tag] = Int(slider.value.rounded())
        updateLabel(slider.tag)
    }

    @objc private func valueFinished(_ slider: UISlider) {
        slider.value = slider.value.rounded()
        values[slider.tag] = Int(slider.value)
        updateLabel(slider.tag)
        defaults?.set(values[slider.tag], forKey: keys[slider.tag])
    }

    @objc private func editRingCount(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let index = gesture.view?.tag else { return }
        let alert = UIAlertController(title: titles[index], message: "输入每环应用数量", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(self.values[index])"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text,
                  let value = Int(text), value > 0 else { return }
            self.values[index] = value
            self.sliders[index].value = Float(value)
            self.updateLabel(index)
            self.defaults?.set(value, forKey: self.keys[index])
        })
        present(alert, animated: true)
    }
}
