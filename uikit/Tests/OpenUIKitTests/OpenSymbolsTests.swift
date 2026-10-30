import XCTest
@testable import OpenUIKit

/// SVG path-data parser and the opt-in open-symbol fallback (Phosphor
/// glyphs for mapped SF Symbol names). The fallback is off by default, so
/// every fail-closed system-image test elsewhere is unaffected.
#if !os(Linux)
@MainActor
#endif
final class OpenSymbolsTests: XCTestCase {
    private var savedFallback = false
    private var savedScale: CGFloat = 2
    private var savedCut: FontEngine.SystemFontCut = .macOS

    override func setUp() {
        super.setUp()
        savedFallback = OpenUIKitRuntime.openSymbolFallback
        savedScale = OpenUIKitRuntime.imageScreenScale
        savedCut = OpenUIKitRuntime.systemFontCut
    }

    override func tearDown() {
        OpenUIKitRuntime.openSymbolFallback = savedFallback
        OpenUIKitRuntime.imageScreenScale = savedScale
        OpenUIKitRuntime.systemFontCut = savedCut
        super.tearDown()
    }

    // MARK: SVG path data

    private func points(_ path: Path) -> [String] {
        func f(_ p: CGPoint) -> String {
            func r(_ v: CGFloat) -> String {
                let rounded = (v * 1000).rounded() / 1000
                return rounded == 0 ? "0" : "\(Double(rounded))"
            }
            return r(p.x) + "," + r(p.y)
        }
        return path.elements.map { element in
            switch element {
            case .move(let p): return "M" + f(p)
            case .line(let p): return "L" + f(p)
            case .quad(let c, let p): return "Q" + f(c) + " " + f(p)
            case .cubic(let c1, let c2, let p): return "C" + f(c1) + " " + f(c2) + " " + f(p)
            case .close: return "Z"
            }
        }
    }

    func testLinesAbsoluteRelativeAndImplicitRepeats() throws {
        let path = try SVGPathData.parse("M10,20 30,40 l5-5 H50 h-10 V0 v10 Z m1 1 L2 2 z")
        XCTAssertEqual(points(path), [
            "M10.0,20.0", "L30.0,40.0", "L35.0,35.0", "L50.0,35.0", "L40.0,35.0",
            "L40.0,0", "L40.0,10.0", "Z", "M11.0,21.0", "L2.0,2.0", "Z",
        ])
    }

    func testCompactNumbersAndExponents() throws {
        let path = try SVGPathData.parse("M.5.5L-1-2l1e1,2.5E-1")
        XCTAssertEqual(points(path), ["M0.5,0.5", "L-1.0,-2.0", "L9.0,-1.75"])
    }

    func testCubicSmoothReflectsPreviousControl() throws {
        let path = try SVGPathData.parse("M0 0C0 10 10 10 10 0S20 -10 20 0s10 10 10 0")
        XCTAssertEqual(points(path), [
            "M0,0",
            "C0,10.0 10.0,10.0 10.0,0",
            "C10.0,-10.0 20.0,-10.0 20.0,0",
            "C20.0,10.0 30.0,10.0 30.0,0",
        ])
        // S without a preceding cubic uses the current point.
        let lone = try SVGPathData.parse("M5 5S10 10 15 5")
        XCTAssertEqual(points(lone), ["M5.0,5.0", "C5.0,5.0 10.0,10.0 15.0,5.0"])
    }

    func testQuadraticSmoothReflectsPreviousControl() throws {
        let path = try SVGPathData.parse("M0 0Q5 10 10 0T20 0t10 0")
        XCTAssertEqual(points(path), [
            "M0,0", "Q5.0,10.0 10.0,0", "Q15.0,-10.0 20.0,0", "Q25.0,10.0 30.0,0",
        ])
    }

