// ColorEmoji. Owner: text module.
//
// Colour emoji for text layout and drawing (docs/COLOR_EMOJI.md). iOS draws
// emoji with Apple Color Emoji, which is never shipped or derived here. The
// glyph images come from Noto Color Emoji (SIL Open Font License 1.1), a
// CBDT/CBLC font: one strike of PNG images at 109 ppem. Only the images are
// Noto's; advances and placement follow what iOS measures (see
// `ColorEmoji.advanceEm(size:)` and `ColorEmoji.draw`).
//
// What counts as an emoji (UTS #51 presentation): a grapheme cluster whose
// first scalar has Emoji_Presentation, or any Emoji cluster that carries
// U+FE0F, a keycap (U+20E3), a skin-tone modifier, a ZWJ, tag characters, or
// a regional-indicator pair. U+FE0E (text presentation) keeps the text path,
// and so do text-default emoji without U+FE0F (e.g. a bare U+2764): which of
// those iOS draws in colour depends on the system font's coverage, which is
// not measured.
//
// Font file (first readable wins): OpenUIKitRuntime.fontPaths["emoji"], then
// <resourceRoot>/fonts/NotoColorEmoji.ttf, then the Debian/Ubuntu package
// path /usr/share/fonts/truetype/noto/NotoColorEmoji.ttf. Drawing an emoji
// without one is a fatal error naming the paths tried.

#if canImport(CoreGraphics)
import struct CoreFoundation.CGFloat
import struct CoreGraphics.CGPoint
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#elseif canImport(Foundation)
import Foundation
#endif

public enum ColorEmoji {

    // MARK: - Classification

    /// Cheap pre-check: false when `s` cannot contain an emoji cluster, so
    /// callers keep their scalar loops unchanged for ordinary text. Every
    /// emoji cluster has a scalar at or above U+203C (the lowest
    /// Emoji_Presentation scalar is U+231A; U+FE0F / U+20E3 mark the
    /// ASCII-based keycaps and U+00A9 / U+00AE sequences).
    public static func mayContainEmoji<S: StringProtocol>(_ s: S) -> Bool {
        for u in s.unicodeScalars where u.value >= 0x203C { return true }
        return false
    }

    /// True when the grapheme cluster `c` draws as a colour emoji.
    public static func isEmoji(_ c: Character) -> Bool {
        isEmoji(scalars: c.unicodeScalars)
    }

    static func isEmoji<C: Collection>(scalars: C) -> Bool where C.Element == Unicode.Scalar {
        guard let first = scalars.first else { return false }
        let p = first.properties
        if isRegionalIndicator(first) { return true }
        guard p.isEmoji else { return false }
        var sequence = false
        for u in scalars.dropFirst() {
            switch u.value {
            case 0xFE0E: return false                 // text presentation
            case 0xFE0F, 0x20E3, 0x200D, 0x1F3FB...0x1F3FF, 0xE0020...0xE007F:
                sequence = true
            default: break
            }
        }
        // Text-default pictographs above U+1F000 have no text glyph in any
        // bundled font; iOS's cascade draws them from the colour font too.
        return sequence || p.isEmojiPresentation || first.value >= 0x1F000
    }

    static func isRegionalIndicator(_ u: Unicode.Scalar) -> Bool {
        u.value >= 0x1F1E6 && u.value <= 0x1F1FF
    }

    /// Per-scalar roles for `scalars`: n > 0 at the first scalar of an
    /// emoji cluster of n scalars, -1 on its other scalars, 0 elsewhere.
    /// nil when there is no emoji at all (the common case).
    static func roles(of scalars: [Unicode.Scalar]) -> [Int]? {
        guard scalars.contains(where: { $0.value >= 0x203C }) else { return nil }
        var s = String.UnicodeScalarView()
        s.append(contentsOf: scalars)
        let text = String(s)
        var roles = [Int](repeating: 0, count: scalars.count)
        var i = 0
        var any = false
        for c in text {
            let n = c.unicodeScalars.count
            if isEmoji(c) {
                roles[i] = n
                for k in 1..<n { roles[i + k] = -1 }
                any = true
            }
            i += n
        }
        return any ? roles : nil
    }

