// Native gate for shape masks (docs/SHAPE_MASKS.md): CAShapeLayer as a
// layer and as CALayer.mask in both compositors and both canvas backends,
// and SwiftUI `.mask { shape }`.
//
//   swift run swiftuishapemaskprobe     exits 0 when every check passes
//
// Drives UIKit and UIHostingController directly, as swiftuilazyprobe does.
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

/// Straight-alpha RGBA at a point (in points) of a bitmap rendered at `scale`.
func pixel(_ bitmap: Bitmap, _ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> [UInt8] {
    let px = Int(x * scale), py = Int(y * scale)
    let o = (py * bitmap.width + px) * 4
    return Array(bitmap.pixels[o..<o + 4])
}

func isRed(_ p: [UInt8]) -> Bool { p[3] == 255 && p[0] > 240 && p[1] < 16 && p[2] < 16 }
func isClear(_ p: [UInt8]) -> Bool { p[3] == 0 }
/// SwiftUI's `Color.red` is the system red, not (255, 0, 0).
func isOpaque(_ p: [UInt8]) -> Bool { p[3] == 255 }

enum Compositor: String, CaseIterable { case renderPass, layers }

@MainActor func render(_ view: UIView, _ compositor: Compositor, scale: CGFloat = 2) -> Bitmap {
    switch compositor {
    case .renderPass: return UIRenderer.renderPassRender(view, scale: scale)
    case .layers: return LayerBridge.render(view, scale: scale)
    }
}

@MainActor func circlePath(_ rect: CGRect) -> Path {
    UIBezierPath(ovalIn: rect).cgPath
}

@MainActor func redSquare(mask: CALayer) -> UIView {
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    view.backgroundColor = .red
    view.layer.mask = mask
    return view
}

@MainActor func uikitChecks(_ compositor: Compositor, backend: RenderBackend) {
    let tag = "\(compositor.rawValue)/\(backend)"
    // 1. Filled circle mask.
    let fill = CAShapeLayer()
    fill.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    fill.path = circlePath(CGRect(x: 0, y: 0, width: 40, height: 40))
    var b = render(redSquare(mask: fill), compositor)
    check(isRed(pixel(b, 20, 20, scale: 2)), "\(tag) filled circle mask keeps the centre")
    check(isClear(pixel(b, 1, 1, scale: 2)), "\(tag) filled circle mask clears the corner")

    // 2. Stroked circle (ring) mask: no fill, 4 pt stroke on r = 16.
    let ring = CAShapeLayer()
    ring.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    ring.path = circlePath(CGRect(x: 4, y: 4, width: 32, height: 32))
    ring.fillColor = nil
    ring.strokeColor = UIColor.black.cgColor
    ring.lineWidth = 4
    b = render(redSquare(mask: ring), compositor)
    check(isClear(pixel(b, 20, 20, scale: 2)), "\(tag) ring mask clears the centre")
    check(isRed(pixel(b, 20, 4.25, scale: 2)), "\(tag) ring mask keeps the ring (top)")
    check(isRed(pixel(b, 35.75, 20, scale: 2)), "\(tag) ring mask keeps the ring (right)")
    check(isClear(pixel(b, 20, 0.5, scale: 2)), "\(tag) ring mask clears outside the ring")

    // 3. Even-odd fill: outer square minus inner square.
    let frame = CAShapeLayer()
    frame.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    var path = Path.rect(CGRect(x: 0, y: 0, width: 40, height: 40))
    path.elements += Path.rect(CGRect(x: 10, y: 10, width: 20, height: 20)).elements
    frame.path = path
    frame.fillRule = .evenOdd
    b = render(redSquare(mask: frame), compositor)
    check(isClear(pixel(b, 20, 20, scale: 2)), "\(tag) even-odd mask clears the hole")
    check(isRed(pixel(b, 5, 5, scale: 2)), "\(tag) even-odd mask keeps the frame")

    // 4. Fill alpha scales the mask; the mask layer's offset moves it.
    let half = CAShapeLayer()
    half.frame = CGRect(x: 20, y: 0, width: 20, height: 40)
    half.path = Path.rect(CGRect(x: 0, y: 0, width: 20, height: 40))
    half.fillColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5).cgColor
    b = render(redSquare(mask: half), compositor)
    let a = Int(pixel(b, 30, 20, scale: 2)[3])
    check(abs(a - 128) <= 2, "\(tag) half-alpha fill masks to half alpha: \(a)")
    check(isClear(pixel(b, 10, 20, scale: 2)), "\(tag) offset mask leaves its left half clear")

    // 5. A CAShapeLayer sublayer draws its fill and stroke.
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let dot = CAShapeLayer()
    dot.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    dot.path = circlePath(CGRect(x: 10, y: 10, width: 20, height: 20))
    dot.fillColor = UIColor.red.cgColor
    host.layer.addSublayer(dot)
    b = render(host, compositor)
    check(isRed(pixel(b, 20, 20, scale: 2)), "\(tag) shape sublayer fills its path")
    check(isClear(pixel(b, 5, 5, scale: 2)), "\(tag) shape sublayer leaves the rest clear")
}

