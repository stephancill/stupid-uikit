// Native gate for SwiftUI shape stroke geometry (docs/SHAPE_STROKES.md):
// `stroke` centres the line on the shape's outline (half of it outside the
// frame, not clipped), `strokeBorder` keeps it inside, for solid colours,
// gradients (the masked style) and StrokeStyle arcs, in both compositors.
// Also the two chrome items of the same parity pass: the `badge-plus` open
// symbol composite and the iOS 27 glass platter rim.
//
//   swift run swiftuistrokeprobe     exits 0 when every check passes
//
// Drives UIHostingController directly, as swiftuishapemaskprobe does. Every
// shape is a 40 x 40 pt overlay on a `Color` whose placed frame is the
// shape's frame F; pixels are sampled at 2x on whole device pixels.
import Foundation
@testable import OpenUIKit
@testable import SwiftUI

@MainActor enum Probe {
    static var failures = 0
}

@MainActor func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { Probe.failures += 1 }
}

/// Straight-alpha RGBA of the device pixel whose top-left corner is at
/// (x, y) points (so a sample covers [x, x + 0.5] at 2x).
func pixel(_ bitmap: Bitmap, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 2) -> [UInt8] {
    let px = Int((x * scale).rounded(.down)), py = Int((y * scale).rounded(.down))
    guard px >= 0, py >= 0, px < bitmap.width, py < bitmap.height else { return [0, 0, 0, 0] }
    let o = (py * bitmap.width + px) * 4
    return Array(bitmap.pixels[o..<o + 4])
}

/// SwiftUI's `Color.red` (system red) fully covering the pixel.
func isRed(_ p: [UInt8]) -> Bool { p[3] > 250 && p[0] > 230 && p[1] < 90 && p[2] < 90 }
/// Opaque gradient ink (purple → orange: never white or the blue base).
func isInk(_ p: [UInt8]) -> Bool { p[3] > 250 && !(p[0] > 245 && p[1] > 245 && p[2] > 245) && p[0] > 120 }
/// The host's background: transparent or white.
func isBackground(_ p: [UInt8]) -> Bool {
    p[3] == 0 || (p[0] > 250 && p[1] > 250 && p[2] > 250)
}
func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
        && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
}
func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 }

enum Compositor: String, CaseIterable { case renderPass, layers }

@MainActor func render(_ view: UIView, _ compositor: Compositor) -> Bitmap {
    switch compositor {
    case .renderPass: return UIRenderer.renderPassRender(view, scale: 2)
    case .layers: return LayerBridge.render(view, scale: 2)
    }
}

@MainActor func find(_ id: String, in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == id { return view }
    for s in view.subviews { if let f = find(id, in: s) { return f } }
    return nil
}

/// A hosted 40 x 40 frame with `shape` overlaid; returns the host, the
/// shape frame F in host coordinates and the overlay's view of `id`.
@MainActor func host(
    _ shape: some View, base: Color = .clear, clipBase: Bool = false, id: String
) -> (UIHostingController<AnyView>, CGRect, UIView?) {
    // The overlaid view is 40 x 40 because padding hands it exactly that
    // rect inside the 120 x 120 host.
    let content: AnyView = clipBase
        ? AnyView(base.clipShape(Circle()).overlay { shape }.frame(width: 40, height: 40).padding(40))
        : AnyView(base.overlay { shape }.frame(width: 40, height: 40).padding(40))
    let controller = UIHostingController(rootView: content)
    controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
    controller.view.layoutIfNeeded()
    let root = controller.view!
    let frame = find("SwiftUI.Color", in: root).map { $0.convert($0.bounds, to: root) } ?? .zero
    let target = find(id, in: root)
    return (controller, frame, target)
}