    func testArcsBecomeCubicsThatLandOnTheCircle() throws {
        // Half circle radius 10 centred (10, 0), sweep from (0,0) to (20,0).
        let path = try SVGPathData.parse("M0 0A10 10 0 0 1 20 0")
        XCTAssertEqual(path.elements.count, 3) // move + two ≤90° cubics
        guard case .cubic(_, _, let mid) = path.elements[1],
              case .cubic(_, _, let end) = path.elements[2] else {
            return XCTFail("expected cubics")
        }
        XCTAssertEqual(mid.x, 10, accuracy: 1e-9)
        XCTAssertEqual(abs(mid.y), 10, accuracy: 1e-9)
        XCTAssertEqual(end.x, 20, accuracy: 1e-12)
        XCTAssertEqual(end.y, 0, accuracy: 1e-12)
        // Positive sweep in SVG's y-down space passes through y = -10.
        XCTAssertEqual(mid.y, -10, accuracy: 1e-9)

        // Compact flags and relative endpoint; an undersized radius is
        // scaled up (F.6.6) so the arc still reaches the endpoint.
        let compact = try SVGPathData.parse("M0 0a1 1 0 018 0")
        guard case .cubic(_, _, let last) = compact.elements.last! else {
            return XCTFail("expected a cubic")
        }
        XCTAssertEqual(last.x, 8, accuracy: 1e-12)
        XCTAssertEqual(last.y, 0, accuracy: 1e-12)

        // Zero radius is a straight line.
        XCTAssertEqual(points(try SVGPathData.parse("M0 0A0 5 0 0 1 4 4")), ["M0,0", "L4.0,4.0"])
    }

    func testMalformedDataThrows() {
        XCTAssertThrowsError(try SVGPathData.parse("L1 1")) { error in
            XCTAssertEqual(error as? SVGPathDataError, .missingInitialMoveTo)
        }
        XCTAssertThrowsError(try SVGPathData.parse("M1 1 X")) { error in
            XCTAssertEqual(error as? SVGPathDataError, .unexpectedCharacter(offset: 5))
        }
        XCTAssertThrowsError(try SVGPathData.parse("M1")) { error in
            XCTAssertEqual(error as? SVGPathDataError, .expectedNumber(offset: 2))
        }
        XCTAssertThrowsError(try SVGPathData.parse("M0 0A1 1 0 2 1 3 3")) { error in
            XCTAssertEqual(error as? SVGPathDataError, .expectedFlag(offset: 11))
        }
    }

    // MARK: Catalog

    func testEveryMappedGlyphParsesInsideTheViewBox() {
        XCTAssertGreaterThan(OpenSymbols.mappedNames.count, 400)
        for name in OpenSymbols.mappedNames {
            guard let glyph = OpenSymbols.glyph(for: name) else {
                XCTFail("\(name) has no glyph")
                continue
            }
            XCTAssertFalse(glyph.paths.isEmpty, name)
            let b = glyph.bounds
            XCTAssertGreaterThan(b.width, 8, name)
            XCTAssertGreaterThan(b.height, 8, name)
            XCTAssertGreaterThanOrEqual(b.minX, -0.5, name)
            XCTAssertGreaterThanOrEqual(b.minY, -0.5, name)
            XCTAssertLessThanOrEqual(b.maxX, 256.5, name)
            XCTAssertLessThanOrEqual(b.maxY, 256.5, name)
        }
    }

    func testStupidSocialSymbolsAreMapped() {
        let names = [
            "alarm", "alarm.fill", "archivebox", "archivebox.fill", "arrow.clockwise",
            "arrow.up.circle.fill", "arrow.up.forward.app", "arrow.up.forward.square",
            "arrow.up.right.square", "arrowshape.turn.up.left", "arrowshape.turn.up.left.fill",
            "at", "bell", "bell.fill", "bell.slash", "bookmark.fill",
            "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill",
            "bubble.left.and.text.bubble.right", "calendar", "camera", "checkmark",
            "checkmark.circle", "checkmark.seal.fill", "chevron.down", "chevron.forward",
            "chevron.left.forwardslash.chevron.right", "chevron.right", "chevron.up", "clock",
            "doc", "doc.fill", "doc.on.doc", "ellipsis", "exclamationmark",
            "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
            "exclamationmark.circle.fill", "exclamationmark.triangle", "face.smiling", "folder",
            "folder.badge.plus", "gear", "heart", "heart.fill", "key",
            "keyboard.chevron.compact.down", "line.3.horizontal.decrease", "link", "location",
            "lock", "magnifyingglass", "mappin.and.ellipse", "message", "message.fill",
            "music.note", "paperclip", "paperplane", "pause.fill", "person.2",
            "person.badge.plus", "person.crop.circle", "person.crop.circle.badge.questionmark",
            "person.crop.circle.badge.xmark", "person.fill", "person.fill.badge.plus", "photo",
            "photo.on.rectangle", "photo.on.rectangle.angled", "play.fill", "play.rectangle",
            "plus", "plus.circle.fill", "safari", "speaker.slash.fill", "speaker.wave.2.fill",
            "square.and.arrow.down", "square.on.square", "star.fill", "text.bubble",
            "textformat", "trash", "trash.fill", "video", "xmark", "xmark.circle.fill",
        ]
        for name in names {
            XCTAssertTrue(OpenSymbols.isMapped(name), name)
        }
        // Focus onboarding's numbered symbols stay unmapped (blank render pinned).
        for name in ["1.circle.fill", "2.circle.fill", "3.circle.fill"] {
            XCTAssertFalse(OpenSymbols.isMapped(name), name)
        }
    }