    // MARK: - Metrics (iOS)

    /// Emoji advance in em of the run's font size: Apple Color Emoji's, as
    /// MEASURED on the iOS 27.0 simulator (iPhone 16e 3x, stupid social;
    /// docs/COLOR_EMOJI.md):
    ///   - 20 pt (UIKit reaction chips, 4 chips): 25.04-25.10 pt from the
    ///     chip widths, i.e. 1.25 em up to the 1/3 pt label rounding;
    ///   - 15 pt (SwiftUI chat previews): 21.2 pt between "ever " and " see"
    ///     around a rocket (1.415 em), and bearings of 0.08-0.13 em on both
    ///     sides of 1.2 em of ink elsewhere;
    ///   - 17 pt (a SwiftUI title before an 8 pt-spaced symbol): about
    ///     1.33-1.36 em.
    /// So small sizes carry extra space after the image (a tracking-like
    /// term, 0.165 em at 15 pt, none at 20 pt). It is interpolated linearly
    /// between 15 and 20 pt and held outside that range (unmeasured there).
    static func advanceEm(size: CGFloat) -> CGFloat {
        let s = Swift.min(20, Swift.max(15, size))
        return 1.25 + 0.165 * (20 - s) / 5
    }

    /// Advance of one emoji cluster in a run of `font`, in points: one emoji
    /// advance per glyph the cluster shapes to (a sequence the font does not
    /// ligate draws its parts side by side, as CoreText does).
    public static func advance<C: Collection>(of scalars: C, font: UIFont) -> CGFloat
        where C.Element == Unicode.Scalar {
        CGFloat(Swift.max(1, glyphs(for: scalars).count)) * font.pointSize
            * advanceEm(size: font.pointSize)
    }

    static var glyphCache: [String: [UInt16]] = [:]

    /// The drawable glyphs of one cluster (glyphs without a strike image,
    /// such as an unligated ZWJ, are dropped).
    static func glyphs<C: Collection>(for scalars: C) -> [UInt16] where C.Element == Unicode.Scalar {
        var key = String.UnicodeScalarView()
        key.append(contentsOf: scalars)
        let k = String(key)
        if let g = glyphCache[k] { return g }
        let f = requireFont()
        let g = f.glyphs(for: scalars).filter { f.image(glyph: $0) != nil }
        glyphCache[k] = g
        return g
    }

    // MARK: - Drawing

    /// Draw cluster `scalars` with its pen at `penX` on `baselineY` (user
    /// space) in a run of `font`. Colour glyphs keep their own colours: the
    /// text colour (and its alpha) does not apply, as on iOS.
    public static func draw<C: Collection>(_ scalars: C, penX: CGFloat, baselineY: CGFloat,
                                           font: UIFont, in canvas: Canvas)
        where C.Element == Unicode.Scalar {
        let f = requireFont()
        let size = font.pointSize
        // Noto's metrics are pixels at the strike's ppem and its em is the
        // run's point size, as CoreText sizes a fallback font. Its image
        // box (ink from 0.07 em after the pen, box bottom 0.25 em below the
        // baseline) sits where Apple's does (ink from 0.08-0.13 em, the
        // deepest ink 0.244 em below the baseline), so its own bearings
        // place it; the iOS advance then adds the space after it.
        let unit = size / CGFloat(f.ppem)
        let step = size * advanceEm(size: size)
        var pen = penX
        for g in glyphs(for: scalars) {
            guard let img = f.image(glyph: g) else { continue }
            let rect = CGRect(x: pen + CGFloat(img.bearingX) * unit,
                              y: baselineY - CGFloat(img.bearingY) * unit,
                              width: CGFloat(img.width) * unit,
                              height: CGFloat(img.height) * unit)
            drawImage(img, glyph: g, in: rect, canvas: canvas)
            pen += step
        }
    }

