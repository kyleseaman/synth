import Cocoa
import CoreText
import SwiftUI

struct Theme {
    static let editorFontCandidatesKey = "theme.editorFontCandidates"
    static let terminalFontCandidatesKey = "theme.terminalFontCandidates"
    static let sidebarFontCandidatesKey = "theme.sidebarFontCandidates"
    static let bundledFontFileNames = [
        "mesloLGS_NF_regular.ttf",
        "mesloLGS_NF_bold.ttf",
        "mesloLGS_NF_italic.ttf",
        "mesloLGS_NF_bold_italic.ttf",
        "PublicSans-Regular.ttf",
        "PublicSans-SemiBold.ttf",
        "PublicSans-Bold.ttf",
        "SourceSerif4-Regular.ttf",
        "SourceSerif4-SemiBold.ttf",
        "SourceSerif4-Bold.ttf"
    ]

    static var uiFont: NSFont { sidebarNSFont(ofSize: 13) }
    static var editorFont: NSFont { editorNSFont(ofSize: 18) }
    static var monoFont: NSFont { terminalNSFont(ofSize: 12) }
    static let offWhite = NSColor.textBackgroundColor
    static let offBlack = NSColor.textColor

    static func bundledFontURLs(
        in bundle: Bundle = .main,
        fileNames: [String] = bundledFontFileNames
    ) -> [URL] {
        fileNames.compactMap { fontFileName in
            let baseName = (fontFileName as NSString).deletingPathExtension
            let extensionName = (fontFileName as NSString).pathExtension
            return bundle.url(forResource: baseName, withExtension: extensionName)
        }
    }

    @discardableResult
    static func registerFonts(
        at fontURLs: [URL],
        registrar: (CFURL, CTFontManagerScope, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
            = CTFontManagerRegisterFontsForURL
    ) -> Int {
        var registeredCount = 0
        for fontURL in fontURLs where registrar(fontURL as CFURL, .process, nil) {
            registeredCount += 1
        }
        return registeredCount
    }

    @discardableResult
    static func registerBundledFonts(in bundle: Bundle = .main) -> Int {
        registerFonts(at: bundledFontURLs(in: bundle))
    }

    static func resolveFont(
        candidates: [String],
        size: CGFloat,
        resolver: (String, CGFloat) -> NSFont? = { fontName, fontSize in
            NSFont(name: fontName, size: fontSize)
        }
    ) -> NSFont? {
        for candidateName in candidates {
            if let fontValue = resolver(candidateName, size) {
                return fontValue
            }
        }
        return nil
    }

    static func parseCandidateList(_ value: String?) -> [String] {
        guard let value else { return [] }
        let pieces = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seenCandidates = Set<String>()
        var deduplicated: [String] = []
        for candidate in pieces where !seenCandidates.contains(candidate) {
            deduplicated.append(candidate)
            seenCandidates.insert(candidate)
        }
        return deduplicated
    }

    static func editorCandidateNames(
        weight: NSFont.Weight,
        defaults: UserDefaults = .standard
    ) -> [String] {
        configuredCandidates(
            customKey: editorFontCandidatesKey,
            fallback: sourceSerifCandidates(for: weight),
            defaults: defaults
        )
    }

    static func terminalCandidateNames(
        weight: NSFont.Weight,
        defaults: UserDefaults = .standard
    ) -> [String] {
        configuredCandidates(
            customKey: terminalFontCandidatesKey,
            fallback: mesloCandidates(for: weight),
            defaults: defaults
        )
    }

    static func sidebarCandidateNames(
        weight: NSFont.Weight,
        defaults: UserDefaults = .standard
    ) -> [String] {
        configuredCandidates(
            customKey: sidebarFontCandidatesKey,
            fallback: defaultSidebarCandidates(for: weight),
            defaults: defaults
        )
    }

    private static func configuredCandidates(
        customKey: String,
        fallback: [String],
        defaults: UserDefaults
    ) -> [String] {
        let configured = parseCandidateList(defaults.string(forKey: customKey))
        if !configured.isEmpty { return configured }
        return fallback
    }

    static func mesloCandidates(for weight: NSFont.Weight) -> [String] {
        let regularCandidates = [
            "MesloLGS-Regular",
            "MesloLGS NF Regular",
            "MesloLGS NF",
            "MesloLGS",
            "Meslo LG S"
        ]
        if weight.rawValue >= NSFont.Weight.bold.rawValue {
            return [
                "MesloLGS-Bold",
                "MesloLGS NF Bold",
                "MesloLGSNerdFont-Bold"
            ] + regularCandidates
        }
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            return [
                "MesloLGS-Semibold",
                "MesloLGS NF Semibold",
                "MesloLGS-Medium"
            ] + regularCandidates
        }
        if weight.rawValue >= NSFont.Weight.medium.rawValue {
            return [
                "MesloLGS-Medium",
                "MesloLGS NF Medium"
            ] + regularCandidates
        }
        return regularCandidates
    }

