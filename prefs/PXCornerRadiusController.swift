import UIKit

@objc(PXCornerRadiusController)
public final class PXCornerRadiusController: UIViewController {
    private let slider = UISlider()
    private let number = UIButton(type: .system)
    private let caption = UILabel()
    private let hint = UILabel()
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "窗口圆角"
        view.backgroundColor = .systemGroupedBackground
        caption.text = "圆角大小"
        caption.font = .preferredFont(forTextStyle: .body)
        view.addSubview(caption)
        slider.minimumValue = 0
        slider.maximumValue = 60
        slider.value = Float(defaults?.object(forKey: "cornerRadius") == nil ? 20 :
                             defaults?.double(forKey: "cornerRadius") ?? 20)
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(valueFinished),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(slider)
        number.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        number.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                  action: #selector(editNumber(_:))))
        number.accessibilityHint = "长按输入圆角数值"
        view.addSubview(number)
        hint.text = "长按右侧数字可以输入 0–60 pt"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        view.addSubview(hint)
        valueChanged()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let y = view.safeAreaInsets.top + 28
        let width = view.bounds.width
        caption.frame = CGRect(x: 20, y: y, width: width - 40, height: 28)
        slider.frame = CGRect(x: 20, y: y + 42, width: width - 112, height: 34)
        number.frame = CGRect(x: width - 90, y: y + 38, width: 70, height: 42)
        hint.frame = CGRect(x: 20, y: y + 88, width: width - 40, height: 24)
    }

    @objc private func valueChanged() {
        number.setTitle("\(Int(slider.value.rounded())) pt", for: .normal)
    }

    @objc private func valueFinished() {
        slider.value = slider.value.rounded()
        valueChanged()
        defaults?.set(Int(slider.value), forKey: "cornerRadius")
    }

    @objc private func editNumber(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let alert = UIAlertController(title: "窗口圆角", message: "输入 0–60 pt", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(Int(self.slider.value.rounded()))"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let text = alert?.textFields?.first?.text,
                  let value = Int(text) else { return }
            self.slider.value = Float(min(60, max(0, value)))
            self.valueFinished()
        })
        present(alert, animated: true)
    }
}