    /// Draw `img` into `rect`: on an axis-aligned canvas, resampled to the
    /// device pixels it covers with an area filter (the strike is 3-4x the
    /// device size; bilinear sampling would alias) and placed on the pixel
    /// grid; otherwise through the canvas' own image interpolation.
    static func drawImage(_ img: ColorEmojiFont.GlyphImage, glyph: UInt16, in rect: CGRect,
                          canvas: Canvas) {
        let t = canvas.ctm
        guard t.b == 0, t.c == 0, t.a > 0, t.d > 0 else {
            canvas.draw(img.bitmap, in: rect, interpolate: true)
            return
        }
        let x0 = (rect.minX * t.a + t.tx).rounded()
        let y0 = (rect.minY * t.d + t.ty).rounded()
        let w = Int((rect.width * t.a).rounded())
        let h = Int((rect.height * t.d).rounded())
        guard w > 0, h > 0 else { return }
        let scaled = resampled(img.bitmap, glyph: glyph, width: w, height: h)
        let user = CGRect(x: (x0 - t.tx) / t.a, y: (y0 - t.ty) / t.d,
                          width: CGFloat(w) / t.a, height: CGFloat(h) / t.d)
        canvas.draw(scaled, in: user, interpolate: false)
    }

    static var resampleCache: [UInt64: Bitmap] = [:]

    /// Area-average `src` to `width` x `height` (premultiplied while
    /// filtering, straight alpha out, as Bitmap stores it). Cached per
    /// glyph and size.
    static func resampled(_ src: Bitmap, glyph: UInt16, width: Int, height: Int) -> Bitmap {
        let key = UInt64(glyph) << 32 | UInt64(width) << 16 | UInt64(height)
        if let b = resampleCache[key] { return b }
        let sw = src.width, sh = src.height
        // Separable box weights: output column x covers source
        // [x * sw / width, (x + 1) * sw / width).
        func weights(_ n: Int, _ sn: Int) -> [[(Int, Double)]] {
            let step = Double(sn) / Double(n)
            return (0..<n).map { o in
                let a = Double(o) * step, b = a + step
                var out: [(Int, Double)] = []
                var s = Int(a)
                while Double(s) < b && s < sn {
                    let w = Swift.min(b, Double(s + 1)) - Swift.max(a, Double(s))
                    if w > 0 { out.append((s, w / step)) }
                    s += 1
                }
                return out
            }
        }
        let wx = weights(width, sw), wy = weights(height, sh)
        var pre = [Double](repeating: 0, count: sw * sh * 4)
        src.pixels.withUnsafeBufferPointer { p in
            for i in 0..<(sw * sh) {
                let a = Double(p[i * 4 + 3]) / 255
                pre[i * 4] = Double(p[i * 4]) * a
                pre[i * 4 + 1] = Double(p[i * 4 + 1]) * a
                pre[i * 4 + 2] = Double(p[i * 4 + 2]) * a
                pre[i * 4 + 3] = a
            }
        }
        // Horizontal pass: sh rows x width columns.
        var mid = [Double](repeating: 0, count: width * sh * 4)
        for y in 0..<sh {
            for x in 0..<width {
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for (s, w) in wx[x] {
                    let i = (y * sw + s) * 4
                    r += pre[i] * w; g += pre[i + 1] * w; b += pre[i + 2] * w; a += pre[i + 3] * w
                }
                let o = (y * width + x) * 4
                mid[o] = r; mid[o + 1] = g; mid[o + 2] = b; mid[o + 3] = a
            }
        }
        let out = Bitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for (s, w) in wy[y] {
                    let i = (s * width + x) * 4
                    r += mid[i] * w; g += mid[i + 1] * w; b += mid[i + 2] * w; a += mid[i + 3] * w
                }
                let o = (y * width + x) * 4
                if a > 0 {
                    out.pixels[o] = UInt8(Swift.min(255, (r / a).rounded()))
                    out.pixels[o + 1] = UInt8(Swift.min(255, (g / a).rounded()))
                    out.pixels[o + 2] = UInt8(Swift.min(255, (b / a).rounded()))
                    out.pixels[o + 3] = UInt8(Swift.min(255, (a * 255).rounded()))
                }
            }
        }
        resampleCache[key] = out
        return out
    }

    /// A scalar outside every emoji cluster that the run's outline font
    /// (and so every bundled font) has no glyph for. iOS would draw it from
    /// a cascade font (or LastResort's box); drawing nothing would hide the
    /// gap, so it fails by name, like OPENUIKIT_IOS_INK_MISS.
    static func missingGlyph(_ u: Unicode.Scalar, font: UIFont) -> Never {
        fatalError("OPENUIKIT_NO_GLYPH: U+\(String(u.value, radix: 16, uppercase: true)) (\(u.properties.name ?? "unnamed")) at \(font.pointSize) pt — no bundled font covers it (outline fallback: DejaVu Sans; colour emoji: Noto Color Emoji); see docs/COLOR_EMOJI.md")
    }

    // MARK: - Font file

    static var loaded: ColorEmojiFont?
    static var triedPaths: [String]?

    static var candidatePaths: [String] {
        var paths: [String] = []
        if let o = OpenUIKitRuntime.fontPaths["emoji"] { paths.append(o) }
        paths.append(OpenUIKitRuntime.resourceRoot + "/fonts/NotoColorEmoji.ttf")
        paths.append("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf")
        return paths
    }

    /// The colour emoji font, or nil when no candidate file is readable.
    public static var font: ColorEmojiFont? {
        if let f = loaded { return f }
        if triedPaths != nil { return nil }
        let paths = candidatePaths
        for p in paths {
            guard let bytes = ResourceIO.readFile(p), !bytes.isEmpty else { continue }
            guard let f = ColorEmojiFont(bytes: bytes) else {
                fatalError("OPENUIKIT_EMOJI_FONT_INVALID: \(p) is not a CBDT/CBLC colour emoji font this reader supports (expected Noto Color Emoji)")
            }
            loaded = f
            return f
        }
        triedPaths = paths
        return nil
    }

    static func requireFont() -> ColorEmojiFont {
        if let f = font { return f }
        fatalError("OPENUIKIT_EMOJI_FONT_MISSING: text draws an emoji but no colour emoji font is readable (tried \(candidatePaths.joined(separator: ", "))); bundle Noto Color Emoji as <resources>/OpenUIKit/fonts/NotoColorEmoji.ttf (docs/COLOR_EMOJI.md)")
    }
}

