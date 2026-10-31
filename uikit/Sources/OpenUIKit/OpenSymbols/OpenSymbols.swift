// Open symbol fallback: Phosphor Icons glyphs drawn for SF Symbol names.
//
// OpenUIKit never ships Apple's SF Symbols. When a `systemName` is not one of
// the project-authored procedural symbols (UIKit) or hand-drawn symbols
// (SwiftUI), and the opt-in fallback is enabled, a glyph from the vendored
// open icon set (MIT, see OpenSymbolCatalog.generated.swift) is drawn
// instead. Only names in the mapping table (uikit/Tools/opensymbols/
// mapping.tsv) draw; any other name still fails exactly as before.
//
// The fallback is OFF unless `OPENUIKIT_OPEN_SYMBOLS=1` is in the process
// environment or a host sets `OpenUIKitRuntime.openSymbolFallback = true`.
// Off, every existing symbol path, gate and fail-closed test is unchanged.
//
// Geometry: the glyph is drawn monochrome in one colour (hierarchical,
// palette and multicolor rendering modes are a monochrome approximation).
// Weight: a symbol drawn at SF semibold or heavier uses Phosphor's bold
// glyph for names mapped to the regular weight (fill glyphs have one
// weight), placed by the regular glyph's bounds so its strokes thicken
// outward as SF's heavier weights do; lighter weights draw regular, and
// `regular-only` rows in mapping.tsv vendor no bold drawing.
// MEASURED stupid social feed, iPhone 16e @3x / iOS 27.0 simulator:
// `chevron.forward` at body semibold has 1.9x the ink of Phosphor's
// regular caret (bold: 1.5x). Sizes follow SF
// Symbol metrics:
// - names in the harvested ink table (Resources/symbol_ink_ios.json) use
//   their measured 17 pt regular alignment box and ink rect, scaled by
//   pointSize / 17; the glyph is aspect-fitted into that ink rect;
// - other names keep Phosphor's own optical size: Phosphor's 208-unit
//   circle (viewBox 256) is drawn as SF's 17 pt circle ink (1.0 × point
//   size), and the alignment box adds 2/17 pt horizontal and 1/17 pt
//   vertical padding per side (the table's median circle-family margins).

import CPortableIO

#if canImport(CoreGraphics)
import struct CoreFoundation.CGFloat
import struct CoreGraphics.CGAffineTransform
import struct CoreGraphics.CGPoint
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#endif

extension OpenUIKitRuntime {
    /// Draw open-licensed Phosphor glyphs for mapped SF Symbol names that
    /// have no project-authored symbol. Off by default; the process
    /// environment `OPENUIKIT_OPEN_SYMBOLS=1` turns it on.
    public static var openSymbolFallback: Bool = {
        guard let value = cpio_getenv("OPENUIKIT_OPEN_SYMBOLS") else { return false }
        return String(cString: value) == "1"
    }()
}

/// Composite drawn around a glyph for `.circle` / `.circle.fill` names that
/// the icon set has no dedicated glyph for.
enum _OpenSymbolComposite {
    case none
    /// Ring (Phosphor `circle`) with the regular glyph at half size inside.
    case ring
    /// Disc (Phosphor `circle-fill`) with the fill glyph cut out at half size.
    case disc
    /// The glyph mirrored horizontally about the viewBox centre (an icon
    /// drawn facing the other way).
    case mirror
    /// SF's `person.fill.badge.plus`: a figure (head ellipse over a
    /// half-ellipse body) and a disc with a plus cut out overlapping its
    /// lower right, the figure knocked out around the disc, all drawn from
    /// the measured `badgePlusGeometry` (Phosphor's filled figure merges
    /// head and body and has a far larger head, so it is not used).
    case badgePlus
}

struct _OpenSymbolEntry {
    let glyph: String
    let composite: _OpenSymbolComposite
}

public enum OpenSymbols {
    /// Version of the vendored icon set.
    public static var iconSetVersion: String { "Phosphor Icons " + _OpenSymbolCatalog.phosphorVersion }

    /// Every SF Symbol name the mapping table covers.
    public static var mappedNames: [String] { _OpenSymbolCatalog.names }

    /// True when `name` is in the mapping table (independent of the flag).
    public static func isMapped(_ name: String) -> Bool {
        _OpenSymbolCatalog.entry(name) != nil
    }

