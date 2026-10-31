// Native gate for iOS navigation chrome parity (docs/SWIFTUI_NAV_CHROME.md).
//
//   swift run swiftuinavchromeprobe     exits 0 when every check passes
//
// SwiftUITests cannot host @MainActor XCTest methods on Linux (see
// Tests/SwiftUITests/SwiftUILinuxStub.swift), so this executable drives
// UIHostingController directly, as swiftuilazyprobe does (debug build:
// `@testable` reads the bar's item views).
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

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

struct TitledStack: View {
    let mode: NavigationBarTitleDisplayMode

    var body: some View {
        NavigationStack {
            Text("Root")
                .navigationTitle("Social")
                .navigationBarTitleDisplayMode(mode)
        }
    }
}

struct UntitledStack: View {
    var body: some View {
        NavigationStack { Text("Root") }
    }
}

struct GroupedToolbarStack: View {
    var body: some View {
        NavigationStack {
            Text("Root")
                .navigationTitle("Social")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {} label: { Image(systemName: "magnifyingglass") }
                        Button {} label: { Image(systemName: "gear") }
                    }
                }
        }
    }
}

struct SeparatedToolbarStack: View {
    var body: some View {
        NavigationStack {
            Text("Root")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {} label: { Image(systemName: "magnifyingglass") }
                    }
                    ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {} label: { Image(systemName: "gear") }
                    }
                }
        }
    }
}

@MainActor func navigation(_ host: UIViewController) -> UINavigationController? {
    host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    host.view.layoutIfNeeded()
    guard let navigation = host.children.compactMap({ $0 as? UINavigationController }).first else {
        return nil
    }
    navigation.view.layoutIfNeeded()
    navigation.navigationBar.layoutIfNeeded()
    return navigation
}

