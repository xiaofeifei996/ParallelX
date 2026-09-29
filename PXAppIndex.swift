import Foundation

func PXAppRailX(base: CGFloat, bow: CGFloat, progress: CGFloat) -> CGFloat {
    base - bow * CGFloat(sin(Double(min(1, max(0, progress))) * Double.pi))
}

func PXAppGridCell(count: Int, width: CGFloat, height: CGFloat) -> CGFloat {
    min(max(0, width) / 3, max(0, height) / CGFloat(max(1, (count + 2) / 3)))
}

func PXBottomGestureFrame(card: CGRect, screen: CGRect, width: CGFloat, height: CGFloat, offset: CGFloat) -> CGRect {
    let underCard = CGRect(x: card.midX - width / 2, y: card.maxY + offset, width: width, height: height)
    guard screen.width > screen.height else { return underCard }
    // Keep the card's controls, but also catch the physical screen's bottom-centre swipe.
    let screenBottom = CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    return underCard.union(screenBottom).intersection(screen)
}

// Shared by the selector and its Foundation-only check.
func PXAppInitial(_ name: String) -> String {
    let latin = (name.applyingTransform(.toLatin, reverse: false) ?? name)
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let first = latin.unicodeScalars.first, (65...90).contains(first.value) else { return "#" }
    return String(first)
}