@MainActor func frameOf(_ view: UIView?, in root: UIView) -> CGRect {
    guard let view else { return .null }
    return view.convert(view.bounds, to: root)
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    var bitmaps: [(String, (UIView) -> Bitmap)] = []
    for backend in [RenderBackend.quartz, .swift] {
        bitmaps.append(("renderPass/\(backend)", { view in
            CanvasBackendSelection.current = backend
            return render(view, .renderPass)
        }))
    }
    bitmaps.append(("layers/quartz", { view in
        CanvasBackendSelection.current = .quartz
        return render(view, .layers)
    }))

    // 1. Circle().stroke(color, 4): straddles the outline (radius 18-22).
    do {
        let (c, f, v) = host(Circle().stroke(Color.red, lineWidth: 4), id: "SwiftUI.Capsule.stroke")
        withExtendedLifetime(c) {
            let root = c.view!
            check(f.width == 40, "circle stroke: base frame found \(f)")
            check(near(frameOf(v, in: root), f.insetBy(dx: -2, dy: -2)),
                  "circle stroke: view is the frame grown by half the line \(frameOf(v, in: root))")
            check(v?.layer.cornerRadius == 22, "circle stroke: outer radius r + w/2")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isRed(pixel(b, f.midX, f.minY - 1.5)), "\(tag) circle stroke paints outside the frame (top)")
                check(isRed(pixel(b, f.midX, f.minY + 1.0)), "\(tag) circle stroke paints inside the frame (top)")
                check(isRed(pixel(b, f.maxX + 1.0, f.midY)), "\(tag) circle stroke paints outside the frame (right)")
                check(isBackground(pixel(b, f.midX, f.minY - 2.5)), "\(tag) circle stroke ends 2 pt outside")
                check(isBackground(pixel(b, f.midX, f.minY + 2.5)), "\(tag) circle stroke ends 2 pt inside")
                check(isBackground(pixel(b, f.midX, f.midY)), "\(tag) circle stroke leaves the centre")
            }
        }
    }

    // 2. Circle().strokeBorder(color, 4): inside the frame (radius 16-20).
    do {
        let (c, f, v) = host(Circle().strokeBorder(Color.red, lineWidth: 4), id: "SwiftUI.Capsule.stroke")
        withExtendedLifetime(c) {
            let root = c.view!
            check(near(frameOf(v, in: root), f), "circle strokeBorder: view keeps the frame")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isRed(pixel(b, f.midX, f.minY)), "\(tag) strokeBorder paints the frame's edge")
                check(isRed(pixel(b, f.midX, f.minY + 3.0)), "\(tag) strokeBorder paints 4 pt in")
                check(isBackground(pixel(b, f.midX, f.minY - 0.5)), "\(tag) strokeBorder paints nothing outside")
                check(isBackground(pixel(b, f.midX, f.minY + 4.5)), "\(tag) strokeBorder ends 4 pt in")
            }
        }
    }

    // 3. RoundedRectangle(cornerRadius: 10).stroke(color, 4) and Rectangle().stroke.
    do {
        let (c, f, v) = host(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 4),
                             id: "SwiftUI.RoundedRectangle.stroke")
        withExtendedLifetime(c) {
            let root = c.view!
            check(near(frameOf(v, in: root), f.insetBy(dx: -2, dy: -2)),
                  "rounded rect stroke: view is the frame grown by half the line")
            check(v?.layer.cornerRadius == 12, "rounded rect stroke: outer radius r + w/2")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isRed(pixel(b, f.midX, f.maxY + 1.0)), "\(tag) rounded rect stroke paints outside (bottom)")
                check(isRed(pixel(b, f.minX - 1.5, f.midY)), "\(tag) rounded rect stroke paints outside (left)")
                check(isBackground(pixel(b, f.minX - 1.5, f.minY - 1.5)), "\(tag) rounded rect stroke's outer corner is round")
                check(isBackground(pixel(b, f.midX, f.midY)), "\(tag) rounded rect stroke leaves the centre")
            }
        }
        let (rc, rf, rv) = host(Rectangle().stroke(Color.red, lineWidth: 4),
                                id: "SwiftUI.RoundedRectangle.stroke")
        withExtendedLifetime(rc) {
            let root = rc.view!
            check(near(frameOf(rv, in: root), rf.insetBy(dx: -2, dy: -2)) && rv?.layer.cornerRadius == 0,
                  "rectangle stroke: grown frame, square corners")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isRed(pixel(b, rf.minX - 2, rf.minY - 2)), "\(tag) rectangle stroke has a mitred outer corner")
                check(isBackground(pixel(b, rf.minX + 2.5, rf.minY + 2.5)), "\(tag) rectangle stroke's inner corner is square")
            }
        }
    }

    // 4. A gradient stroke paints both halves; its unit points stay on F.
    do {
        let gradient = LinearGradient(colors: [.purple, .pink, .orange],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        let (c, f, v) = host(Circle().stroke(gradient, lineWidth: 4), id: "SwiftUI.LinearGradient")
        withExtendedLifetime(c) {
            let root = c.view!
            let g = v as? UIGradientView
            check(near(frameOf(v, in: root), f.insetBy(dx: -2, dy: -2)),
                  "gradient stroke: gradient drawn over the grown frame")
            check(g.map { near($0.startPoint, CGPoint(x: 2.0 / 44, y: 2.0 / 44))
                          && near($0.endPoint, CGPoint(x: 42.0 / 44, y: 42.0 / 44)) } == true,
                  "gradient stroke: unit points relative to the shape's frame")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isInk(pixel(b, f.midX, f.minY - 1.5)), "\(tag) gradient stroke paints outside the frame: \(pixel(b, f.midX, f.minY - 1.5))")
                check(isInk(pixel(b, f.midX, f.minY + 1.0)), "\(tag) gradient stroke paints inside the frame")
                check(isBackground(pixel(b, f.midX, f.minY - 2.5)), "\(tag) gradient stroke ends 2 pt outside")
                check(isBackground(pixel(b, f.midX, f.midY)), "\(tag) gradient stroke leaves the centre")
            }
        }
        let (bc, bf, bv) = host(Circle().strokeBorder(gradient, lineWidth: 4), id: "SwiftUI.LinearGradient")
        withExtendedLifetime(bc) {
            let root = bc.view!
            check(near(frameOf(bv, in: root), bf), "gradient strokeBorder: gradient keeps the frame")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isInk(pixel(b, bf.midX, bf.minY + 3.0)), "\(tag) gradient strokeBorder paints 4 pt in")
                check(isBackground(pixel(b, bf.midX, bf.minY - 0.5)), "\(tag) gradient strokeBorder paints nothing outside")
            }
        }
    }

    // 5. StrokeStyle arcs (trim) are centred too: the lower half, 0 → 0.5.
    do {
        let (c, f, v) = host(
            Circle().trim(from: 0, to: 0.5).stroke(Color.red, style: StrokeStyle(lineWidth: 4)),
            id: "SwiftUI.Circle.trim.stroke")
        withExtendedLifetime(c) {
            let root = c.view!
            check(near(frameOf(v, in: root), f.insetBy(dx: -2, dy: -2)),
                  "trimmed stroke: view is the frame grown by half the line")
            for (tag, draw) in bitmaps {
                let b = draw(root)
                check(isRed(pixel(b, f.midX, f.maxY + 1.0)), "\(tag) trimmed stroke paints outside (bottom)")
                check(isRed(pixel(b, f.midX, f.maxY - 1.5)), "\(tag) trimmed stroke paints inside (bottom)")
                check(isBackground(pixel(b, f.midX, f.maxY + 2.5)), "\(tag) trimmed stroke ends 2 pt outside")
                check(isBackground(pixel(b, f.midX, f.minY - 1.0)), "\(tag) trimmed stroke leaves the other half")
            }
        }
        let (sc, sf, sv) = host(
            Circle().trim(from: 0, to: 0.25).stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .square)),
            id: "SwiftUI.Circle.trim.stroke")
        withExtendedLifetime(sc) {
            let o = 2 * 2.squareRoot()
            check(near(frameOf(sv, in: sc.view!), sf.insetBy(dx: -o, dy: -o)),
                  "square-capped trimmed stroke: grown by the cap's corner")
        }
    }

    // 6. A stroke overlaid on a clipped view is not clipped by it.
    do {
        let (c, f, _) = host(Circle().stroke(Color.red, lineWidth: 4), base: .blue, clipBase: true,
                             id: "SwiftUI.Capsule.stroke")
        withExtendedLifetime(c) {
            for (tag, draw) in bitmaps {
                let b = draw(c.view!)
                check(isRed(pixel(b, f.midX, f.minY - 1.5)), "\(tag) overlay stroke over clipShape is not clipped")
            }
        }
    }

    // 7. A gradient stroke built as a mask (stupid social's story ring):
    //    the ring's outer half survives the mask in both compositors.
    do {
        let ring = Circle().stroke(Color.clear, lineWidth: 0).overlay {
            Circle().stroke(LinearGradient(colors: [.purple, .pink, .orange],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3)
        }
        let (c, f, _) = host(ring, base: .blue, clipBase: true, id: "SwiftUI.Mask")
        withExtendedLifetime(c) {
            for (tag, draw) in bitmaps {
                let b = draw(c.view!)
                check(isInk(pixel(b, f.midX, f.minY - 1.0)), "\(tag) story ring paints 1-1.5 pt outside the photo")
                check(isInk(pixel(b, f.midX, f.minY + 0.5)), "\(tag) story ring paints 0.5-1 pt inside the photo")
                check(isBackground(pixel(b, f.midX, f.minY - 2.0)), "\(tag) story ring ends 1.5 pt outside")
            }
        }
    }
}

