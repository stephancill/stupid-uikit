// ADDITIVE Canvas extension: gamma-space text blending. Owner: text module
// (new capability file; does not modify the frozen Canvas contract or the
// rasterizer — it only adds an overload, as the contract permits).
//
// Real UIKit composites glyph coverage against the destination in a
// power-law space (exponent ~0.79 on normalized sRGB bytes; fitted from
// Catalyst oracle renders of colored text). For a text foreground color
// C with alpha a over destination D, per channel:
//
//     F   = D + a * (C - D)              (sRGB pre-composite of the color)
//     out = (D^g + (F^g - D^g) * cov)^(1/g)
//
// where cov is the TRUE glyph coverage. For the calibration case
// (black/white label text) this reduces exactly to the plain sRGB lerp
// that `drawMask(_:width:height:atPixelX:pixelY:color:)` performs with
// pre-distorted coverage, but for saturated colors (link blue, tint
// colors) the channels diverge; this overload reproduces the real thing.

extension Canvas {
    /// Draw an 8-bit TRUE-coverage mask with gamma-space blending.
    /// `origin` in device pixels, like the plain drawMask.
    ///
    /// Where the destination is transparent there is nothing to blend
    /// against; the coverage then accumulates into the alpha channel using
    /// the sRGB-effective coverage of the appropriate polarity
    /// (`darkCalibration`: glyph calibrated against a black background),
    /// matching how real UIKit label layers store glyph ink.
    ///
    /// Dispatched through the backend like every other drawing op: the
    /// Quartz backend's QZ backing is the authoritative surface and
    /// `bitmap.pixels` only its mirror, so blending into the mirror directly
    /// was overwritten by the next op whose sync region overlapped it (the
    /// following glyph's mask erased harvested-ink glyphs at 2x).
    public func drawMask(_ mask: [UInt8], width: Int, height: Int,
                         atPixelX x: Int, pixelY y: Int, color: CanvasColor,
                         blendGamma gamma: CGFloat, darkCalibration: Bool = false) {
        guard let blend = _TextGammaBlend(color: color, gamma: gamma,
                                          darkCalibration: darkCalibration) else { return }
        backend.drawMaskGamma(mask, width: width, height: height,
                              atPixelX: x, pixelY: y, blend: blend)
    }

    /// Swift-rasterizer implementation: blends into the straight-alpha
    /// `bitmap.pixels`, which that backend owns.
    func _drawMaskGamma(_ mask: [UInt8], _ w: Int, _ h: Int, _ ox: Int, _ oy: Int,
                        _ blend: _TextGammaBlend) {
        let bw = bitmap.width
        _TextGammaBlend.forEachCoveredPixel(mask, w, h, ox, oy, surfaceWidth: bw,
                                            surfaceHeight: bitmap.height,
                                            clip: state.clipMask) { x, y, cov in
            let o = (y * bw + x) * 4
            var px = (bitmap.pixels[o], bitmap.pixels[o + 1],
                      bitmap.pixels[o + 2], bitmap.pixels[o + 3])
            blend.apply(&px, coverage: cov)
            bitmap.pixels[o] = px.0; bitmap.pixels[o + 1] = px.1
            bitmap.pixels[o + 2] = px.2; bitmap.pixels[o + 3] = px.3
        }
    }
}

/// The per-pixel gamma text blend on STRAIGHT-alpha RGBA8, shared by both
/// canvas backends so their glyph ink is identical.
struct _TextGammaBlend {
    let lut: _GammaLUT
    let ca: CGFloat
    let src: (CGFloat, CGFloat, CGFloat)
    let darkCal: Bool
    let caG: CGFloat
    let caDarkG: CGFloat

    init?(color: CanvasColor, gamma: CGFloat, darkCalibration: Bool) {
        guard color.alpha > 0 else { return nil }
        lut = _GammaLUT.shared(gamma: gamma)
        ca = color.alpha
        src = (color.red, color.green, color.blue)
        darkCal = darkCalibration
        // Forward map: true coverage -> the sRGB-effective source alpha the
        // layer stores over transparent destinations. The contrast of the
        // map is the COLOR's alpha (verified against oracle renders of both
        // the 0.847-alpha label color and fully-opaque tint colors).
        caG = lut.toGamma(1 - ca)      // (1-ca)^g, light polarity
        caDarkG = lut.toGamma(ca)      // ca^g, dark polarity
    }