/// A CBDT/CBLC colour bitmap font (Noto Color Emoji): cmap format 12/4,
/// GSUB ligature lookups (the emoji sequences), and the PNG strike.
public final class ColorEmojiFont {
    struct GlyphImage {
        var bitmap: Bitmap
        var width: Int, height: Int
        var bearingX: Int, bearingY: Int
    }

    let data: [UInt8]
    let ppem: Int
    /// The font's own emoji advance in em (hmtx of the first emoji glyph /
    /// upem): not used for layout, which follows iOS.
    let advanceEm: CGFloat
    private var cmapGroups: [(start: UInt32, end: UInt32, glyph: UInt32)] = []
    /// Ligature lookups in lookup-list order: first glyph -> [(rest, ligature)].
    private var ligatures: [[UInt16: [([UInt16], UInt16)]]] = []
    private let cbdt: Int
    private var glyphLocation: [UInt16: (offset: Int, length: Int, format: Int)] = [:]
    private var imageCache: [UInt16: GlyphImage?] = [:]

    init?(bytes: [UInt8]) {
        data = bytes
        func u16(_ o: Int) -> Int { Int(bytes[o]) << 8 | Int(bytes[o + 1]) }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        guard bytes.count > 12 else { return nil }
        var tables: [String: Int] = [:]
        let n = u16(4)
        for i in 0..<n {
            let r = 12 + 16 * i
            guard r + 16 <= bytes.count else { return nil }
            let tag = String(decoding: bytes[r..<r + 4], as: UTF8.self)
            tables[tag] = u32(r + 8)
        }
        guard let cmap = tables["cmap"], let cblc = tables["CBLC"], let cbdt = tables["CBDT"],
              let head = tables["head"], let hhea = tables["hhea"], let hmtx = tables["hmtx"]
        else { return nil }
        self.cbdt = cbdt
        let upem = u16(head + 18)
        let numHMetrics = u16(hhea + 34)
        // The first emoji glyph's advance (all Noto emoji share it).
        advanceEm = CGFloat(u16(hmtx + 4 * Swift.min(4, numHMetrics - 1))) / CGFloat(upem)

        // cmap: prefer format 12 (full Unicode), else format 4.
        var groups: [(UInt32, UInt32, UInt32)] = []
        for i in 0..<u16(cmap + 2) {
            let sub = cmap + u32(cmap + 4 + 8 * i + 4)
            if u16(sub) == 12 {
                let count = u32(sub + 12)
                for k in 0..<count {
                    let g = sub + 16 + 12 * k
                    groups.append((UInt32(u32(g)), UInt32(u32(g + 4)), UInt32(u32(g + 8))))
                }
                break
            }
        }
        if groups.isEmpty {
            for i in 0..<u16(cmap + 2) {
                let sub = cmap + u32(cmap + 4 + 8 * i + 4)
                guard u16(sub) == 4 else { continue }
                let segX2 = u16(sub + 6)
                let ends = sub + 14, starts = ends + segX2 + 2
                let deltas = starts + segX2, ranges = deltas + segX2
                for s in 0..<(segX2 / 2) {
                    let end = u16(ends + 2 * s), start = u16(starts + 2 * s)
                    let delta = u16(deltas + 2 * s), ro = u16(ranges + 2 * s)
                    guard start != 0xFFFF else { continue }
                    for c in start...end {
                        var g: Int
                        if ro == 0 {
                            g = (c + delta) & 0xFFFF
                        } else {
                            let at = ranges + 2 * s + ro + 2 * (c - start)
                            g = u16(at)
                            if g != 0 { g = (g + delta) & 0xFFFF }
                        }
                        if g != 0 { groups.append((UInt32(c), UInt32(c), UInt32(g))) }
                    }
                }
                break
            }
        }
        cmapGroups = groups.map { (start: $0.0, end: $0.1, glyph: $0.2) }.sorted { $0.start < $1.start }

        // GSUB: every ligature-substitution lookup (type 4, or 4 inside a
        // type 7 extension), in lookup-list order.
        if let gsub = tables["GSUB"] {
            let list = gsub + u16(gsub + 8)
            for li in 0..<u16(list) {
                let lookup = list + u16(list + 2 + 2 * li)
                var type = u16(lookup)
                var table: [UInt16: [([UInt16], UInt16)]] = [:]
                for si in 0..<u16(lookup + 4) {
                    var st = lookup + u16(lookup + 6 + 2 * si)
                    if type == 7 {
                        type = u16(st + 2)
                        st += u32(st + 4)
                    }
                    guard type == 4 else { continue }
                    let coverage = Self.coverage(bytes, at: st + u16(st + 2))
                    for (glyph, index) in coverage {
                        let set = st + u16(st + 6 + 2 * index)
                        for k in 0..<u16(set) {
                            let lig = set + u16(set + 2 + 2 * k)
                            let comps = u16(lig + 2)
                            let rest = (0..<Swift.max(0, comps - 1)).map { UInt16(u16(lig + 4 + 2 * $0)) }
                            table[glyph, default: []].append((rest, UInt16(u16(lig))))
                        }
                    }
                }
                if !table.isEmpty { ligatures.append(table) }
            }
        }

        // CBLC: the largest strike; index subtable formats 1 (32-bit
        // offsets) and 3 (16-bit offsets), image formats 17 and 18.
        let numSizes = u32(cblc + 4)
        guard numSizes > 0 else { return nil }
        var best = 0
        for s in 0..<numSizes where bytes[cblc + 8 + 48 * s + 44] > bytes[cblc + 8 + 48 * best + 44] {
            best = s
        }
        let size = cblc + 8 + 48 * best
        ppem = Int(bytes[size + 44])
        let arrayOffset = u32(size), subtables = u32(size + 8)
        for k in 0..<subtables {
            let rec = cblc + arrayOffset + 8 * k
            let first = u16(rec), last = u16(rec + 2)
            let sub = cblc + arrayOffset + u32(rec + 4)
            let indexFormat = u16(sub), imageFormat = u16(sub + 2), dataOffset = u32(sub + 4)
            guard imageFormat == 17 || imageFormat == 18 else { return nil }
            for g in first...last {
                let i = g - first
                let a: Int, b: Int
                switch indexFormat {
                case 1: a = u32(sub + 8 + 4 * i); b = u32(sub + 8 + 4 * (i + 1))
                case 3: a = u16(sub + 8 + 2 * i); b = u16(sub + 8 + 2 * (i + 1))
                default: return nil
                }
                if b > a {
                    glyphLocation[UInt16(g)] = (cbdt + dataOffset + a, b - a, imageFormat)
                }
            }
        }
    }

