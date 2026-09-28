import UIKit

enum PXSettingsStyle {
    static func card(in parent: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        parent.insertSubview(card, at: 0)
        return card
    }

    static func heading(_ title: String, in parent: UIView) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        parent.addSubview(label)
        return label
    }

    static func separator(in parent: UIView) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        parent.addSubview(line)
        return line
    }
}
