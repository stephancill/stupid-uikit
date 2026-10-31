// CAShapeLayer: a layer that fills and strokes a path, and the renderers'
// view of it. Owner: view module (docs/SHAPE_MASKS.md).
//
// Where Apple's frameworks exist (`canImport(CoreGraphics)`), CAShapeLayer is
// QuartzCore's own class (QuartzCoreUnification.swift); the extension below
// only reads it. Linux ELF and the Mach-O guests get the portable subset
// declared here, next to OpenUIKit's own CALayer (UIView.swift). Its `path`
// is the renderer's `Path`, the same type `UIBezierPath.cgPath` returns
// there, so `shape.path = UIBezierPath(...).cgPath` reads as in UIKit.
//
// Rendering: UIRenderer.renderLayer fills then strokes the path above the
// layer's background and below its sublayers and border, as Core Animation
// does; LayerBridge maps it to quartz's QZShapeLayer. As a `CALayer.mask`
// the shape's rendered alpha (fill alpha, stroke alpha, opacity) is the mask.
//
// Not modelled (absent from the portable class, so code using them fails to
// compile rather than rendering differently): strokeStart/strokeEnd,
// lineDashPattern/lineDashPhase, and animation of path/colour properties.

#if canImport(CoreGraphics)
import struct CoreFoundation.CGFloat
import struct CoreGraphics.CGPoint
import struct CoreGraphics.CGRect
import QuartzCore
#elseif canImport(Foundation)
import Foundation
#endif

#if !canImport(CoreGraphics)
/// `CAShapeLayerFillRule`.
public struct CAShapeLayerFillRule: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = CAShapeLayerFillRule(rawValue: "non-zero")
    public static let evenOdd = CAShapeLayerFillRule(rawValue: "even-odd")
}

/// `CAShapeLayerLineCap`.
public struct CAShapeLayerLineCap: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = CAShapeLayerLineCap(rawValue: "butt")
    public static let round = CAShapeLayerLineCap(rawValue: "round")
    public static let square = CAShapeLayerLineCap(rawValue: "square")
}

/// `CAShapeLayerLineJoin`.
public struct CAShapeLayerLineJoin: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = CAShapeLayerLineJoin(rawValue: "miter")
    public static let round = CAShapeLayerLineJoin(rawValue: "round")
    public static let bevel = CAShapeLayerLineJoin(rawValue: "bevel")
}

/// Portable CAShapeLayer subset (Core Animation defaults: black fill, no
/// stroke, 1 pt line, non-zero fill rule, butt caps, miter joins, miter
/// limit 10).
@preconcurrency @MainActor
public final class CAShapeLayer: CALayer {
    public var path: Path?
    private var storedFillColor = _LayerColor(
        value: CanvasColor(red: 0, green: 0, blue: 0, alpha: 1))
    private var storedStrokeColor = _LayerColor(value: nil)
    public var fillColor: CGColor? {
        get { storedFillColor.cgColor }
        set { storedFillColor.set(newValue) }
    }
    public var strokeColor: CGColor? {
        get { storedStrokeColor.cgColor }
        set { storedStrokeColor.set(newValue) }
    }
    public var fillRule: CAShapeLayerFillRule = .nonZero
    public var lineWidth: CGFloat = 1
    public var lineCap: CAShapeLayerLineCap = .butt
    public var lineJoin: CAShapeLayerLineJoin = .miter
    public var miterLimit: CGFloat = 10

    var _fillColorValue: CanvasColor? { storedFillColor.value }
    var _strokeColorValue: CanvasColor? { storedStrokeColor.value }

    public override init() { super.init() }
#if !_runtime(_ObjC)
    public required init(owner: UIView) { super.init(owner: owner) }
#endif
}

extension CAShapeLayer {
    var _shapePath: Path? { path }
}
#else
extension CAShapeLayer {
    var _shapePath: Path? { path.map { Path($0) } }
    var _fillColorValue: CanvasColor? { fillColor.map(CanvasColor.init) }
    var _strokeColorValue: CanvasColor? { strokeColor.map(CanvasColor.init) }
}
#endif

/// What the renderers draw for one shape layer, in its bounds space.
struct _CAShapeRenderState {
    var path: Path
    var fill: CanvasColor?
    var evenOdd: Bool
    var stroke: CanvasColor?
    var lineWidth: CGFloat
    var cap: CanvasLineCap
    var join: CanvasLineJoin
    var miterLimit: CGFloat
}

extension CAShapeLayer {
    var _shapeRenderState: _CAShapeRenderState? {
        guard let path = _shapePath, !path.elements.isEmpty else { return nil }
        let fill = _fillColorValue.flatMap { $0.alpha > 0 ? $0 : nil }
        let width = lineWidth.isFinite ? Swift.max(0, lineWidth) : 0
        let stroke = _strokeColorValue.flatMap {
            $0.alpha > 0 && width > 0 ? $0 : nil
        }
        let cap: CanvasLineCap
        switch lineCap {
        case .round: cap = .round
        case .square: cap = .square
        default: cap = .butt
        }
        let join: CanvasLineJoin
        switch lineJoin {
        case .round: join = .round
        case .bevel: join = .bevel
        default: join = .miter
        }
        return _CAShapeRenderState(
            path: path, fill: fill, evenOdd: fillRule == .evenOdd,
            stroke: stroke, lineWidth: width, cap: cap, join: join,
            miterLimit: miterLimit)
    }

    /// A shape layer with the exact geometry the render pass draws for a
    /// UIView with `cornerRadius` (and, when `borderWidth` is set, only its
    /// border ring: outer rounded rect minus the rect inset by the width with
    /// radius `cornerRadius - borderWidth`, even-odd), filled at `alpha`.
    /// SwiftUI's `.mask` uses it to turn a shape view into a mask layer.
    @MainActor
    public static func _openLayerShape(
        frame: CGRect,
        cornerRadius: CGFloat,
        borderWidth: CGFloat?,
        alpha: CGFloat
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        let bounds = layer.bounds
        let radius = Swift.max(0, cornerRadius)
        var path = UIRenderer.layerRoundedRect(bounds, cornerRadius: radius)
        var evenOdd = false
        if let width = borderWidth {
            let inner = bounds.insetBy(dx: width, dy: width)
            if !inner.isNull, inner.width > 0, inner.height > 0 {
                path.elements += UIRenderer.layerRoundedRect(
                    inner, cornerRadius: Swift.max(0, radius - width)).elements
                evenOdd = true
            }
        }
#if canImport(CoreGraphics)
        layer.path = path._cgPath
#else
        layer.path = path
#endif
        layer.fillColor = CanvasColor(
            red: 0, green: 0, blue: 0,
            alpha: Swift.min(Swift.max(alpha, 0), 1)).cgColor
        layer.fillRule = evenOdd ? .evenOdd : .nonZero
        return layer
    }
}
