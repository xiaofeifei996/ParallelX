import UIKit

@objc(PXDockController)
public final class PXDockController: UIViewController {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let widthLabel = UILabel()
    private let widthSlider = UISlider()
    private let countLabel = UILabel()
    private let countSlider = UISlider()
    private let sideLabel = UILabel()
    private let sideControl = UISegmentedControl(items: ["左侧", "右侧"])

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "角落小窗"
        view.backgroundColor = .systemGroupedBackground
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
        let y = view.safeAreaInsets.top + 24
        let width = view.bounds.width - 40
        widthLabel.frame = CGRect(x: 20, y: y, width: width, height: 28)
        widthSlider.frame = CGRect(x: 20, y: y + 38, width: width, height: 38)
        countLabel.frame = CGRect(x: 20, y: y + 112, width: width, height: 28)
        countSlider.frame = CGRect(x: 20, y: y + 150, width: width, height: 38)
        sideLabel.frame = CGRect(x: 20, y: y + 220, width: width, height: 28)
        sideControl.frame = CGRect(x: 20, y: y + 256, width: width, height: 38)
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