/// The other two items of the same parity pass: the `badge-plus` open
/// symbol composite and the iOS 27 glass platter rim.
@MainActor func chromeChecks() {
    // 8. person.fill.badge.plus: the disc overlaps the figure's lower right,
    //    the plus is cut out of it, the figure is knocked out around it.
    OpenUIKitRuntime.openSymbolFallback = true
    for backend in [RenderBackend.quartz, .swift] {
        CanvasBackendSelection.current = backend
        let bitmap = Bitmap(width: 120, height: 120)
        let canvas = Canvas(bitmap: bitmap, scale: 2)
        let bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        let name = "person.fill.badge.plus"
        let red = CanvasColor(red: 1, green: 0, blue: 0, alpha: 1)
        check(OpenSymbols.draw(name: name, in: canvas, bounds: bounds, color: red), "badge: draws")
        guard let b = canvas.makeImage(),
              let k = OpenSymbols.knockout(name: name, in: bounds) else {
            check(false, "badge: knockout geometry"); continue
        }
        let m = OpenSymbols.badgePlusGeometry
        let unit = k.circle.width / 2 / m.knockoutRadius
        func at(_ x: CGFloat, _ y: CGFloat) -> [UInt8] {
            pixel(b, k.circle.midX + (x - m.disc.x) * unit - 0.25,
                  k.circle.midY + (y - m.disc.y) * unit - 0.25)
        }
        let ink: ([UInt8]) -> Bool = { $0[3] > 200 }
        let none: ([UInt8]) -> Bool = { $0[3] < 40 }
        let tag = "badge/\(backend)"
        check(k.pathCount == 2, "\(tag): the figure (head and body) is knocked out")
        check(ink(at(0.379, 0.2)), "\(tag): the head is drawn")
        check(none(at(m.disc.x, m.disc.y)), "\(tag): the plus is cut out of the disc")
        check(ink(at(m.disc.x + 0.12, m.disc.y + 0.12)), "\(tag): the disc is drawn between the arms")
        check(none(at(m.disc.x - (m.discRadius + m.knockoutRadius) / 2, m.disc.y)),
              "\(tag): the gap around the disc is knocked out of the body")
        check(ink(at(m.disc.x - m.knockoutRadius - 0.05, m.disc.y)), "\(tag): the body beyond the gap is drawn")
    }
    OpenUIKitRuntime.openSymbolFallback = false

    // 9. The iOS 27 platter rim: 0.5 pt outside the capsule, darkest at the ends.
    OpenUIKitRuntime.systemFontCut = .iOS
    CanvasBackendSelection.current = .quartz
    for release in [OpenUIKitChromeRelease.iOS26, .iOS27] {
        OpenUIKitRuntime.chromeRelease = release
        let platter = _UIBarSharedPlatterView(frame: CGRect(x: 0, y: 0, width: 108, height: 44))
        platter.setNeedsLayout()
        platter.layoutIfNeeded()
        let rim = platter.rim
        if release == .iOS26 {
            check(rim.isHidden, "rim: none on the iOS 26 chrome")
            check(platter.layer.shadowOpacity == _UIBarMetrics.shadowOpacity, "rim: iOS 26 shadow unchanged")
            continue
        }
        check(!rim.isHidden && rim.frame == platter.bounds.insetBy(dx: -0.5, dy: -0.5),
              "rim: shown around the iOS 27 platter, 0.5 pt outside it: \(rim.frame)")
        check(platter.layer.shadowOpacity == _UIBarMetrics.iOS27ShadowOpacity, "rim: iOS 27 shadow is lighter")
        let b = render(rim, .renderPass)
        let side = Int(pixel(b, 0, 21.75)[3]), flat = Int(pixel(b, 54, 0)[3])
        check(abs(side - 77) <= 6, "rim: 0.30 black at the capsule's ends: \(side)")
        check(abs(flat - 26) <= 4, "rim: 0.10 black along the flat edges: \(flat)")
        check(pixel(b, 54, 0.5)[3] == 0 && pixel(b, 54, 22)[3] == 0, "rim: 0.5 pt wide, nothing inside")
    }
    OpenUIKitRuntime.chromeRelease = .iOS26
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    chromeChecks()
    return Probe.failures
}
print(failures == 0 ? "STROKE_PROBE=PASS" : "STROKE_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