    // MARK: Layout

    func testApproximateLayoutKeepsPhosphorOpticalSize() throws {
        // Phosphor's circle (208 units) is SF's 17 pt circle ink at 17 pt.
        let glyph = try XCTUnwrap(OpenSymbols.glyph(for: "circle"))
        XCTAssertEqual(glyph.bounds.width, 208, accuracy: 0.5)
        let layout = try XCTUnwrap(OpenSymbols.layout(name: "heart.circle", pointSize: 34))
        XCTAssertEqual(layout.ink.width, 34, accuracy: 0.1)
        XCTAssertEqual(layout.size.width, 34 + 8, accuracy: 0.1)
        XCTAssertEqual(layout.size.height, 34 + 4, accuracy: 0.1)
        XCTAssertNil(OpenSymbols.layout(name: "not.a.symbol", pointSize: 17))
        XCTAssertNil(OpenSymbols.layout(name: "heart", pointSize: .nan))
    }

    // MARK: UIImage(systemName:)

    private func alpha(_ image: UIImage) -> [UInt8] {
        stride(from: 3, to: image.bitmap.pixels.count, by: 4).map { image.bitmap.pixels[$0] }
    }

    func testFallbackIsOffByDefaultAndOnlyServesMappedNames() throws {
        OpenUIKitRuntime.imageScreenScale = 2
        OpenUIKitRuntime.openSymbolFallback = false
        XCTAssertNil(UIImage(systemName: "heart.fill"))
        XCTAssertNil(UIImage(systemName: "airplane"))

        OpenUIKitRuntime.openSymbolFallback = true
        let heart = try XCTUnwrap(UIImage(systemName: "heart.fill"))
        XCTAssertTrue(heart.isSymbolImage)
        let a = alpha(heart)
        XCTAssertTrue(a.contains { $0 > 200 }, "heart.fill has no solid ink")
        XCTAssertTrue(a.contains(0), "heart.fill lost its transparent field")
        XCTAssertNil(UIImage(systemName: "not.a.symbol"))
        XCTAssertNil(UIImage(systemName: "1.circle.fill"))
        XCTAssertNil(UIImage(systemName: "Heart"))
    }

    func testFallbackLeavesProceduralSymbolsByteIdentical() throws {
        OpenUIKitRuntime.imageScreenScale = 2
        for name in ["calendar", "clock", "clock.fill", "multiply", "plus.circle.fill",
                     "circlebadge", "checkmark.circle.fill"] {
            OpenUIKitRuntime.openSymbolFallback = false
            let off = try XCTUnwrap(UIImage(systemName: name))
            OpenUIKitRuntime.openSymbolFallback = true
            let on = try XCTUnwrap(UIImage(systemName: name))
            XCTAssertEqual(off.size, on.size, name)
            XCTAssertEqual(off.bitmap.pixels, on.bitmap.pixels, name)
        }
    }

    func testFallbackHonoursPointSizeAndSymbolScale() throws {
        OpenUIKitRuntime.imageScreenScale = 2
        OpenUIKitRuntime.openSymbolFallback = true
        let base = try XCTUnwrap(UIImage(systemName: "airplane"))
        let big = try XCTUnwrap(UIImage(systemName: "airplane", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)))
        XCTAssertEqual(big.size.width, base.size.width * 2, accuracy: 0.5)
        let large = try XCTUnwrap(UIImage(systemName: "airplane", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .large)))
        XCTAssertGreaterThan(large.size.height, base.size.height * 1.2)
    }
}
