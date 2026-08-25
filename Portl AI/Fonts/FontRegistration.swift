import CoreText
import Foundation

/// Registers custom fonts bundled with the app at runtime
enum FontRegistration {
    static func registerFonts() {
        let fontNames = ["PublicaPlay-Regular"]
        let fontExtensions = ["otf"]

        for (index, fontName) in fontNames.enumerated() {
            guard let fontURL = Bundle.main.url(
                forResource: fontName,
                withExtension: fontExtensions[index]
            ) else {
                continue
            }
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
}
