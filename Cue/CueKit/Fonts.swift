import SwiftUI
import AppKit
import CoreText

public enum Fonts {
    public static let scriptRegular = "CourierPrime-Regular"
    public static let scriptBold = "CourierPrime-Bold"
    public static let scriptItalic = "CourierPrime-Italic"
    public static let scriptBoldItalic = "CourierPrime-BoldItalic"
    public static let uiRegular = "Geist-Regular"

    private static var registered = false

    public static func register() {
        guard !registered else { return }
        registered = true
        let names = [
            "CourierPrime-Regular", "CourierPrime-Bold",
            "CourierPrime-Italic", "CourierPrime-BoldItalic", "Geist"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Already-registered is success.
        }
    }

    public static func script(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        let name: String
        switch (bold, italic) {
        case (true, true): name = scriptBoldItalic
        case (true, false): name = scriptBold
        case (false, true): name = scriptItalic
        case (false, false): name = scriptRegular
        }
        return .custom(name, size: size)
    }

    public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(uiRegular, size: size).weight(weight)
    }

    public static func uiNS(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let font = NSFont(name: uiRegular, size: size) {
            if weight == .regular { return font }
            return NSFontManager.shared.convert(font, toHaveTrait: weight >= .semibold ? .boldFontMask : [])
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    public static func scriptNS(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let name: String
        switch (bold, italic) {
        case (true, true): name = scriptBoldItalic
        case (true, false): name = scriptBold
        case (false, true): name = scriptItalic
        case (false, false): name = scriptRegular
        }
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// Verifies registration; used by the diagnostics screen and tests.
    public static func availablePostScriptNames() -> [String] {
        (CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? []
    }
}