    static func sourceSerifCandidates(for weight: NSFont.Weight) -> [String] {
        let regularCandidates = [
            "SourceSerif4-Regular",
            "SourceSerif4Roman-Regular",
            "Source Serif 4",
            "SourceSerif4"
        ]
        if weight.rawValue >= NSFont.Weight.bold.rawValue {
            return [
                "SourceSerif4-Bold",
                "SourceSerif4Roman-Bold"
            ] + regularCandidates
        }
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            return [
                "SourceSerif4-Semibold",
                "SourceSerif4Roman-Semibold"
            ] + regularCandidates
        }
        return regularCandidates
    }

    static func publicSansCandidates(for weight: NSFont.Weight) -> [String] {
        let regularCandidates = [
            "PublicSans-Regular",
            "PublicSansRoman-Regular",
            "Public Sans",
            "PublicSans"
        ]
        if weight.rawValue >= NSFont.Weight.bold.rawValue {
            return [
                "PublicSans-Bold",
                "PublicSansRoman-Bold"
            ] + regularCandidates
        }
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            return [
                "PublicSans-Semibold",
                "PublicSansRoman-Semibold"
            ] + regularCandidates
        }
        return regularCandidates
    }

    static var mesloPresetValue: String {
        mesloCandidates(for: .regular).joined(separator: ", ")
    }

    static var sourceSerifPresetValue: String {
        sourceSerifCandidates(for: .regular).joined(separator: ", ")
    }

    static var publicSansPresetValue: String {
        publicSansCandidates(for: .regular).joined(separator: ", ")
    }

    // MARK: - Font Cache

    /// Thread-safe cache for resolved NSFont instances keyed by (category, size, weight).
    final class FontCache: @unchecked Sendable {
        private var store: [String: NSFont] = [:]
        private let lock = NSLock()

        func font(forKey key: String) -> NSFont? {
            lock.lock()
            defer { lock.unlock() }
            return store[key]
        }

        func setFont(_ font: NSFont, forKey key: String) {
            lock.lock()
            defer { lock.unlock() }
            store[key] = font
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            store.removeAll()
        }
    }

    static let fontCache = FontCache()

    /// Invalidate cached fonts (call when user changes font preferences).
    static func invalidateFontCache() {
        fontCache.clear()
    }

    private static func cacheKey(_ category: String, size: CGFloat, weight: NSFont.Weight) -> String {
        "\(category)-\(size)-\(weight.rawValue)"
    }

    static func editorNSFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        defaults: UserDefaults = .standard,
        resolver: (String, CGFloat) -> NSFont? = { fontName, fontSize in
            NSFont(name: fontName, size: fontSize)
        }
    ) -> NSFont {
        let key = cacheKey("editor", size: size, weight: weight)
        if let cached = fontCache.font(forKey: key) { return cached }
        let font = resolveFont(
            candidates: editorCandidateNames(weight: weight, defaults: defaults),
            size: size,
            resolver: resolver
        ) ?? NSFont.systemFont(ofSize: size, weight: weight)
        fontCache.setFont(font, forKey: key)
        return font
    }

    static func terminalNSFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        defaults: UserDefaults = .standard
    ) -> NSFont {
        let key = cacheKey("terminal", size: size, weight: weight)
        if let cached = fontCache.font(forKey: key) { return cached }
        let font = resolveFont(
            candidates: terminalCandidateNames(weight: weight, defaults: defaults),
            size: size
        ) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        fontCache.setFont(font, forKey: key)
        return font
    }

    private static func defaultSidebarCandidates(
        for weight: NSFont.Weight
    ) -> [String] {
        let regularCandidates = [
            "PublicSans-Regular",
            "PublicSansRoman-Regular",
            "PublicSans",
            ".SFNSText"
        ]
        let semiboldCandidates = [
            "PublicSans-Semibold",
            "PublicSansRoman-Semibold"
        ]
        let boldCandidates = [
            "PublicSans-Bold",
            "PublicSansRoman-Bold"
        ]
        let candidates: [String]
        if weight.rawValue >= NSFont.Weight.bold.rawValue {
            candidates = boldCandidates + semiboldCandidates + regularCandidates
        } else if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            candidates = semiboldCandidates + regularCandidates
        } else {
            candidates = regularCandidates
        }
        return candidates
    }

    static func sidebarNSFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        defaults: UserDefaults = .standard
    ) -> NSFont {
        let key = cacheKey("sidebar", size: size, weight: weight)
        if let cached = fontCache.font(forKey: key) { return cached }
        let font = resolveFont(
            candidates: sidebarCandidateNames(weight: weight, defaults: defaults),
            size: size
        ) ?? NSFont.systemFont(ofSize: size, weight: weight)
        fontCache.setFont(font, forKey: key)
        return font
    }

    private static func swiftUIFontWeight(_ weight: NSFont.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    private static func swiftUIFont(from nsFont: NSFont, size: CGFloat, weight: NSFont.Weight) -> Font {
        if nsFont.fontName.hasPrefix(".") || nsFont.fontName.contains("SFNS") || nsFont.fontName.contains("SFPro") {
            return .system(size: size, weight: swiftUIFontWeight(weight))
        }
        return Font.custom(nsFont.fontName, size: size)
    }

    static func editorSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        swiftUIFont(from: editorNSFont(ofSize: size, weight: weight), size: size, weight: weight)
    }

    static func sidebarSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        swiftUIFont(from: sidebarNSFont(ofSize: size, weight: weight), size: size, weight: weight)
    }

    static func terminalSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        swiftUIFont(from: terminalNSFont(ofSize: size, weight: weight), size: size, weight: weight)
    }

    /// General-purpose UI font for views like browsers, backlinks, chat, etc.
    static func uiSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        sidebarSwiftUIFont(size: size, weight: weight)
    }
}
