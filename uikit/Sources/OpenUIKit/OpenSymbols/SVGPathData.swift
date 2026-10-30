// SVG path data (`<path d="…">`) → OpenCoreGraphics `Path`.
//
// Implements the SVG 1.1 path grammar: M/L/H/V/C/S/Q/T/A/Z, absolute and
// relative, implicit command repetition (extra pairs after M are lineto),
// compact numbers ("1.5.5", "-1-2", exponents) and compact arc flags
// ("a8 8 0 018 8"). Arcs become cubic Béziers (≤ 90° per segment) using the
// endpoint → centre conversion of SVG 1.1 implementation notes F.6.5/F.6.6.
// Malformed data throws; nothing is silently dropped.

#if canImport(CoreGraphics)
import struct CoreFoundation.CGFloat
import struct CoreGraphics.CGPoint
#endif

public enum SVGPathDataError: Error, Equatable {
    case unexpectedCharacter(offset: Int)
    case expectedNumber(offset: Int)
    case expectedFlag(offset: Int)
    case missingInitialMoveTo
}

public enum SVGPathData {
    /// Parses SVG path data into a `Path` in the data's own coordinates.
    public static func parse(_ data: String) throws -> Path {
        var parser = _SVGPathParser(bytes: Array(data.utf8))
        return try parser.run()
    }
}

private struct _SVGPathParser {
    let bytes: [UInt8]
    var index = 0
    var path = Path()
    var current = CGPoint(x: 0, y: 0)
    var subpathStart = CGPoint(x: 0, y: 0)
    /// Reflection sources for S/s and T/t.
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?
    var hasCurrentPoint = false

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func run() throws -> Path {
        skipSeparators()
        while index < bytes.count {
            let command = bytes[index]
            guard Self.isCommand(command) else {
                throw SVGPathDataError.unexpectedCharacter(offset: index)
            }
            index += 1
            try parseCommand(command)
            skipSeparators()
        }
        return path
    }

    static func isCommand(_ c: UInt8) -> Bool {
        switch c {
        case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
             UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
             UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
             UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
             UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
            return true
        default:
            return false
        }
    }

    mutating func parseCommand(_ command: UInt8) throws {
        let relative = command >= UInt8(ascii: "a")
        let upper = relative ? command - 32 : command
        if upper != UInt8(ascii: "M"), !hasCurrentPoint {
            throw SVGPathDataError.missingInitialMoveTo
        }
        switch upper {
        case UInt8(ascii: "Z"):
            path.close()
            current = subpathStart
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "M"):
            var first = true
            repeat {
                let p = try point(relative: relative)
                if first {
                    path.move(to: p)
                    subpathStart = p
                    hasCurrentPoint = true
                    first = false
                } else {
                    path.addLine(to: p)
                }
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "L"):
            repeat {
                let p = try point(relative: relative)
                path.addLine(to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "H"):
            repeat {
                let x = try number()
                let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "V"):
            repeat {
                let y = try number()
                let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "C"):
            repeat {
                let c1 = try point(relative: relative)
                let c2 = try point(relative: relative)
                let p = try point(relative: relative)
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastCubicControl = c2
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "S"):
            repeat {
                let c1 = reflect(lastCubicControl)
                let c2 = try point(relative: relative)
                let p = try point(relative: relative)
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastCubicControl = c2
                lastQuadControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "Q"):
            repeat {
                let c = try point(relative: relative)
                let p = try point(relative: relative)
                path.addQuad(to: p, control: c)
                current = p
                lastQuadControl = c
                lastCubicControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "T"):
            repeat {
                let c = reflect(lastQuadControl)
                let p = try point(relative: relative)
                path.addQuad(to: p, control: c)
                current = p
                lastQuadControl = c
                lastCubicControl = nil
            } while hasMoreNumbers()
        case UInt8(ascii: "A"):
            repeat {
                let rx = try number()
                let ry = try number()
                let rotation = try number()
                let largeArc = try flag()
                let sweep = try flag()
                let p = try point(relative: relative)
                appendArc(rx: rx, ry: ry, rotationDegrees: rotation,
                          largeArc: largeArc, sweep: sweep, to: p)
                current = p
                lastCubicControl = nil
                lastQuadControl = nil
            } while hasMoreNumbers()
        default:
            throw SVGPathDataError.unexpectedCharacter(offset: index - 1)
        }
    }