    static func coverage(_ d: [UInt8], at o: Int) -> [(UInt16, Int)] {
        func u16(_ o: Int) -> Int { Int(d[o]) << 8 | Int(d[o + 1]) }
        var out: [(UInt16, Int)] = []
        if u16(o) == 1 {
            for i in 0..<u16(o + 2) { out.append((UInt16(u16(o + 4 + 2 * i)), i)) }
        } else {
            for i in 0..<u16(o + 2) {
                let r = o + 4 + 6 * i
                let s = u16(r), e = u16(r + 2), si = u16(r + 4)
                if e >= s { for g in s...e { out.append((UInt16(g), si + g - s)) } }
            }
        }
        return out
    }

    func glyph(of u: Unicode.Scalar) -> UInt16 {
        var lo = 0, hi = cmapGroups.count - 1
        while lo <= hi {
            let m = (lo + hi) / 2
            let g = cmapGroups[m]
            if u.value < g.start { hi = m - 1 } else if u.value > g.end { lo = m + 1 } else {
                return UInt16(truncatingIfNeeded: g.glyph + (u.value - g.start))
            }
        }
        return 0
    }

    /// Glyphs for one emoji cluster: cmap (variation selectors dropped, as
    /// a shaper does for this font) followed by the ligature lookups.
    /// Fails loudly on a scalar the font does not cover.
    func glyphs<C: Collection>(for scalars: C) -> [UInt16] where C.Element == Unicode.Scalar {
        var gs: [UInt16] = []
        for u in scalars where u.value != 0xFE0F && u.value != 0xFE0E {
            let g = glyph(of: u)
            if g == 0 {
                let seq = scalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }
                fatalError("OPENUIKIT_EMOJI_MISSING: the colour emoji font has no glyph for U+\(String(u.value, radix: 16, uppercase: true)) in the emoji sequence \(seq.joined(separator: " ")) (Noto Color Emoji predates it?)")
            }
            gs.append(g)
        }
        for table in ligatures {
            var out: [UInt16] = []
            var i = 0
            while i < gs.count {
                var matched = false
                if let candidates = table[gs[i]] {
                    for (rest, lig) in candidates where i + 1 + rest.count <= gs.count
                        && Array(gs[(i + 1)..<(i + 1 + rest.count)]) == rest {
                        out.append(lig)
                        i += 1 + rest.count
                        matched = true
                        break
                    }
                }
                if !matched { out.append(gs[i]); i += 1 }
            }
            gs = out
        }
        return gs
    }

    /// The decoded strike image of `glyph` and its metrics (pixels at ppem).
    func image(glyph: UInt16) -> GlyphImage? {
        if let cached = imageCache[glyph] { return cached }
        var result: GlyphImage?
        if let loc = glyphLocation[glyph] {
            let o = loc.offset
            let height = Int(data[o]), width = Int(data[o + 1])
            let bx = Int(Int8(bitPattern: data[o + 2])), by = Int(Int8(bitPattern: data[o + 3]))
            let pngStart = loc.format == 17 ? o + 9 : o + 12
            let lenAt = pngStart - 4
            let len = Int(data[lenAt]) << 24 | Int(data[lenAt + 1]) << 16
                | Int(data[lenAt + 2]) << 8 | Int(data[lenAt + 3])
            guard let bitmap = ImageCodec.decode(Array(data[pngStart..<pngStart + len])) else {
                fatalError("OPENUIKIT_EMOJI_IMAGE_INVALID: glyph \(glyph)'s strike image does not decode as PNG")
            }
            result = GlyphImage(bitmap: bitmap, width: width, height: height,
                                bearingX: bx, bearingY: by)
        }
        imageCache[glyph] = result
        return result
    }
}
