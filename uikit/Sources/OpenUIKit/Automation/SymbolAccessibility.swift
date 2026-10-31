// iOS's default accessibility labels for SF Symbols. Owner: automation module
// (docs/AUTOMATION.md, docs/SYMBOL_ACCESSIBILITY_LABELS.md).
//
// iOS labels an SF Symbol image it shows without an app-provided label from
// its accessibility runtime's symbol name tables ("xmark" -> "Close",
// "star.fill" -> "Favourite" in British English). Those tables are Apple's;
// OpenUIKit carries only the labels of the symbols in
// scripts/sf_symbol_label_names.txt, generated from the iOS 27.0 Simulator
// runtime by scripts/sf_symbol_labels_from_runtime.py
// (SymbolAccessibilityLabels.swift). A symbol outside that list, or a
// language without a table, has no label (the tree still reports the
// symbol's name as the identifier).

#if canImport(Foundation)
import Foundation
#elseif canImport(FoundationEssentials)
import FoundationEssentials
#endif

public enum _UISymbolAccessibility {
    /// Probes pin the language; nil follows `Locale.preferredLanguages`.
    nonisolated(unsafe) public static var preferredLanguagesOverride: [String]?

    /// The label iOS 27 gives `name` in the guest's first preferred
    /// language: its regional table when there is one (`en_GB`), else the
    /// language's (`en`); nil for other languages and unlisted symbols.
    public static func label(forSymbolNamed name: String) -> String? {
        label(forSymbolNamed: name, preferredLanguages: preferredLanguagesOverride ?? Locale.preferredLanguages)
    }

    public static func label(forSymbolNamed name: String, preferredLanguages: [String]) -> String? {
        guard let preferred = preferredLanguages.first else { return nil }
        let parts = preferred.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let language = parts.first, language == "en" else { return nil }
        if parts.count > 1 {
            let regional = "\(language)_\(parts[parts.count - 1].uppercased())"
            if let label = _SymbolAccessibilityLabelTable.regional[regional]?[name] { return label }
        }
        return _SymbolAccessibilityLabelTable.base[name]
    }
}
