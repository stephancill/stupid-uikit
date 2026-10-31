// Native gate: a SwiftUI List under a large-title NavigationStack rests below
// the bar when the app is driven only by plain host turns (tick + layout, no
// automation session), keeps a position the user scrolled to across hosting
// rebuilds, and does not keep an offset the scroll view set itself.
//
//   swift run swiftuilistrestprobe     exits 0 when every check passes
//
// Regression it pins (stupid social, plain 300-turn render): the hosting view
// rebuilds the List's scroll view; the retained offset recorded UIKit's inset
// rebase (-116 -> -153) as if the user had scrolled and restored it against
// the new view's still-zero inset, so the feed sat at offset 0 under the
// status bar and large title. The scripted path's settle loop hid it.
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

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }

struct Feed: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(0 ..< 60, id: \.self) { index in
                    Text("Row \(index)")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Social")
        }
    }
}

@MainActor func find(_ view: UIView, _ match: (UIView) -> Bool) -> UIView? {
    if match(view) { return view }
    for child in view.subviews {
        if let found = find(child, match) { return found }
    }
    return nil
}

@MainActor func list(in window: UIWindow) -> UIScrollView? {
    find(window) { $0.accessibilityIdentifier == "SwiftUI.List" } as? UIScrollView
}

@MainActor var clock = 0.0

/// One plain host turn, as the SwiftUI App loop and the harness's render path run them.
@MainActor func turn(_ window: UIWindow) {
    clock += 1.0 / 60
    OpenUIKitRuntime.animationTime = clock
    window.tick(timestamp: clock)
    window.layoutIfNeeded()
}

/// Rebuild the List the way a graph update does: the stack content's hosting
/// view lays out again and recreates its subviews.
@MainActor func rebuild(_ window: UIWindow) {
    find(window) { $0.accessibilityIdentifier == "SwiftUI.NavigationStack.content" }?.setNeedsLayout()
    turn(window)
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    OpenUIKitRuntime.configureDevice(.iPhone16e)
    let window = UIWindow(windowScene: UIWindowScene())
    let host = UIHostingController(rootView: Feed())
    window.rootViewController = host
    window.makeKeyAndVisible()
    for _ in 0 ..< 30 { turn(window) }

    guard let bar = find(window, { $0 is UINavigationBar }) as? UINavigationBar,
          let first = list(in: window) else {
        check(false, "the feed mounted a navigation bar and a List")
        return
    }
    let barBottom = bar.convert(CGPoint(x: 0, y: bar.bounds.maxY), to: window).y
    check(near(barBottom, 153), "large-title bar ends at 153 pt on iPhone 16e: \(barBottom)")
    check(near(first.contentOffset.y, -barBottom), "plain turns: the List rests below the bar: \(first.contentOffset.y)")

    rebuild(window)
    if let rebuilt = list(in: window) {
        check(near(rebuilt.contentOffset.y, -barBottom), "rebuild keeps the rest offset: \(rebuilt.contentOffset.y)")
        // An offset the scroll view (or the app's code) set, not a drag, is not retained.
        rebuilt.contentOffset = CGPoint(x: 0, y: -100)
        rebuild(window)
        check(near(list(in: window)?.contentOffset.y ?? .nan, -barBottom),
              "a non-user offset is not restored: \(list(in: window)?.contentOffset.y ?? .nan)")
    } else {
        check(false, "the List survived a rebuild")
    }

    // A drag the user made survives the next rebuild.
    window.sendTouch(.began, at: CGPoint(x: 195, y: 650), timestamp: clock)
    for step in 1 ... 20 {
        turn(window)
        window.sendTouch(.moved, at: CGPoint(x: 195, y: 650 - CGFloat(step) * 15), timestamp: clock)
    }
    // Hold still before lifting so the release carries no fling.
    for _ in 0 ..< 12 {
        turn(window)
        window.sendTouch(.moved, at: CGPoint(x: 195, y: 350), timestamp: clock)
    }
    turn(window)
    window.sendTouch(.ended, at: CGPoint(x: 195, y: 350), timestamp: clock)
    for _ in 0 ..< 240 { turn(window) }
    let scrolled = list(in: window)?.contentOffset.y ?? .nan
    check(scrolled > -barBottom + 100, "the drag scrolled the feed: \(scrolled)")
    rebuild(window)
    let kept = list(in: window)?.contentOffset.y ?? .nan
    check(near(kept, scrolled), "a user scroll survives a rebuild: \(scrolled) -> \(kept)")

    withExtendedLifetime((host, window)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "LIST_REST_PROBE=PASS" : "LIST_REST_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
