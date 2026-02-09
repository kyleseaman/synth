import Cocoa
import SwiftUI

struct Theme {
    static let editorFontCandidatesKey = "theme.editorFontCandidates"
    static let terminalFontCandidatesKey = "theme.terminalFontCandidates"
    static let sidebarFontCandidatesKey = "theme.sidebarFontCandidates"

    static var uiFont: NSFont { sidebarNSFont(ofSize: 13) }
    static var editorFont: NSFont { editorNSFont(ofSize: 18) }
    static var monoFont: NSFont { terminalNSFont(ofSize: 12) }
    static let offWhite = NSColor.textBackgroundColor
    static let offBlack = NSColor.textColor

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
            fallback: mesloCandidates(for: weight),
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
        var merged = configured
        var seenCandidates = Set(configured)
        for fallbackCandidate in fallback where seenCandidates.insert(fallbackCandidate).inserted {
            merged.append(fallbackCandidate)
        }
        return merged
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

    static func editorNSFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        defaults: UserDefaults = .standard,
        resolver: (String, CGFloat) -> NSFont? = { fontName, fontSize in
            NSFont(name: fontName, size: fontSize)
        }
    ) -> NSFont {
        resolveFont(
            candidates: editorCandidateNames(weight: weight, defaults: defaults),
            size: size,
            resolver: resolver
        )
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func terminalNSFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        defaults: UserDefaults = .standard
    ) -> NSFont {
        resolveFont(
            candidates: terminalCandidateNames(weight: weight, defaults: defaults),
            size: size
        )
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func defaultSidebarCandidates(
        for weight: NSFont.Weight
    ) -> [String] {
        let regularCandidates = [
            "SF Pro Text Regular",
            "SFProText-Regular",
            "SF Pro Text",
            ".SFNSText"
        ]
        let mediumCandidates = [
            "SF Pro Text Medium",
            "SFProText-Medium"
        ]
        let semiboldCandidates = [
            "SF Pro Text Semibold",
            "SFProText-Semibold"
        ]
        let boldCandidates = [
            "SF Pro Text Bold",
            "SFProText-Bold"
        ]
        let candidates: [String]
        if weight.rawValue >= NSFont.Weight.bold.rawValue {
            candidates = boldCandidates + semiboldCandidates + mediumCandidates + regularCandidates
        } else if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            candidates = semiboldCandidates + mediumCandidates + regularCandidates
        } else if weight.rawValue >= NSFont.Weight.medium.rawValue {
            candidates = mediumCandidates + regularCandidates
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
        resolveFont(
            candidates: sidebarCandidateNames(weight: weight, defaults: defaults),
            size: size
        )
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func sidebarSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(sidebarNSFont(ofSize: size, weight: weight))
    }

    static func terminalSwiftUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(terminalNSFont(ofSize: size, weight: weight))
    }
}
