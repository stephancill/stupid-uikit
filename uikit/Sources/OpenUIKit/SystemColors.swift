// Data-driven system color table. Owner: color module.
//
// Resolves UIKit semantic color names ("label", "systemBlue", ...) to concrete
// sRGB values using Resources/system_colors.json — ground truth dumped from
// real UIKit by the oracle (`oracle colors`). Format:
//   { "light": { name: [r, g, b, a], ... }, "dark": { ... } }
//
// Pure Swift, no Foundation: loading goes through ResourceIO + MiniJSON.

public enum SystemColors {
    /// Magenta — returned for unknown names so failures are loudly visible.
    static let missing = CanvasColor(red: 1, green: 0, blue: 1, alpha: 1)

    struct Table {
        var light: [String: CanvasColor] = [:]
        var dark: [String: CanvasColor] = [:]
    }

    /// Parsed + cached color table. `static let` gives us lazy, thread-safe,
    /// once-only initialization.
    static let table: Table = loadTable()
    /// The iOS palette (Resources/system_colors_ios.json, resolved on the
    /// iPhone 16 / iOS 26.1 simulator by Tools/oracle2/colorprobe on
    /// 2026-09-04). system_colors.json is Mac Catalyst's, and 10 light + 13
    /// dark names differ: `label` is opaque black/white on iOS (0.847 alpha
    /// on Catalyst), dark `systemBackground` is #000000 (#1E1E1E), dark
    /// `secondarySystemBackground` #1C1C1E (#323232), light
    /// `secondarySystemBackground` #F2F2F7 (#ECECEC), the grey labels are
    /// (60,60,67)/(235,235,245) tints, `separator` (84,84,88)@0.5 in dark.
    /// Empty when the file is absent; the Catalyst table then serves both.
    static let tableIOS: Table = loadTable(resource: "system_colors_ios.json")
    /// The iOS 27.0 palette (Resources/system_colors_ios27.json, the same
    /// colorprobe on a temporary iOS 27.0 (24A434) iPhone SE 3rd generation
    /// simulator, 2026-10-31), used on the iOS cut when
    /// `OpenUIKitRuntime.chromeRelease == .iOS27`. It differs from iOS 26.1
    /// only in `opaqueSeparator`: light (231, 231, 232), dark (42, 42, 44)
    /// where iOS 26.1 has (198, 198, 200) / (56, 56, 58). `systemBlue` is
    /// (0, 136, 255) light / (0, 145, 255) dark on both releases.
    /// The iOS 26 chrome the gates pin keeps `tableIOS`.
    static let tableIOS27: Table = loadTable(resource: "system_colors_ios27.json")

    /// The palette for the current font cut and chrome release.
    static var activeTable: Table {
        guard OpenUIKitRuntime.systemFontCut == .iOS, !tableIOS.light.isEmpty else { return table }
        guard OpenUIKitRuntime.chromeRelease == .iOS27 else { return tableIOS }
        precondition(!tableIOS27.light.isEmpty,
                     "OpenUIKit: chromeRelease .iOS27 needs Resources/system_colors_ios27.json next to system_colors_ios.json")
        return tableIOS27
    }

    private static func loadTable(resource: String = "system_colors.json") -> Table {
        var t = Table()
        guard let json = ResourceIO.loadJSONResource(resource),
              let root = json.objectValue else {
            return t
        }
        t.light = parseStyle(root["light"])
        t.dark = parseStyle(root["dark"])
        return t
    }

    private static func parseStyle(_ value: _OpenUIKitJSONValue?) -> [String: CanvasColor] {
        guard let obj = value?.objectValue else { return [:] }
        var out: [String: CanvasColor] = [:]
        out.reserveCapacity(obj.count)
        for (name, comps) in obj {
            guard let a = comps.arrayValue, a.count == 4,
                  let r = a[0].doubleValue, let g = a[1].doubleValue,
                  let b = a[2].doubleValue, let al = a[3].doubleValue else { continue }
            out[name] = CanvasColor(red: CGFloat(r), green: CGFloat(g),
                                blue: CGFloat(b), alpha: CGFloat(al))
        }
        return out
    }

    /// Resolve a semantic color name for the given traits.
    /// `.unspecified` resolves as light. Unknown names resolve to magenta.
    static func resolve(_ name: String, traits: UITraitCollection) -> CanvasColor {
        let t = activeTable
        let styleTable: [String: CanvasColor]
        switch traits.userInterfaceStyle {
        case .dark: styleTable = t.dark
        case .light, .unspecified: styleTable = t.light
        }
        guard var c = styleTable[name] else { return missing }
        // MEASURED iPhone 16 / iOS 26.1 (iososswallsprobe `cgcolor.*`): these
        // semantic colours resolve to gray-model CGColors in that style.
        let gray: Set<String> = traits.userInterfaceStyle == .dark
            ? ["label", "systemBackground", "systemGroupedBackground", "lightText", "darkText"]
            : ["label", "systemBackground", "tertiarySystemBackground", "lightText", "darkText"]
        if gray.contains(name) { c.isGrayModel = true }
        return c
    }

    /// Whether the measured palette carries `name`. `UINib` asks before
    /// turning an archived `UISystemColorName` into a semantic `UIColor`,
    /// so an unknown name is reported instead of resolving to magenta.
    static func isKnown(_ name: String) -> Bool {
        let t = activeTable
        return t.light[name] != nil || t.dark[name] != nil
    }
}