// SwiftUI content under test.
struct RingMask: View {
    var body: some View {
        // The mask sizes to its content's placed rect, so the frame goes
        // outside it (as stupid social's overlay ring does).
        Color.red
            .mask { Circle().stroke(Color.black, lineWidth: 3) }
            .frame(width: 70, height: 70)
    }
}

struct RoundedMask: View {
    var body: some View {
        // The mask sizes to its content's placed rect, so the frame goes
        // outside it (as stupid social's overlay ring does).
        Color.red
            .mask { RoundedRectangle(cornerRadius: 20).padding(10) }
            .frame(width: 70, height: 70)
    }
}

struct GradientRing: View {
    var body: some View {
        ZStack {
            // Implicit-member colours still pick the Color overload.
            Circle().stroke(.white, lineWidth: 2)
            Circle().stroke(
                LinearGradient(colors: [.purple, .pink, .orange],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 3)
        }
        .frame(width: 70, height: 70)
    }
}

struct TextMask: View {
    var body: some View {
        // The mask sizes to its content's placed rect, so the frame goes
        // outside it (as stupid social's overlay ring does).
        Color.red
            .mask { Text("x") }
            .frame(width: 70, height: 70)
    }
}

@MainActor func maskHost(_ root: some View) -> (UIHostingController<some View>, UIView?) {
    let host = UIHostingController(rootView: root)
    host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    host.view.layoutIfNeeded()
    func find(_ v: UIView) -> UIView? {
        if v.accessibilityIdentifier == "SwiftUI.Mask" { return v }
        for s in v.subviews { if let f = find(s) { return f } }
        return nil
    }
    return (host, find(host.view))
}

@MainActor func swiftUIChecks(_ compositor: Compositor) {
    let tag = "swiftui/\(compositor.rawValue)"
    let (ringHost, ring) = maskHost(RingMask())
    withExtendedLifetime(ringHost) {
        guard let ring else { return check(false, "\(tag) ring: no mask host") }
        check(ring.layer.mask?.sublayers?.isEmpty == false,
              "\(tag) stroked circle builds a shape mask tree")
        let b = render(ring, compositor)
        check(isClear(pixel(b, 35, 35, scale: 2)), "\(tag) ring clears the centre")
        check(isOpaque(pixel(b, 35, 1.5, scale: 2)), "\(tag) ring keeps the 3 pt band (top)")
        check(isOpaque(pixel(b, 68.5, 35, scale: 2)), "\(tag) ring keeps the 3 pt band (right)")
        check(isClear(pixel(b, 35, 5, scale: 2)), "\(tag) ring clears inside the band")
        check(isClear(pixel(b, 1, 1, scale: 2)), "\(tag) ring clears the corner")
    }
    let (roundedHost, rounded) = maskHost(RoundedMask())
    withExtendedLifetime(roundedHost) {
        guard let rounded else { return check(false, "\(tag) rounded: no mask host") }
        let b = render(rounded, compositor)
        check(isOpaque(pixel(b, 35, 35, scale: 2)), "\(tag) padded rounded rect keeps the centre")
        check(isClear(pixel(b, 5, 35, scale: 2)), "\(tag) padding is outside the mask")
        check(isClear(pixel(b, 11, 11, scale: 2)), "\(tag) rounded corner is outside the mask")
        check(isOpaque(pixel(b, 30, 11, scale: 2)), "\(tag) straight edge is inside the mask")
    }
    let (gradientHost, gradient) = maskHost(GradientRing())
    withExtendedLifetime(gradientHost) {
        guard let gradient else { return check(false, "\(tag) gradient stroke: no mask host") }
        let b = render(gradient, compositor)
        let band = pixel(b, 35, 1.5, scale: 2)
        check(isOpaque(band) && band[0] > band[1],
              "\(tag) gradient stroke draws the gradient on the band: \(band)")
        check(isClear(pixel(b, 35, 35, scale: 2)), "\(tag) gradient stroke clears the centre")
    }
    let (textHost, text) = maskHost(TextMask())
    withExtendedLifetime(textHost) {
        guard let text else { return check(false, "\(tag) text: no mask host") }
        let mask = text.layer.mask
        check(mask != nil && !(mask is CAShapeLayer) && mask?.sublayers?.isEmpty != false,
              "\(tag) non-shape mask content keeps the rectangular mask")
    }
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    for backend in [RenderBackend.quartz, .swift] {
        CanvasBackendSelection.current = backend
        uikitChecks(.renderPass, backend: backend)
    }
    CanvasBackendSelection.current = .quartz
    uikitChecks(.layers, backend: .quartz)
    swiftUIChecks(.renderPass)
    swiftUIChecks(.layers)
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "SHAPE_MASK_PROBE=PASS" : "SHAPE_MASK_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