    /// Visits every mask pixel with nonzero coverage (after the clip),
    /// clipped to the surface; `body(x, y, coverage)` in device pixels.
    static func forEachCoveredPixel(_ mask: [UInt8], _ w: Int, _ h: Int,
                                    _ ox: Int, _ oy: Int,
                                    surfaceWidth bw: Int, surfaceHeight bh: Int,
                                    clip: [UInt8]?,
                                    _ body: (Int, Int, CGFloat) -> Void) {
        guard w > 0, h > 0 else { return }
        let my0 = Swift.max(0, -oy), my1 = Swift.min(h, bh - oy)
        let mx0 = Swift.max(0, -ox), mx1 = Swift.min(w, bw - ox)
        guard my0 < my1, mx0 < mx1 else { return }
        for my in my0..<my1 {
            let yy = oy + my
            let maskRow = my * w
            let rowBase = yy * bw
            for mx in mx0..<mx1 {
                let mv = mask[maskRow + mx]
                if mv == 0 { continue }
                let xx = ox + mx
                var cov = CGFloat(mv) / 255
                if let m = clip {
                    let cv = m[rowBase + xx]
                    if cv == 0 { continue }
                    cov *= CGFloat(cv) / 255
                }
                if cov <= 0 { continue }
                body(xx, yy, cov)
            }
        }
    }

    func apply(_ px: inout (UInt8, UInt8, UInt8, UInt8), coverage cov: CGFloat) {
        let da = CGFloat(px.3) / 255
        // sRGB-effective source alpha over transparent destinations.
        let aSrc: CGFloat
        if darkCal {
            aSrc = lut.fromGamma(caDarkG * cov)
        } else {
            aSrc = 1 - lut.fromGamma(1 - (1 - caG) * cov)
        }
        let outA = aSrc + da * (1 - aSrc)
        if outA <= 0 {
            px = (0, 0, 0, 0)
            return
        }
        func b8(_ v: CGFloat) -> UInt8 { UInt8((v * 255).rounded().clamped(0, 255)) }
        func channel(_ d8: UInt8, _ s: CGFloat) -> UInt8 {
            if da <= 0 {
                // Transparent destination: ink accumulates as colored alpha.
                return b8(s)
            }
            let d = CGFloat(d8) / 255
            let f = d + ca * (s - d)
            let outG = lut.toGamma(d) + (lut.toGamma(f) - lut.toGamma(d)) * cov
            let blended = lut.fromGamma(outG)
            if da >= 1 {
                // Opaque destination: pure per-channel gamma blend.
                return b8(blended)
            }
            // Mixed: blend of the two regimes weighted by dst alpha.
            return b8((blended * da + s * aSrc * (1 - da)) / outA)
        }
        px = (channel(px.0, src.0), channel(px.1, src.1), channel(px.2, src.2), b8(outA))
    }
}

/// Power-law lookup tables for the text blend (built once per gamma).
final class _GammaLUT {
    let gamma: CGFloat
    /// x^gamma and x^(1/gamma) sampled on 1025 points over [0, 1].
    private var up: [CGFloat] = []
    private var down: [CGFloat] = []

    private static var cached: _GammaLUT?
    static func shared(gamma: CGFloat) -> _GammaLUT {
        if let c = cached, c.gamma == gamma { return c }
        let l = _GammaLUT(gamma: gamma)
        cached = l
        return l
    }

    init(gamma: CGFloat) {
        self.gamma = gamma
        up.reserveCapacity(1025)
        down.reserveCapacity(1025)
        for i in 0...1024 {
            let x = CGFloat(i) / 1024
            up.append(_GammaLUT.pow(x, gamma))
            down.append(_GammaLUT.pow(x, 1 / gamma))
        }
    }

    @inline(__always) private func sample(_ t: [CGFloat], _ x: CGFloat) -> CGFloat {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let f = x * 1024
        let i = Int(f)
        let r = f - CGFloat(i)
        return t[i] + (t[i + 1] - t[i]) * r
    }
    @inline(__always) func toGamma(_ x: CGFloat) -> CGFloat { sample(up, x) }
    @inline(__always) func fromGamma(_ x: CGFloat) -> CGFloat { sample(down, x) }

    /// x^p for x in [0,1], p in (0,4): exp(p * ln x) with pure-Swift series.
    static func pow(_ x: CGFloat, _ p: CGFloat) -> CGFloat {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return exp(p * ln(x))
    }
    static func ln(_ x0: CGFloat) -> CGFloat {
        // Normalize x = m * 2^k with m in [0.5, 1).
        var x = x0
        var k = 0
        while x < 0.5 { x *= 2; k -= 1 }
        while x >= 1 { x /= 2; k += 1 }
        let z = (x - 1) / (x + 1)  // in [-1/3, 0)
        let z2 = z * z
        var term = z
        var sum: CGFloat = 0
        var n: CGFloat = 1
        for _ in 0..<12 {
            sum += term / n
            term *= z2
            n += 2
        }
        return 2 * sum + CGFloat(k) * 0.6931471805599453
    }
    static func exp(_ x: CGFloat) -> CGFloat {
        let k = (x * 1.4426950408889634).rounded()
        let r = x - k * 0.6931471805599453
        var term: CGFloat = 1
        var sum: CGFloat = 1
        for i in 1...14 {
            term *= r / CGFloat(i)
            sum += term
        }
        var p = sum
        var n = Int(k)
        while n > 0 { p *= 2; n -= 1 }
        while n < 0 { p /= 2; n += 1 }
        return p
    }
}