@MainActor func prefersLarge(_ root: some View) -> Bool? {
    let host = UIHostingController(rootView: root)
    return withExtendedLifetime(host) { navigation(host)?.navigationBar.prefersLargeTitles }
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS

    // 1. Title display modes: `.automatic` at a stack's root is large on iOS.
    check(prefersLarge(TitledStack(mode: .automatic)) == true, "automatic root title is large")
    check(prefersLarge(TitledStack(mode: .large)) == true, "large title is large")
    check(prefersLarge(TitledStack(mode: .inline)) == false, "inline title stays inline")
    check(prefersLarge(UntitledStack()) == false, "untitled root keeps the inline bar")
    OpenUIKitRuntime.systemFontCut = .macOS
    check(prefersLarge(TitledStack(mode: .automatic)) == false, "macOS cut keeps large titles opt-in")
    OpenUIKitRuntime.systemFontCut = .iOS

    // 2. ToolbarItemGroup: two bar items on one shared platter.
    let grouped = UIHostingController(rootView: GroupedToolbarStack())
    if let nav = navigation(grouped), let items = nav.topViewController?.navigationItem.rightBarButtonItems {
        check(items.count == 2, "group is two bar items: \(items.count)")
        check(items.count == 2 && items[1].systemItem == .search, "first declared item (search) is leading")
        check(items.allSatisfy { $0._sharesSwiftUISymbolPlatter && !$0._isolatesPlatter }, "group items share a platter")
        let views = nav.navigationBar.rightItemViews.map(\.frame)
        check(views.count == 2 && views.allSatisfy { near($0.width, 50) }, "50 pt item views: \(views)")
        check(views.count == 2 && near(views[0].maxX, 390 - 16) && near(views[0].minX - views[1].maxX, 8),
              "trailing margin 16, gap 8: \(views)")
        let platters = nav.navigationBar.sharedPlatterViews.map(\.frame)
        check(platters.count == 1 && near(platters[0].width, 108) && near(platters[0].height, 44),
              "one 108 x 44 shared platter: \(platters)")
        // Large title layout (UIKit's iOS 26 numbers): bar at the safe-area
        // top, 54 pt content row plus the 52 pt large-title zone.
        check(near(nav.navigationBar.frame.height, 106), "large-title bar height: \(nav.navigationBar.frame)")
    } else {
        check(false, "grouped toolbar installed no trailing items")
    }

    // 2b. iOS 27 chrome: the magnifier is a symbol image item like the gear,
    //     each grouped item is a UIKit image item (image + 2 x 11), the rim
    //     lies 0.5 pt outside the shared platter (docs/ROOT_SCREEN_RESIDUALS.md).
    OpenUIKitRuntime.chromeRelease = .iOS27
    let grouped27 = UIHostingController(rootView: GroupedToolbarStack())
    if let nav = navigation(grouped27), let items = nav.topViewController?.navigationItem.rightBarButtonItems {
        check(items.count == 2 && items.allSatisfy { $0.image?.isSymbolImage == true && $0._sharesSwiftUISymbolPlatter },
              "iOS 27: both group items are symbol image items")
        let views = nav.navigationBar.rightItemViews
        let widths = views.map { $0.frame.width }
        let expected = views.map { max(22, $0.contentSize.width) + 22 }
        check(views.count == 2 && zip(widths, expected).allSatisfy { near($0, $1) },
              "iOS 27: item width is image + 22: \(widths) vs \(expected)")
        check(views.count == 2 && near(views[0].frame.maxX, 390 - 16) && near(views[0].frame.minX - views[1].frame.maxX, 8),
              "iOS 27: trailing margin 16, gap 8")
        let platters = nav.navigationBar.sharedPlatterViews
        check(platters.count == 1 && near(platters[0].frame.width, widths.reduce(8, +)),
              "iOS 27: platter spans the items: \(platters.map(\.frame))")
        check(platters.count == 1 && platters[0].rim.frame == platters[0].bounds.insetBy(dx: -0.5, dy: -0.5)
              && !platters[0].rim.isHidden, "iOS 27: rim 0.5 pt outside the platter")
    } else {
        check(false, "iOS 27 grouped toolbar installed no trailing items")
    }
    OpenUIKitRuntime.chromeRelease = .iOS26

    // 3. A ToolbarSpacer separates runs: two isolated 44 pt platters.
    let separated = UIHostingController(rootView: SeparatedToolbarStack())
    if let nav = navigation(separated), let items = nav.topViewController?.navigationItem.rightBarButtonItems {
        check(items.count == 2 && items.allSatisfy { !$0._sharesSwiftUISymbolPlatter },
              "spacer-separated items keep their own platters")
        check(nav.navigationBar.sharedPlatterViews.allSatisfy { $0.isHidden || $0.frame == .zero }
              || nav.navigationBar.sharedPlatterViews.isEmpty, "no shared platter across a spacer")
    } else {
        check(false, "separated toolbar installed no trailing items")
    }

    // 4. Device model: scene windows take its safe area; the status bar
    //    overlay covers the top inset as the topmost subview.
    check(UIWindow(windowScene: UIWindowScene()).safeAreaInsets == .zero, "no device: zero window safe area")
    OpenUIKitRuntime.configureDevice(.iPhone16e)
    check(UIScreen.main.bounds.size == CGSize(width: 390, height: 844), "iPhone 16e screen")
    let window = UIWindow(windowScene: UIWindowScene())
    check(window.safeAreaInsets == UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
          "iPhone 16e window safe area: \(window.safeAreaInsets)")
    check(OpenUIKitDeviceModel.named("iPhone16e") == .iPhone16e, "device lookup is case-insensitive")
    let bar = window._installScreenshotStatusBar(time: "09:41")
    check(bar.frame == CGRect(x: 0, y: 0, width: 390, height: 47), "status bar covers the top inset: \(bar.frame)")
    check(window.subviews.last === bar, "status bar is topmost")
    check(window._installScreenshotStatusBar() === bar, "installing again reuses the bar")

    withExtendedLifetime((grouped, grouped27, separated, window)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "NAV_CHROME_PROBE=PASS" : "NAV_CHROME_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