    /// SF-style alignment box and ink rect for `name` at `pointSize`
    /// (medium symbol scale), in points; nil for unmapped names.
    public struct Layout: Equatable, Sendable {
        public var size: CGSize
        public var ink: CGRect
        /// The point of the box a fixed-size SwiftUI image centres in its
        /// frame: the box centre, except for a badge composite, whose
        /// figure is centred and whose badge hangs off it (MEASURED
        /// `person.fill.badge.plus`: the figure's centre sits on the
        /// frame's centre, the badge 0.6 pt past a 28 pt frame).
        public var anchor: CGPoint

        public init(size: CGSize, ink: CGRect, anchor: CGPoint? = nil) {
            self.size = size
            self.ink = ink
            self.anchor = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    public static func layout(name: String, pointSize: CGFloat) -> Layout? {
        guard pointSize.isFinite, pointSize > 0, let glyph = glyph(for: name) else { return nil }
        let k = pointSize / 17
        if let measured = SymbolInkTable.defaultAlignment(name: name) {
            return Layout(
                size: CGSize(width: measured.box.width * k, height: measured.box.height * k),
                ink: CGRect(x: measured.ink.minX * k, y: measured.ink.minY * k,
                            width: measured.ink.width * k, height: measured.ink.height * k))
        }
        let unit = pointSize / 208
        let inkW = glyph.bounds.width * unit
        let inkH = glyph.bounds.height * unit
        let padX = 2 * k
        let padY = 1 * k
        var anchor: CGPoint?
        if _OpenSymbolCatalog.entry(name)?.composite == .badgePlus {
            let m = badgePlusGeometry
            let figureCentre = m.square.minX + m.bodyCentre.x * m.square.width
            anchor = CGPoint(x: padX + (figureCentre - glyph.bounds.minX) * unit,
                             y: padY + inkH / 2)
        }
        return Layout(size: CGSize(width: inkW + 2 * padX, height: inkH + 2 * padY),
                      ink: CGRect(x: padX, y: padY, width: inkW, height: inkH),
                      anchor: anchor)
    }

    /// Glyph paths for `name` placed in `bounds`, which is treated as the
    /// symbol's alignment box (scaled uniformly and centred if its aspect
    /// differs). Fill each path separately with the returned rule.
    /// Whether a symbol drawn at `weight` uses the bold glyph (semibold
    /// and heavier; see the file header).
    public static func usesBoldGlyph(_ weight: UIImage.SymbolWeight) -> Bool {
        weight.rawValue >= UIImage.SymbolWeight.semibold.rawValue
    }

    /// `paths(name:in:weight:)` for a font weight (SwiftUI `Image` takes
    /// its symbol weight from the font).
    public static func symbolWeight(forFontWeight weight: UIFont.Weight) -> UIImage.SymbolWeight {
        weight.rawValue >= UIFont.Weight.semibold.rawValue ? .semibold : .regular
    }

    public static func paths(name: String, in bounds: CGRect,
                             weight: UIImage.SymbolWeight = .regular) -> (paths: [Path], evenOdd: Bool)? {
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite,
              let regular = glyph(for: name),
              let layout = layout(name: name, pointSize: 17) else { return nil }
        let drawn = usesBoldGlyph(weight) ? (boldGlyph(for: name) ?? regular) : regular
        let fit = Swift.min(bounds.width / layout.size.width, bounds.height / layout.size.height)
        let boxW = layout.size.width * fit
        let boxH = layout.size.height * fit
        let originX = bounds.minX + (bounds.width - boxW) / 2
        let originY = bounds.minY + (bounds.height - boxH) / 2
        let ink = CGRect(x: originX + layout.ink.minX * fit, y: originY + layout.ink.minY * fit,
                         width: layout.ink.width * fit, height: layout.ink.height * fit)
        // Placed by the REGULAR glyph's bounds: a bold glyph's strokes grow
        // outward around the same skeleton instead of shrinking it to fit.
        let g = regular.bounds
        let s = Swift.min(ink.width / g.width, ink.height / g.height)
        let tx = ink.midX - g.midX * s
        let ty = ink.midY - g.midY * s
        let transform = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
        return (drawn.paths.map { $0.applying(transform) }, drawn.evenOdd)
    }

    /// The knockout of a `badgePlus` composite placed in `bounds` as
    /// `paths(name:in:weight:)` places the glyph: the first `pathCount`
    /// paths are drawn only outside `circle`. nil for other names.
    static func knockout(name: String, in bounds: CGRect,
                         weight: UIImage.SymbolWeight = .regular) -> (circle: CGRect, pathCount: Int)? {
        guard let regular = glyph(for: name) else { return nil }
        let drawn = usesBoldGlyph(weight) ? (boldGlyph(for: name) ?? regular) : regular
        guard let knockout = drawn.knockout,
              let layout = layout(name: name, pointSize: 17) else { return nil }
        let fit = Swift.min(bounds.width / layout.size.width, bounds.height / layout.size.height)
        let originX = bounds.minX + (bounds.width - layout.size.width * fit) / 2
        let originY = bounds.minY + (bounds.height - layout.size.height * fit) / 2
        let ink = CGRect(x: originX + layout.ink.minX * fit, y: originY + layout.ink.minY * fit,
                         width: layout.ink.width * fit, height: layout.ink.height * fit)
        let g = regular.bounds
        let s = Swift.min(ink.width / g.width, ink.height / g.height)
        let c = knockout.circle
        return (CGRect(x: ink.midX - g.midX * s + c.minX * s, y: ink.midY - g.midY * s + c.minY * s,
                       width: c.width * s, height: c.height * s), knockout.pathCount)
    }

    /// Fills `name`'s glyph into `bounds` with `color`. Returns false (and
    /// draws nothing) for unmapped names.
    @discardableResult
    public static func draw(name: String, in canvas: Canvas, bounds: CGRect,
                            color: CanvasColor,
                            weight: UIImage.SymbolWeight = .regular) -> Bool {
        guard let placed = paths(name: name, in: bounds, weight: weight) else { return false }
        var first = 0
        if let knockout = knockout(name: name, in: bounds, weight: weight) {
            // Everything but the knockout circle: a clockwise rectangle
            // around the glyph and the circle wound the other way (nonzero).
            let r = knockout.circle
            let outer = bounds.union(r).insetBy(dx: -r.width, dy: -r.height)
            var clip = Path()
            clip.move(to: CGPoint(x: outer.minX, y: outer.minY))
            clip.addLine(to: CGPoint(x: outer.maxX, y: outer.minY))
            clip.addLine(to: CGPoint(x: outer.maxX, y: outer.maxY))
            clip.addLine(to: CGPoint(x: outer.minX, y: outer.maxY))
            clip.close()
            clip.elements += circlePath(centre: CGPoint(x: r.midX, y: r.midY),
                                        radius: r.width / 2, clockwise: false).elements
            canvas.save()
            canvas.clip(to: clip)
            for path in placed.paths.prefix(knockout.pathCount) {
                canvas.fill(path, color: color, evenOdd: placed.evenOdd)
            }
            canvas.restore()
            first = knockout.pathCount
        }
        for path in placed.paths.dropFirst(first) {
            canvas.fill(path, color: color, evenOdd: placed.evenOdd)
        }
        return true
    }

    // MARK: Glyph cache

    struct Glyph {
        let paths: [Path]
        let evenOdd: Bool
        /// Ink bounds in viewBox units.
        let bounds: CGRect
        /// The first `pathCount` paths are drawn only outside `circle`
        /// (viewBox units).
        var knockout: (circle: CGRect, pathCount: Int)? = nil
    }

    private static var cache: [String: Glyph] = [:]

    static func glyph(for name: String) -> Glyph? {
        if let hit = cache[name] { return hit }
        guard let entry = _OpenSymbolCatalog.entry(name) else { return nil }
        let glyph = build(entry, bold: false)
        cache[name] = glyph
        return glyph
    }

    /// The bold drawing of a regular-weight entry; nil for fill glyphs and
    /// disc composites (Phosphor's fill set has one weight).
    static func boldGlyph(for name: String) -> Glyph? {
        if let hit = boldCache[name] { return hit }
        guard let entry = _OpenSymbolCatalog.entry(name),
              entry.composite != .disc, entry.composite != .badgePlus,
              _OpenSymbolCatalog.pathData(entry.glyph + "-bold") != nil else { return nil }
        let glyph = build(entry, bold: true)
        boldCache[name] = glyph
        return glyph
    }

    private static var boldCache: [String: Glyph] = [:]

    private static func build(_ entry: _OpenSymbolEntry, bold: Bool) -> Glyph {
        let suffix = bold ? "-bold" : ""
        let glyph: Glyph
        switch entry.composite {
        case .none:
            let paths = parsed(entry.glyph + suffix)
            glyph = Glyph(paths: paths, evenOdd: false, bounds: boundsOf(paths))
        case .mirror:
            let paths = parsed(entry.glyph + suffix).map { $0.applying(mirrorAboutCentre) }
            glyph = Glyph(paths: paths, evenOdd: false, bounds: boundsOf(paths))
        case .ring:
            let ring = parsed("circle" + suffix)
            let inner = parsed(entry.glyph + suffix).map { $0.applying(halfSizeAboutCentre) }
            glyph = Glyph(paths: ring + inner, evenOdd: false, bounds: boundsOf(ring))
        case .disc:
            var cut = Path()
            for p in parsed("circle-fill") { cut.elements.append(contentsOf: p.elements) }
            for p in parsed(entry.glyph) {
                cut.elements.append(contentsOf: p.applying(halfSizeAboutCentre).elements)
            }
            glyph = Glyph(paths: [cut], evenOdd: true, bounds: boundsOf([cut]))
        case .badgePlus:
            glyph = badgePlus()
        }
        return glyph
    }

    /// MEASURED `person.fill.badge.plus`, iOS 27.0 simulator, iPhone 16e @3x,
    /// title2 semibold (stupid social's follow row): the ink is a 24 x 24 pt
    /// square (72 px). In units of that square: the head is an ellipse in
    /// [0.195, 0.570] x [0, 0.403]; the body a half-ellipse on the baseline
    /// y 0.847, centred at x 0.379, 0.758 wide and 0.377 tall (its outline
    /// is within 1 px of the reference at every measured row); the badge
    /// disc is centred at (0.768, 0.757) with radius 0.236; the figure is
    /// knocked out within radius 0.292 of the disc's centre (a 4 px gap);
    /// the plus cut out of the disc has arms of half-length 0.146 and
    /// half-width 0.036. The square is 227 viewBox units (24 pt at 22 pt
    /// through the Phosphor optical size, 208 units per point size), centred.
    static let badgePlusGeometry = (
        square: CGRect(x: 14.5, y: 14.5, width: 227, height: 227),
        head: CGRect(x: 0.195, y: 0, width: 0.375, height: 0.403),
        bodyCentre: CGPoint(x: 0.379, y: 0.847), bodyRadii: CGSize(width: 0.379, height: 0.377),
        disc: CGPoint(x: 0.768, y: 0.757), discRadius: CGFloat(0.236),
        knockoutRadius: CGFloat(0.292),
        armHalfLength: CGFloat(0.146), armHalfWidth: CGFloat(0.036)
    )

    private static func badgePlus() -> Glyph {
        let m = badgePlusGeometry
        let u = m.square.width
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: m.square.minX + x * u, y: m.square.minY + y * u)
        }
        let headOrigin = point(m.head.minX, m.head.minY)
        let head = ellipsePath(CGRect(x: headOrigin.x, y: headOrigin.y,
                                      width: m.head.width * u, height: m.head.height * u),
                               clockwise: true)
        let base = point(m.bodyCentre.x, m.bodyCentre.y)
        let rx = m.bodyRadii.width * u, ry = m.bodyRadii.height * u
        let k: CGFloat = 0.5522847498
        var body = Path()
        body.move(to: CGPoint(x: base.x - rx, y: base.y))
        body.addCurve(to: CGPoint(x: base.x, y: base.y - ry),
                      control1: CGPoint(x: base.x - rx, y: base.y - k * ry),
                      control2: CGPoint(x: base.x - k * rx, y: base.y - ry))
        body.addCurve(to: CGPoint(x: base.x + rx, y: base.y),
                      control1: CGPoint(x: base.x + k * rx, y: base.y - ry),
                      control2: CGPoint(x: base.x + rx, y: base.y - k * ry))
        body.close()
        // The disc clockwise, the plus counter-clockwise: nonzero leaves the
        // plus as a hole.
        let centre = point(m.disc.x, m.disc.y)
        var badge = circlePath(centre: centre, radius: m.discRadius * u, clockwise: true)
        let a = m.armHalfLength * u, w = m.armHalfWidth * u
        let cross: [(CGFloat, CGFloat)] = [
            (-w, -a), (-w, -w), (-a, -w), (-a, w), (-w, w), (-w, a),
            (w, a), (w, w), (a, w), (a, -w), (w, -w), (w, -a),
        ]
        badge.move(to: CGPoint(x: centre.x + cross[0].0, y: centre.y + cross[0].1))
        for (dx, dy) in cross.dropFirst() {
            badge.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
        }
        badge.close()
        let r = m.knockoutRadius * u
        let paths = [head, body, badge]
        return Glyph(paths: paths, evenOdd: false, bounds: boundsOf(paths),
                     knockout: (CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r), 2))
    }

    static func circlePath(centre c: CGPoint, radius r: CGFloat, clockwise: Bool) -> Path {
        ellipsePath(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), clockwise: clockwise)
    }

    /// An ellipse of four cubic arcs, clockwise on screen (y down) or not.
    static func ellipsePath(_ rect: CGRect, clockwise: Bool) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        let kx = rx * 0.5522847498, ky = ry * 0.5522847498
        let s: CGFloat = clockwise ? 1 : -1
        var path = Path()
        path.move(to: CGPoint(x: c.x + rx, y: c.y))
        path.addCurve(to: CGPoint(x: c.x, y: c.y + s * ry),
                      control1: CGPoint(x: c.x + rx, y: c.y + s * ky),
                      control2: CGPoint(x: c.x + kx, y: c.y + s * ry))
        path.addCurve(to: CGPoint(x: c.x - rx, y: c.y),
                      control1: CGPoint(x: c.x - kx, y: c.y + s * ry),
                      control2: CGPoint(x: c.x - rx, y: c.y + s * ky))
        path.addCurve(to: CGPoint(x: c.x, y: c.y - s * ry),
                      control1: CGPoint(x: c.x - rx, y: c.y - s * ky),
                      control2: CGPoint(x: c.x - kx, y: c.y - s * ry))
        path.addCurve(to: CGPoint(x: c.x + rx, y: c.y),
                      control1: CGPoint(x: c.x + kx, y: c.y - s * ry),
                      control2: CGPoint(x: c.x + rx, y: c.y - s * ky))
        path.close()
        return path
    }

    private static let mirrorAboutCentre = CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                              tx: 256, ty: 0)

    private static let halfSizeAboutCentre = CGAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5,
                                                                tx: 64, ty: 64)

    private static func parsed(_ key: String) -> [Path] {
        guard let data = _OpenSymbolCatalog.pathData(key) else {
            preconditionFailure("OpenSymbols: catalog has no glyph '\(key)'")
        }
        return data.map { d in
            do {
                return try SVGPathData.parse(d)
            } catch {
                preconditionFailure("OpenSymbols: glyph '\(key)' path data is malformed: \(error)")
            }
        }
    }

    /// Bounds of the drawn outline: on-curve points plus Bézier extrema
    /// sampled at 16 steps (control points overshoot round glyphs).
    static func boundsOf(_ paths: [Path]) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func add(_ p: CGPoint) {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        for path in paths {
            var current = CGPoint(x: 0, y: 0)
            var start = current
            for element in path.elements {
                switch element {
                case .move(let p):
                    add(p); current = p; start = p
                case .line(let p):
                    add(p); current = p
                case .quad(let c, let p):
                    for i in 1...16 {
                        let t = CGFloat(i) / 16, u = 1 - t
                        add(CGPoint(x: u * u * current.x + 2 * u * t * c.x + t * t * p.x,
                                    y: u * u * current.y + 2 * u * t * c.y + t * t * p.y))
                    }
                    current = p
                case .cubic(let c1, let c2, let p):
                    for i in 1...16 {
                        let t = CGFloat(i) / 16, u = 1 - t
                        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                        add(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * p.x,
                                    y: a * current.y + b * c1.y + c * c2.y + d * p.y))
                    }
                    current = p
                case .close:
                    current = start
                }
            }
        }
        guard minX.isFinite, maxX > minX, maxY > minY else {
            return CGRect(x: 0, y: 0, width: 256, height: 256)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
