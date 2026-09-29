import Foundation

// Shared by the selector and its Foundation-only check.
func PXAppInitial(_ name: String) -> String {
    let latin = (name.applyingTransform(.toLatin, reverse: false) ?? name)
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let first = latin.unicodeScalars.first, (65...90).contains(first.value) else { return "#" }
    return String(first)
}