    func reflect(_ control: CGPoint?) -> CGPoint {
        guard let control else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    mutating func point(relative: Bool) throws -> CGPoint {
        let x = try number()
        let y = try number()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    // MARK: Lexing

    static func isSeparator(_ c: UInt8) -> Bool {
        c == UInt8(ascii: " ") || c == UInt8(ascii: ",") || c == 0x09 || c == 0x0A
            || c == 0x0C || c == 0x0D
    }

    static func isDigit(_ c: UInt8) -> Bool {
        c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
    }

    mutating func skipSeparators() {
        while index < bytes.count, Self.isSeparator(bytes[index]) { index += 1 }
    }

    mutating func hasMoreNumbers() -> Bool {
        skipSeparators()
        guard index < bytes.count else { return false }
        let c = bytes[index]
        return Self.isDigit(c) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+")
            || c == UInt8(ascii: ".")
    }

    mutating func flag() throws -> Bool {
        skipSeparators()
        guard index < bytes.count else { throw SVGPathDataError.expectedFlag(offset: index) }
        let c = bytes[index]
        guard c == UInt8(ascii: "0") || c == UInt8(ascii: "1") else {
            throw SVGPathDataError.expectedFlag(offset: index)
        }
        index += 1
        return c == UInt8(ascii: "1")
    }

    mutating func number() throws -> CGFloat {
        skipSeparators()
        let start = index
        if index < bytes.count,
           bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") {
            index += 1
        }
        var digits = 0
        while index < bytes.count, Self.isDigit(bytes[index]) { index += 1; digits += 1 }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            while index < bytes.count, Self.isDigit(bytes[index]) { index += 1; digits += 1 }
        }
        guard digits > 0 else { throw SVGPathDataError.expectedNumber(offset: start) }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            var probe = index + 1
            if probe < bytes.count,
               bytes[probe] == UInt8(ascii: "-") || bytes[probe] == UInt8(ascii: "+") {
                probe += 1
            }
            if probe < bytes.count, Self.isDigit(bytes[probe]) {
                index = probe
                while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
            }
        }
        var text = ""
        text.unicodeScalars.reserveCapacity(index - start)
        for b in bytes[start..<index] { text.unicodeScalars.append(Unicode.Scalar(b)) }
        guard let value = Double(text), value.isFinite else {
            throw SVGPathDataError.expectedNumber(offset: start)
        }
        return CGFloat(value)
    }

    // MARK: Arcs (SVG 1.1 F.6.5 endpoint → centre, F.6.6 radius correction)

    mutating func appendArc(rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDegrees: CGFloat,
                            largeArc: Bool, sweep: Bool, to end: CGPoint) {
        let start = current
        if start.x == end.x, start.y == end.y { return }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }
        let phi = Double(rotationDegrees) * Double.pi / 180
        let cosPhi = CGFloat(_svgCos(phi))
        let sinPhi = CGFloat(_svgSin(phi))
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        var numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        if numerator < 0 { numerator = 0 }
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        var coefficient = denominator == 0 ? 0 : (numerator / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = _svgAtan2(Double(uy), Double(ux))
        var delta = _svgAtan2(Double(ux * vy - uy * vx), Double(ux * vx + uy * vy))
        if !sweep, delta > 0 { delta -= 2 * Double.pi }
        if sweep, delta < 0 { delta += 2 * Double.pi }

        let segments = Swift.max(1, Int((abs(delta) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * _svgTan(step / 4)
        var angle = theta1
        for i in 0..<segments {
            let cos1 = _svgCos(angle), sin1 = _svgSin(angle)
            let angle2 = angle + step
            let cos2 = _svgCos(angle2), sin2 = _svgSin(angle2)
            // Unit-circle segment, scaled by the radii, rotated by phi, moved to centre.
            func map(_ x: Double, _ y: Double) -> CGPoint {
                let px = CGFloat(x) * rx
                let py = CGFloat(y) * ry
                return CGPoint(x: cosPhi * px - sinPhi * py + cx,
                               y: sinPhi * px + cosPhi * py + cy)
            }
            let c1 = map(cos1 - t * sin1, sin1 + t * cos1)
            let c2 = map(cos2 + t * sin2, sin2 - t * cos2)
            let p = i == segments - 1 ? end : map(cos2, sin2)
            path.addCurve(to: p, control1: c1, control2: c2)
            angle = angle2
        }
    }
}

// Foundation-free trigonometry (OpenUIKit's target rule: no Foundation).
// Range-reduced Taylor/minimax evaluations, accurate to ~1e-12 over the
// inputs arcs produce; arcs feed a rasterizer at sub-pixel tolerance.

func _svgSin(_ x: Double) -> Double {
    let twoPi = 2 * Double.pi
    var r = x - twoPi * (x / twoPi).rounded()
    // r in [-pi, pi]; fold to [-pi/2, pi/2].
    if r > Double.pi / 2 { r = Double.pi - r }
    if r < -Double.pi / 2 { r = -Double.pi - r }
    let r2 = r * r
    var term = r
    var sum = r
    var n = 1.0
    for _ in 0..<10 {
        term *= -r2 / ((n + 1) * (n + 2))
        sum += term
        n += 2
    }
    return sum
}

func _svgCos(_ x: Double) -> Double {
    _svgSin(x + Double.pi / 2)
}

func _svgTan(_ x: Double) -> Double {
    _svgSin(x) / _svgCos(x)
}

func _svgAtan(_ x: Double) -> Double {
    // atan(x) = 2 atan(x / (1 + sqrt(1 + x²))) halves the argument; three
    // halvings bring |x| ≤ ~0.2 where the series converges quickly.
    var v = x
    var scale = 1.0
    for _ in 0..<3 {
        v = v / (1 + (1 + v * v).squareRoot())
        scale *= 2
    }
    let v2 = v * v
    var term = v
    var sum = v
    var k = 1.0
    for _ in 0..<20 {
        term *= -v2
        k += 2
        sum += term / k
    }
    return sum * scale
}

func _svgAtan2(_ y: Double, _ x: Double) -> Double {
    if x > 0 { return _svgAtan(y / x) }
    if x < 0 { return y >= 0 ? _svgAtan(y / x) + Double.pi : _svgAtan(y / x) - Double.pi }
    if y > 0 { return Double.pi / 2 }
    if y < 0 { return -Double.pi / 2 }
    return 0
}
