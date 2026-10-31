// Native gate for LazyVStack viewport materialisation (docs/SWIFTUI_LAZY_STACKS.md).
//
//   swift run swiftuilazyprobe     exits 0 when every check passes
//
// SwiftUITests cannot host @MainActor XCTest methods on Linux (see
// Tests/SwiftUITests/SwiftUILinuxStub.swift), so this executable drives the
// same UIHostingController path directly and lets graph invalidations run on
// the main executor between layout passes.
import Foundation
import OpenUIKit
import SwiftUI

@MainActor enum Probe {
    static var failures = 0
}

@MainActor func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { Probe.failures += 1 }
}

@MainActor func descendants(_ root: UIView) -> [UIView] {
    root.subviews + root.subviews.flatMap(descendants)
}

@MainActor func labels(_ root: UIView) -> [String] {
    descendants(root).compactMap { ($0 as? UILabel)?.text }
}

@MainActor func builtRows(_ root: UIView) -> [Int] {
    labels(root).compactMap { text -> Int? in
        guard text.hasPrefix("Row ") else { return nil }
        return Int(text.dropFirst(4).split(separator: " ").first ?? "")
    }.sorted()
}

@MainActor func scrollView(_ root: UIView) -> UIScrollView? {
    descendants(root).first { $0.accessibilityIdentifier == "SwiftUI.ScrollView" } as? UIScrollView
}

/// Lets queued graph invalidations run, then lays the host out again.
@MainActor func settle(_ host: UIView) async {
    for _ in 0 ..< 4 {
        host.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    host.layoutIfNeeded()
}

struct CounterRow: View {
    let index: Int
    @State private var taps = 0

    var body: some View {
        Button("Row \(index) taps \(taps)") { taps += 1 }
            .frame(height: 50)
    }
}

struct LazyFixture: View {
    let count: Int
    let capture: @MainActor (ScrollViewProxy) -> Void

    var body: some View {
        ScrollViewReader { proxy in content(proxy) }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        capture(proxy)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    CounterRow(index: index)
                }
            }
        }
    }
}

struct SiblingFixture: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("Header")
                ForEach(0 ..< 100, id: \.self) { index in
                    Text("Row \(index)").frame(height: 50)
                }
            }
        }
    }
}

struct UnscrolledFixture: View {
    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(0 ..< 20, id: \.self) { index in
                Text("Row \(index)").frame(height: 10)
            }
        }
    }
}

struct SmallFixture: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Text("Row \(index)").frame(height: 30)
                }
            }
        }
    }
}

struct PagerFixture: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0 ..< 800, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Row \(index)")
                        Color.gray.frame(height: 40)
                    }
                    .frame(height: 112, alignment: .top)
                }
            }
        }
        .frame(height: 112)
    }
}

