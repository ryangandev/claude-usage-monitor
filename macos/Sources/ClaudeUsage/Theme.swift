import AppKit
import SwiftUI

extension Color {
    /// A color with its own light and dark values, following the view's appearance.
    init(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { a in
            let isDark = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// The Linear-like palette from the design: one indigo accent, orange and red only when they mean something.
enum Theme {
    static let accent = Color(light: 0x5E6AD2, dark: 0x6E79DB)
    static let accentSoft = Color(light: 0xB9BDF2, dark: 0xA7ADF0)
    static let warn = Color(light: 0xC2610C, dark: 0xF59E4B)
    static let warnText = Color(light: 0x9A4A06, dark: 0xF8B577)
    static let warnBg = Color(light: 0xFDF0E3, dark: 0xF59E4B, darkAlpha: 0.14)
    static let danger = Color(light: 0xC62F2F, dark: 0xFF6B6B)
    static let live = Color(light: 0x2FB26B, dark: 0x2FB26B)
    static let liveText = Color(light: 0x1D7A48, dark: 0x7FD6A4)
    static let okBg = Color(light: 0xE6F5EC, dark: 0x2FB26B, darkAlpha: 0.16)

    static let text = Color(light: 0x1B1C1F, dark: 0xEDEDF0)
    static let sub = Color(light: 0x6B6F76, dark: 0x9A9CA5)
    static let line = Color(light: 0xECECEF, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let line2 = Color(light: 0xF3F3F5, dark: 0xFFFFFF, darkAlpha: 0.05)
    static let chip = Color(light: 0xECECEF, dark: 0xFFFFFF, darkAlpha: 0.07)
    static let track = Color(light: 0xEFEFF2, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let segOn = Color(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.14)
    static let navOn = Color(light: 0xE9E9EC, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B1C20)
    static let main = Color(light: 0xFFFFFF, dark: 0x16171A)
    static let idle = Color(light: 0xD4D5DB, dark: 0xFFFFFF, darkAlpha: 0.2)
    static let budget = Color(light: 0x000000, dark: 0xFFFFFF, darkAlpha: 0.3, lightAlpha: 0.28)

    static let ease = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
}

extension Usage.Status {
    var color: Color {
        switch self {
        case .normal: return Theme.accent
        case .early: return Theme.warn
        case .almostFull, .full: return Theme.danger
        }
    }
}
