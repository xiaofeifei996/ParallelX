import UIKit

@objc(PXDockController)
public final class PXDockController: PSViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let widthLabel = UILabel()
    private let widthSlider = UISlider()
    private let countLabel = UILabel()
    private let countSlider = UISlider()
    private let sideLabel = UILabel()
    private let sideControl = UISegmentedControl(items: ["左侧", "右侧"])
    private let card = UIView()
    private let heading = UILabel()
    private let lines = [UIView(), UIView()]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "角落小窗"
        view.backgroundColor = .systemGroupedBackground
        heading.text = "位置与容量"
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.textColor = .secondaryLabel
        view.addSubview(heading)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        view.addSubview(card)
        for line in lines {
            line.backgroundColor = .separator
            view.addSubview(line)
        }
        for label in [widthLabel, countLabel, sideLabel] {
            label.font = .preferredFont(forTextStyle: .body)
            view.addSubview(label)
        }
        sideLabel.text = "小窗默认放置位置"
        sideControl.selectedSegmentIndex = defaults?.integer(forKey: "dockSide") == -1 ? 0 : 1
        sideControl.addTarget(self, action: #selector(sideChanged), for: .valueChanged)
        view.addSubview(sideControl)
        widthSlider.minimumValue = 35
        widthSlider.maximumValue = 160
        widthSlider.value = Float(defaults?.object(forKey: "dockWidth") as? Int ?? 110)
        countSlider.minimumValue = 1
        countSlider.maximumValue = 4
        countSlider.value = Float(defaults?.object(forKey: "dockCount") as? Int ?? 2)
        for slider in [widthSlider, countSlider] {
            slider.addTarget(self, action: #selector(changed), for: .valueChanged)
            slider.addTarget(self, action: #selector(finished),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            view.addSubview(slider)
        }
        changed()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let y = view.safeAreaInsets.top + 16
        let width = view.bounds.width - 64
        heading.frame = CGRect(x: 32, y: y, width: width, height: 22)
        card.frame = CGRect(x: 16, y: y + 30, width: view.bounds.width - 32, height: 264)
        for row in 0..<3 {
            let rowY = y + 30 + CGFloat(row) * 88
            let label = [widthLabel, countLabel, sideLabel][row]
            label.frame = CGRect(x: 32, y: rowY + 10, width: width, height: 28)
            if row < 2 {
                [widthSlider, countSlider][row].frame = CGRect(x: 32, y: rowY + 42,
                                                                 width: width, height: 34)
                lines[row].frame = CGRect(x: 32, y: rowY + 87, width: width, height: 0.5)
            } else {
                sideControl.frame = CGRect(x: 32, y: rowY + 40, width: width, height: 36)
            }
        }
    }

    @objc private func changed() {
        widthLabel.text = "小窗宽度：\(Int(widthSlider.value.rounded())) pt"
        countLabel.text = "最多保留：\(Int(countSlider.value.rounded())) 个小窗"
    }

    @objc private func finished() {
        widthSlider.value = widthSlider.value.rounded()
        countSlider.value = countSlider.value.rounded()
        defaults?.set(Int(widthSlider.value), forKey: "dockWidth")
        defaults?.set(Int(countSlider.value), forKey: "dockCount")
        changed()
    }

    @objc private func sideChanged() {
        defaults?.set(sideControl.selectedSegmentIndex == 0 ? -1 : 1, forKey: "dockSide")
    }
}
