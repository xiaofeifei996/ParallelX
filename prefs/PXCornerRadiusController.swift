import UIKit

@objc(PXCornerRadiusController)
public final class PXCornerRadiusController: UIViewController {
    private let slider = UISlider()
    private let number = UIButton(type: .system)
    private let caption = UILabel()
    private let hint = UILabel()
    private let shadowStrength = UISlider()
    private let shadowBlur = UISlider()
    private let shadowStrengthLabel = UILabel()
    private let shadowBlurLabel = UILabel()
    private let rightInset = UISlider()
    private let rightInsetLabel = UILabel()
    private let initialWidth = UISlider()
    private let initialWidthLabel = UILabel()
    private let scroll = UIScrollView()
    private var cards: [UIView] = []
    private var headings: [UILabel] = []
    private var lines: [UIView] = []
    private var inputButtons: [UIButton] = []
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "位置、圆角与阴影"
        view.backgroundColor = .systemGroupedBackground
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        for title in ["初始位置与尺寸", "窗口圆角", "窗口阴影"] {
            headings.append(PXSettingsStyle.heading(title, in: scroll))
            cards.append(PXSettingsStyle.card(in: scroll))
        }
        lines = (0..<2).map { _ in PXSettingsStyle.separator(in: scroll) }
        caption.text = "圆角大小"
        caption.font = .preferredFont(forTextStyle: .body)
        scroll.addSubview(caption)
        slider.minimumValue = 0
        slider.maximumValue = 60
        slider.value = Float(defaults?.object(forKey: "cornerRadius") == nil ? 20 :
                             defaults?.double(forKey: "cornerRadius") ?? 20)
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(valueFinished),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        scroll.addSubview(slider)
        number.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        number.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                  action: #selector(editNumber(_:))))
        number.accessibilityHint = "长按输入圆角数值"
        scroll.addSubview(number)
        number.setImage(UIImage(systemName: "keyboard"), for: .normal)
        number.addTarget(self, action: #selector(editCorner), for: .touchUpInside)
        hint.text = "点击键盘按钮输入精确数值"
        hint.textColor = .secondaryLabel
        hint.font = .preferredFont(forTextStyle: .footnote)
        scroll.addSubview(hint)
        for (control, label, key, fallback, maximum) in [
            (shadowStrength, shadowStrengthLabel, "shadowStrength", 22, 50),
            (shadowBlur, shadowBlurLabel, "shadowBlur", 15, 24),
            (rightInset, rightInsetLabel, "initialRightInset", 12, 120),
            (initialWidth, initialWidthLabel, "initialWidthPercent", 78, 95)
        ] {
            label.font = .preferredFont(forTextStyle: .body)
            scroll.addSubview(label)
            control.minimumValue = key == "initialWidthPercent" ? 35 : 0
            control.maximumValue = Float(maximum)
            control.value = Float(defaults?.object(forKey: key) as? Int ?? fallback)
            control.addTarget(self, action: #selector(shadowChanged), for: .valueChanged)
            control.addTarget(self, action: #selector(shadowFinished),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])
            scroll.addSubview(control)
            let button = PXSettingsStyle.inputButton(for: control, title: key == "shadowStrength" ? "阴影强度（%）" : key == "shadowBlur" ? "阴影模糊（pt）" : key == "initialRightInset" ? "初始右边距（pt）" : "初始窗口宽度（%）", in: self)
            scroll.addSubview(button)
            inputButtons.append(button)
        }
        valueChanged()
        shadowChanged()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = scroll.bounds.width
        let groups: [[(UILabel, UISlider)]] = [
            [(rightInsetLabel, rightInset), (initialWidthLabel, initialWidth)],
            [(caption, slider)],
            [(shadowStrengthLabel, shadowStrength), (shadowBlurLabel, shadowBlur)]
        ]
        var y: CGFloat = 20
        for (section, rows) in groups.enumerated() {
            headings[section].frame = CGRect(x: 32, y: y, width: width - 64, height: 22)
            y += 30
            let cardY = y
            cards[section].frame = CGRect(x: 16, y: cardY, width: width - 32,
                                           height: CGFloat(rows.count) * 82)
            for (row, pair) in rows.enumerated() {
                let rowY = cardY + CGFloat(row) * 82
                pair.0.frame = CGRect(x: 32, y: rowY + 10, width: width - 64, height: 28)
                pair.1.frame = CGRect(x: 32, y: rowY + 40,
                                      width: width - 112, height: 34)
                if section == 1 {
                    number.frame = CGRect(x: width - 70, y: rowY + 36, width: 38, height: 38)
                } else {
                    inputButtons[section == 0 ? row + 2 : row].frame = CGRect(x: width - 70, y: rowY + 36, width: 38, height: 38)
                }
                if section != 1 && row == 0 {
                    lines[section == 0 ? 0 : 1].frame = CGRect(x: 32, y: rowY + 81,
                                                               width: width - 64, height: 0.5)
                }
            }
            y += CGFloat(rows.count) * 82 + 28
        }
        hint.frame = CGRect(x: 32, y: y - 18, width: width - 64, height: 32)
        scroll.contentSize = CGSize(width: width, height: hint.frame.maxY + 16)
    }

    @objc private func valueChanged() {
        caption.text = "圆角大小：\(Int(slider.value.rounded())) pt"
    }

    @objc private func valueFinished() {
        slider.value = slider.value.rounded()
        valueChanged()
        defaults?.set(Int(slider.value), forKey: "cornerRadius")
    }

    @objc private func shadowChanged() {
        shadowStrengthLabel.text = "阴影强度：\(Int(shadowStrength.value.rounded()))%"
        shadowBlurLabel.text = "阴影模糊：\(Int(shadowBlur.value.rounded())) pt"
        rightInsetLabel.text = "初始窗口距离右边缘：\(Int(rightInset.value.rounded())) pt"
        initialWidthLabel.text = "初始窗口宽度：屏幕的 \(Int(initialWidth.value.rounded()))%"
    }

    @objc private func shadowFinished() {
        shadowStrength.value = shadowStrength.value.rounded()
        shadowBlur.value = shadowBlur.value.rounded()
        rightInset.value = rightInset.value.rounded()
        initialWidth.value = initialWidth.value.rounded()
        shadowChanged()
        defaults?.set(Int(shadowStrength.value), forKey: "shadowStrength")
        defaults?.set(Int(shadowBlur.value), forKey: "shadowBlur")
        defaults?.set(Int(rightInset.value), forKey: "initialRightInset")
        defaults?.set(Int(initialWidth.value), forKey: "initialWidthPercent")
    }

    @objc private func editNumber(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        editCorner()
    }

    @objc private func editCorner() {
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
