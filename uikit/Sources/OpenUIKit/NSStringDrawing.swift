// NSString drawing conveniences supplied by UIKit/Foundation when the full
// Foundation umbrella is present. Native Linux and Foundation-hidden Mach-O
// framework builds both need OpenUIKit's implementation; the latter is still
// an Apple target, so an `os(Linux)` test alone is insufficient.
//
// The types are UIKit names, not Foundation exports: Darwin SwiftPM OpenUIKit
// (canImport(Foundation), not Linux) must declare them too. MEASURED
// scripts/guest_route_check.sh on origin/agent/merge-focus4 (Darwin target,
// Foundation hidden): FocusLaunchCompat.swift:202/211 `invalid redeclaration`
// of NSStringDrawingOptions / NSStringDrawingContext and `ambiguous use of
// 'init(rawValue:)'` — that file's `#if !os(Linux)` copies compiled next to
// this file's `#if os(Linux) || !canImport(Foundation)` copies. One set lives
// here. NSAttributedString.boundingRect is Focus AutocompleteTextField.swift:250
// (Blockzilla a2832521); String.boundingRect stays Linux/guest-only so Darwin
// host keeps the SDK String overlay (TooltipView.swift:112 already compiles).
// That overlay is AppKit's on the macOS triple; on the iOS triple, whose
// curated SDK has no Apple UIKit (docs/agent_reports/ios-target-route.md),
// nothing else supplies it, hence `!canImport(AppKit)`.

public struct NSStringDrawingOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1 << 0)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 1 << 1)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 1 << 3)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 1 << 5)
}

public final class NSStringDrawingContext: @unchecked Sendable {
    public init() {}
}

#if os(Linux) || !canImport(Foundation) || !canImport(AppKit)
extension String {
    public func boundingRect(
        with size: CGSize,
        options: NSStringDrawingOptions = [],
        attributes: [NSAttributedString.Key: Any]? = nil,
        context: NSStringDrawingContext? = nil
    ) -> CGRect {
        _ = context
        let font = attributes?[.font] as? UIFont ?? .systemFont(ofSize: 12)
        let maximumWidth = max(0, size.width)
        let lineHeight = FontEngine.labelLineHeight(for: font)

        if options.contains(.usesLineFragmentOrigin), maximumWidth > 0 {
            let lines = TextLayout.wrap(
                self,
                font: font,
                maxWidth: maximumWidth,
                maxLines: 0
            )
            let width = lines.reduce(CGFloat.zero) { max($0, $1.measuredWidth) }
            return CGRect(
                origin: .zero,
                size: CGSize(
                    width: FontEngine.ceilToPixel(width, scale: 1),
                    height: CGFloat(lines.count) * lineHeight
                )
            )
        }

        return CGRect(
            origin: .zero,
            size: CGSize(
                width: FontEngine.ceilToPixel(FontEngine.measure(self, font: font), scale: 1),
                height: isEmpty ? 0 : lineHeight
            )
        )
    }
}
#endif

extension NSAttributedString {
    /// AutocompleteTextField.swift:250. Width of the typed prefix.
    public func boundingRect(
        with size: CGSize,
        options: NSStringDrawingOptions,
        context: NSStringDrawingContext?
    ) -> CGRect {
        _ = context
        let font: UIFont
        if length > 0, let value = attributes(at: 0, effectiveRange: nil)[.font] as? UIFont {
            font = value
        } else {
            font = .systemFont(ofSize: 17)
        }
        // Multi-line measurement lays the runs out as a label does (fonts,
        // attachments, colour emoji, kerning, wrapping at `size.width`), so
        // a width measured here is one a label of that width keeps on the
        // same lines. stupid social sizes chat bubbles this way; the
        // first-font single-line estimate came out 3.5 pt narrower than the
        // label for a line holding a custom-emoji attachment and a smaller
        // time run, and the label then wrapped the time onto a line of its
        // own (iOS 27 simulator: one line, 267 pt).
        if options.contains(.usesLineFragmentOrigin), size.width > 0, length > 0 {
            let t = AttributedTextLayout.flatten(self, defaultFont: font,
                                                 defaultColor: .label)
            let lines = AttributedTextLayout.wrap(t, maxWidth: size.width, maxLines: 0,
                                                  scale: OpenUIKitRuntime.imageScreenScale)
            var w: CGFloat = 0
            var h: CGFloat = 0
            for (i, l) in lines.enumerated() {
                w = Swift.max(w, l.measuredWidth)
                h += l.height
                if i < lines.count - 1 { h += l.spacingBelow }
            }
            return CGRect(x: 0, y: 0, width: min(size.width, w), height: min(size.height, h))
        }
        let w = FontEngine.measure(string, font: font)
        let h = FontEngine.labelLineHeight(for: font)
        return CGRect(x: 0, y: 0, width: min(size.width, w), height: min(size.height, h))
    }

    /// stupid social ChatUserColor.swift: initials avatar centring. Unconstrained single-line size,
    /// measured with the same engine as `boundingRect`.
    public func size() -> CGSize {
        boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [],
            context: nil
        ).size
    }

    /// stupid social ChatUserColor.swift: draws the initials into a UIGraphicsImageRenderer context.
    /// Uses UILabel's attributed-text drawing so runs, fonts and colours match a label's.
    public func draw(at point: CGPoint) {
        let bounds = CGRect(origin: point, size: size())
        let label = UILabel()
        label.attributedText = self
        UIGraphics.draw { label._drawText(in: $0, bounds: bounds) }
    }
}
