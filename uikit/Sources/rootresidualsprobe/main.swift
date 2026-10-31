// Native gate for the root-screen residuals pass (docs/ROOT_SCREEN_RESIDUALS.md).
//
//   swift run rootresidualsprobe     exits 0 when every check passes
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

func writePNG(width: Int, height: Int, to path: String) {
    var bitmap = Bitmap(width: width, height: height)
    for i in 0..<(width * height) {
        bitmap.pixels[i * 4] = UInt8(i % 251)
        bitmap.pixels[i * 4 + 3] = 255
    }
    FileManager.default.createFile(atPath: path, contents: Data(ImageCodec.encodePNG(bitmap)!))
}

@MainActor func imageVariants() {
    let dir = NSTemporaryDirectory() + "rootresidualsprobe-\(UInt32.random(in: 0...UInt32.max))"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    // stupid social's badges: Badge.png 14x14, @2x 28x28, @3x 42x42.
    writePNG(width: 14, height: 14, to: dir + "/Badge.png")
    writePNG(width: 28, height: 28, to: dir + "/Badge@2x.png")
    writePNG(width: 42, height: 42, to: dir + "/Badge@3x.png")
    writePNG(width: 10, height: 10, to: dir + "/Solo.png")
    writePNG(width: 20, height: 20, to: dir + "/Only2x@2x.png")
    let saved = OpenUIKitRuntime.imageScreenScale
    defer { OpenUIKitRuntime.imageScreenScale = saved }

    for scale in [1, 2, 3] {
        OpenUIKitRuntime.imageScreenScale = CGFloat(scale)
        let image = UIImage(contentsOfFile: dir + "/Badge.png")
        check(image?.scale == CGFloat(scale) && image?.size == CGSize(width: 14, height: 14)
              && image?.bitmap.width == 14 * scale,
              "contentsOfFile on a \(scale)x screen loads the @\(scale)x variant: scale \(String(describing: image?.scale)) px \(String(describing: image?.bitmap.width))")
    }
    OpenUIKitRuntime.imageScreenScale = 3
    check(UIImage(contentsOfFile: dir + "/Badge@2x.png")?.scale == 2, "an explicit @2x path loads as named on a 3x screen")
    let solo = UIImage(contentsOfFile: dir + "/Solo.png")
    check(solo?.scale == 1 && solo?.size == CGSize(width: 10, height: 10), "no screen variant: the unmodified path at 1x")
    check(UIImage(contentsOfFile: dir + "/Only2x.png") == nil, "a missing path with only a non-screen variant is nil")
    check(UIImage(contentsOfFile: dir + "/Missing.png") == nil, "a missing path is nil")
    // UIImage(named:in:compatibleWith:) already picks the variant (loadNamed).
    OpenUIKitRuntime.imageSearchPaths = [dir]
    UIImage.clearNamedCache()
    check(UIImage.named("Badge")?.scale == 3, "named(_:) picks the 3x variant on a 3x screen")
    OpenUIKitRuntime.imageSearchPaths = []
    UIImage.clearNamedCache()
}

@MainActor func rgba(_ style: _OpenHierarchicalShapeStyle, _ ui: UIUserInterfaceStyle) -> [Int] {
    let c = UIColor(style._openResolvedForegroundColor()).resolvedColor(with: UITraitCollection(userInterfaceStyle: ui))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    _ = c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a].map { Int(($0 * 255).rounded()) }
}

@MainActor func hierarchicalStyles() {
    let saved = OpenUIKitRuntime.chromeRelease
    defer { OpenUIKitRuntime.chromeRelease = saved }
    func uikit(_ color: UIColor, _ ui: UIUserInterfaceStyle) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: ui)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }
    OpenUIKitRuntime.chromeRelease = .iOS26
    check(rgba(.secondary, .light) == uikit(.secondaryLabel, .light), "iOS 26: .secondary is secondaryLabel")
    check(rgba(.tertiary, .light) == uikit(.tertiaryLabel, .light), "iOS 26: .tertiary is tertiaryLabel")
    OpenUIKitRuntime.chromeRelease = .iOS27
    check(rgba(.secondary, .light) == [0, 0, 0, 128], "iOS 27: .secondary is black at 0.5: \(rgba(.secondary, .light))")
    check(rgba(.tertiary, .light) == [0, 0, 0, 64], "iOS 27: .tertiary is black at 0.25: \(rgba(.tertiary, .light))")
    check(rgba(.primary, .light) == uikit(.label, .light), "iOS 27: .primary is label")
    check(rgba(.quaternary, .light) == uikit(.quaternaryLabel, .light), "iOS 27: .quaternary unchanged (unmeasured)")
    check(rgba(.secondary, .dark) == uikit(.secondaryLabel, .dark), "iOS 27 dark: .secondary unchanged (unmeasured)")
}

// Compile-time check: ShapeStyle statics are usable from nonisolated code
// (the generic spelling `.foregroundStyle(.white)` takes), and `.secondary`
// through a generic ShapeStyle is the hierarchical style, not Color.secondary.
nonisolated func pickStyle<S: ShapeStyle>(_ style: S) -> S { style }
nonisolated func nonisolatedWhite() -> Color { pickStyle(.white) }
nonisolated func nonisolatedSecondary() -> _OpenHierarchicalShapeStyle { pickStyle(.secondary) }

@MainActor func shapeStyleStatics() {
    check(nonisolatedWhite() == Color.white, "nonisolated generic .white is Color.white")
    check(nonisolatedSecondary().level == .secondary, "generic .secondary is the hierarchical secondary")
}

let failures = MainActor.assumeIsolated { () -> Int in
    shapeStyleStatics()
    imageVariants()
    hierarchicalStyles()
    return Probe.failures
}
print(failures == 0 ? "ROOT_RESIDUALS_PROBE=PASS" : "ROOT_RESIDUALS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
