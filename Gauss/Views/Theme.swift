import Cocoa

/// Central theme configuration for the Gauss calculator.
/// Follows system appearance (dark/light) for Liquid Glass design.
enum Theme {

    // MARK: - Appearance Detection

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Fonts

    static var monoFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: Settings.shared.fontSize, weight: .regular)
    }

    static var monoFontSmall: NSFont {
        NSFont.monospacedSystemFont(ofSize: max(9, Settings.shared.fontSize - 2), weight: .regular)
    }

    static var totalBarFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - Window Background

    static var windowBackground: NSColor {
        isDark
            ? NSColor(red: 15/255, green: 15/255, blue: 25/255, alpha: 0.85)
            : NSColor(white: 1.0, alpha: 0.88)
    }

    // MARK: - Text Colors

    static var textPrimary: NSColor {
        isDark
            ? NSColor(white: 0.93, alpha: 1)
            : NSColor(white: 0.1, alpha: 1)
    }

    static var textSecondary: NSColor {
        isDark
            ? NSColor(white: 0.6, alpha: 1)
            : NSColor(white: 0.4, alpha: 1)
    }

    // MARK: - Syntax Highlighting Colors

    static var headerColor: NSColor {
        isDark
            ? NSColor(red: 96/255, green: 165/255, blue: 250/255, alpha: 1)  // #60a5fa
            : NSColor(red: 37/255, green: 99/255, blue: 235/255, alpha: 1)   // #2563eb
    }

    static var commentColor: NSColor {
        isDark
            ? NSColor(red: 71/255, green: 85/255, blue: 105/255, alpha: 1)   // #475569
            : NSColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 1) // #94a3b8
    }

    static var keywordColor: NSColor {
        isDark
            ? NSColor(red: 244/255, green: 114/255, blue: 182/255, alpha: 1) // #f472b6
            : NSColor(red: 219/255, green: 39/255, blue: 119/255, alpha: 1)  // #db2777
    }

    static var variableColor: NSColor {
        isDark
            ? NSColor(red: 103/255, green: 232/255, blue: 249/255, alpha: 1) // #67e8f9
            : NSColor(red: 8/255, green: 145/255, blue: 178/255, alpha: 1)   // #0891b2
    }

    // MARK: - Result Colors (based on value type)

    static var resultNumber: NSColor {
        isDark
            ? NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)  // #4ade80
            : NSColor(red: 22/255, green: 163/255, blue: 74/255, alpha: 1)   // #16a34a
    }

    static var resultUnit: NSColor {
        isDark
            ? NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1)  // #fbbf24
            : NSColor(red: 202/255, green: 138/255, blue: 4/255, alpha: 1)   // #ca8a04
    }

    static var resultDate: NSColor {
        isDark
            ? NSColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 1)  // #fb923c
            : NSColor(red: 234/255, green: 88/255, blue: 12/255, alpha: 1)   // #ea580c
    }

    static var resultDev: NSColor {
        isDark
            ? NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 1) // #c084fc
            : NSColor(red: 147/255, green: 51/255, blue: 234/255, alpha: 1)  // #9333ea
    }

    // MARK: - TotalBar

    static var totalBarBackground: NSColor {
        isDark
            ? NSColor(white: 0.1, alpha: 0.6)
            : NSColor(white: 0.95, alpha: 0.6)
    }

    static var totalBarText: NSColor {
        isDark
            ? NSColor(white: 0.7, alpha: 1)
            : NSColor(white: 0.3, alpha: 1)
    }

    // MARK: - Separator

    static var separator: NSColor {
        isDark
            ? NSColor(white: 0.55, alpha: 0.9)
            : NSColor(white: 0.45, alpha: 0.85)
    }

    // MARK: - Toast

    static var toastBackground: NSColor {
        isDark
            ? NSColor(white: 0.2, alpha: 0.95)
            : NSColor(white: 0.95, alpha: 0.95)
    }

    static var toastText: NSColor {
        isDark
            ? NSColor(white: 0.9, alpha: 1)
            : NSColor(white: 0.1, alpha: 1)
    }
}