@MainActor func run() async {
    // 1. Initial window, then the viewport-driven window.
    var proxy: ScrollViewProxy?
    let controller = UIHostingController(
        rootView: LazyFixture(count: 1000, capture: { proxy = $0 })
    )
    let host = controller.view!
    host.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
    host.layoutIfNeeded()
    check(builtRows(host) == Array(0 ..< 8), "first evaluation builds the initial window: \(builtRows(host))")
    await settle(host)
    let first = builtRows(host)
    check(first.first == 0 && first.count >= 15 && first.count <= 30,
          "viewport window covers 500pt of 50pt rows plus margin: \(first.count) rows \(first.first ?? -1)...\(first.last ?? -1)")
    check(scrollView(host)?.contentSize.height == 50_000, "content size spans every element: \(scrollView(host)?.contentSize.height ?? -1)")
    check(descendants(host).count < 200, "hierarchy stays small: \(descendants(host).count) views")

    // 2. @State on a built row.
    let button = descendants(host).compactMap { $0 as? UIControl }.first { control in
        descendants(control).contains { ($0 as? UILabel)?.text == "Row 3 taps 0" }
    }
    check(button != nil, "row 3 button is built")
    button?.sendActions(for: .touchUpInside)
    await settle(host)
    check(labels(host).contains("Row 3 taps 1"), "row 3 state updated")

    // 3. Scrolling far releases the top rows and builds the new region; the
    //    rebuilt scroll view keeps its offset.
    scrollView(host)?.setContentOffset(CGPoint(x: 0, y: 20_000), animated: false)
    await settle(host)
    let middle = builtRows(host)
    check(scrollView(host)?.contentOffset.y == 20_000, "offset survives re-evaluation: \(scrollView(host)?.contentOffset.y ?? -1)")
    check(middle.contains(400) && middle.contains(409) && !middle.contains(3),
          "window follows the offset: \(middle.first ?? -1)...\(middle.last ?? -1)")
    check(middle.count <= 40, "far rows released: \(middle.count) built")

    // 4. Scrolling back restores the unloaded row's state.
    scrollView(host)?.setContentOffset(.zero, animated: false)
    await settle(host)
    check(labels(host).contains("Row 3 taps 1"), "row 3 keeps @State across unload: \(labels(host).filter { $0.hasPrefix("Row 3 ") })")

    // 5. ScrollViewReader reaches an unbuilt row by its ForEach ID.
    if let proxy {
        proxy.scrollTo(900, anchor: .top)
        await settle(host)
        check(builtRows(host).contains(900), "scrollTo materialises row 900: \(builtRows(host).first ?? -1)...\(builtRows(host).last ?? -1)")
        check(scrollView(host)?.contentOffset.y == 45_000, "scrollTo offset: \(scrollView(host)?.contentOffset.y ?? -1)")
    } else {
        check(false, "proxy captured")
    }

    // 6. Content that is not a lone ForEach stays eager.
    let siblingController = UIHostingController(rootView: SiblingFixture())
    let sibling = siblingController.view!
    sibling.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
    await settle(sibling)
    check(builtRows(sibling).count == 100, "sibling content builds eagerly: \(builtRows(sibling).count)")

    // 7. Without a ScrollView the first layout requests every element.
    let unscrolledController = UIHostingController(rootView: UnscrolledFixture())
    let unscrolled = unscrolledController.view!
    unscrolled.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
    await settle(unscrolled)
    check(builtRows(unscrolled) == Array(0 ..< 20), "unscrolled lazy stack builds everything: \(builtRows(unscrolled).count)")

    // 8. A stack that fits the initial window renders as the eager VStack.
    let smallController = UIHostingController(rootView: SmallFixture())
    let small = smallController.view!
    small.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
    await settle(small)
    let smallLabels = descendants(small).compactMap { $0 as? UILabel }
    let smallFrames = smallLabels.map { $0.convert($0.bounds, to: small).minY }
    // Rows sit at 0, 34, 68, ... (30 pt frames, 4 pt spacing); each Text is
    // placed at its own height, centred in its 30 pt frame, as in SwiftUI.
    let labelInset = smallLabels.first.map { (30 - $0.bounds.height) / 2 } ?? 0
    check(builtRows(small) == Array(0 ..< 5), "small stack fully built")
    check(scrollView(small)?.contentSize.height == 500, "small stack content size is the viewport: \(scrollView(small)?.contentSize.height ?? -1)")
    check(smallFrames == [0, 34, 68, 102, 136].map { $0 + labelInset }, "small stack lays out as the eager VStack: \(smallFrames)")

    // 9. A one-row pager (stupid social's story bar shape): 800 rows of
    //    112pt behind a 112pt-tall ScrollView build only the initial window.
    let pagerController = UIHostingController(rootView: PagerFixture())
    let pager = pagerController.view!
    pager.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
    await settle(pager)
    check(builtRows(pager) == Array(0 ..< 8), "pager keeps the initial window: \(builtRows(pager))")
    check(scrollView(pager)?.contentSize.height == 800 * 112, "pager content size: \(scrollView(pager)?.contentSize.height ?? -1)")
    scrollView(pager)?.setContentOffset(CGPoint(x: 0, y: 112 * 7), animated: false)
    await settle(pager)
    let paged = builtRows(pager)
    check(paged.contains(7) && paged.contains(9) && paged.count <= 8, "paging to row 7 rebuilds around it: \(paged)")
    // Graph invalidation holds its controller weakly.
    withExtendedLifetime(
        (controller, siblingController, unscrolledController, smallController, pagerController)
    ) {}
}

await run()
print(Probe.failures == 0 ? "LAZY_PROBE=PASS" : "LAZY_PROBE=FAIL (\(Probe.failures))")
exit(Probe.failures == 0 ? 0 : 1)
