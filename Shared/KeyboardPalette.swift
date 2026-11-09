import SwiftUI
import UIKit

/// The keyboard's colours, shared with the app's Look preview so it shows
/// exactly what the keyboard draws.
enum Palette {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    // Dark colours are Gboard's night theme, measured from a screenshot:
    // keys #424242, function keys #303030 on #212121.
    static let key = dynamic(light: .white, dark: UIColor(white: 0x42 / 255, alpha: 1))
    static let functional = dynamic(light: UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1),
                                    dark: UIColor(white: 0x30 / 255, alpha: 1))
    /// Flick guide cells: tinted so they stand apart from the keys they cover.
    static let flick = dynamic(light: UIColor(red: 0.84, green: 0.89, blue: 0.98, alpha: 1),
                               dark: UIColor(red: 0.20, green: 0.27, blue: 0.40, alpha: 1))
    /// Symbols in the keys' corners: white on the dark keys, like Gboard.
    static let hint = dynamic(light: UIColor(white: 0.35, alpha: 1), dark: UIColor(white: 1, alpha: 0.9))
    static let pressed = dynamic(light: UIColor(white: 0.80, alpha: 1), dark: UIColor(white: 0.40, alpha: 1))
    /// Behind the keys, painted in every theme: iOS's own backdrop is a
    /// frosted blur that tints the dark keyboard blue-grey with the app behind.
    static let background = dynamic(light: UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1),
                                    dark: UIColor(white: 0x21 / 255, alpha: 1))
}

extension UIColor {
    /// The user's colour, mixed with white just enough to read on the dark
    /// #424242 keys (relative luminance >= 0.4, about 4:1 contrast). Light
    /// colours come back unchanged; #007AFF becomes #66AFFF, #FF3B30 #FF8983.
    var readableOnDarkKeys: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        var t: CGFloat = 0
        while t < 1, luminance(r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t) < 0.4 { t += 0.05 }
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: a)
    }
}
