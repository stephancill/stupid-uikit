// Text.bold() / Font.bold() add the bold trait, which on iOS is semibold for
// most fonts (MEASURED iOS 27.0 simulator; _OpenFont.boldTraitWeight).

import XCTest
#if os(Linux)
@preconcurrency @testable import SwiftUI
@preconcurrency @testable import OpenUIKit
#else
@testable import SwiftUI
@testable import OpenUIKit
#endif

@MainActor
final class BoldTraitTests: XCTestCase {
    private var savedCut = OpenUIKitRuntime.systemFontCut

    override func setUp() {
        savedCut = OpenUIKitRuntime.systemFontCut
    }

    override func tearDown() {
        OpenUIKitRuntime.systemFontCut = savedCut
    }

    func testBoldTraitOnIOS() {
        OpenUIKitRuntime.systemFontCut = .iOS
        XCTAssertEqual(Font.body.resolve(weight: .boldTrait).weight, .semibold)
        XCTAssertEqual(Font.caption.resolve(weight: .boldTrait).weight, .semibold)
        XCTAssertEqual(Font.headline.resolve(weight: .boldTrait).weight, .semibold)
        XCTAssertEqual(Font.title3.resolve(weight: .boldTrait).weight, .semibold)
        XCTAssertEqual(Font.title2.resolve(weight: .boldTrait).weight, .bold)
        XCTAssertEqual(Font.largeTitle.resolve(weight: .boldTrait).weight, .bold)
        XCTAssertEqual(Font.system(size: 17).resolve(weight: .boldTrait).weight, .semibold)
        XCTAssertEqual(Font.system(size: 17, weight: .medium).resolve(weight: .boldTrait).weight, .medium)
        XCTAssertEqual(Font.body.bold().resolve(weight: nil).weight, .semibold)
        XCTAssertEqual(Font.title.bold().resolve(weight: nil).weight, .bold)
        // The bold weight stays bold.
        XCTAssertEqual(Font.body.resolve(weight: .bold).weight, .bold)
        XCTAssertEqual(Font.body.weight(.bold).resolve(weight: nil).weight, .bold)
    }

    func testBoldTraitOnMacOSCutIsBold() {
        OpenUIKitRuntime.systemFontCut = .macOS
        XCTAssertEqual(Font.body.resolve(weight: .boldTrait).weight, .bold)
        XCTAssertEqual(Font.body.bold().resolve(weight: nil).weight, .bold)
    }
}
