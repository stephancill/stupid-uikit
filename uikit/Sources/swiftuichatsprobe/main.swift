// Native gate for the Chats side of stupid social (docs/CHAT_SCREENS.md).
//
//   swift run swiftuichatsprobe     exits 0 when every check passes
//
// Drives UIKit and UIHostingController directly, as swiftuinavchromeprobe
// does (debug build: `@testable` reads internal state).
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

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(a - b) <= tolerance }

@MainActor func descendants(of view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

// MARK: 1. Pager swipe over a row with trailing swipe actions

struct SwipeRows: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { index in
                Text("Row \(index)")
                    .swipeActions(edge: .trailing) {
                        Button("Delete") {}
                    }
            }
        }
        .listStyle(.plain)
    }
}

@MainActor final class PagerSource: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let left: UIViewController
    let right: UIViewController
    var finished: [Bool] = []

    init(left: UIViewController, right: UIViewController) {
        self.left = left
        self.right = right
    }

    func pageViewController(_: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        viewController === right ? left : nil
    }

    func pageViewController(_: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        viewController === left ? right : nil
    }

    func pageViewController(_: UIPageViewController, didFinishAnimating _: Bool, previousViewControllers _: [UIViewController], transitionCompleted completed: Bool) {
        finished.append(completed)
    }
}

/// stupidsim's `swipe x1 y1 x2 y2`: 192 ms, 16 moves (UIAutomationSession).
@MainActor func swipe(_ window: UIWindow, from: CGPoint, to: CGPoint, start: TimeInterval) {
    _ = window.sendTouch(.began, at: from, timestamp: start)
    for step in 1...16 {
        let f = CGFloat(step) / 16
        let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
        _ = window.sendTouch(.moved, at: p, timestamp: start + 0.192 * Double(f))
    }
    _ = window.sendTouch(.ended, at: to, timestamp: start + 0.192)
    var t = start + 0.2
    while t < start + 2 {
        window.tick(timestamp: t)
        t += 1.0 / 60
    }
}

@MainActor func pagerSwipe() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let left = UIViewController()
    let rows = UIHostingController(rootView: SwipeRows())
    let source = PagerSource(left: left, right: rows)
    let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    pager.dataSource = source
    pager.delegate = source
    pager.setViewControllers([rows], direction: .forward, animated: false)
    window.rootViewController = pager
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    window.tick(timestamp: 0)

    let rowHosts = descendants(of: rows.view).filter { $0.accessibilityIdentifier == "SwiftUI.SwipeActions" }
    check(!rowHosts.isEmpty, "rows carry swipe-action hosts: \(rowHosts.count)")

    // A rightward swipe over a row (trailing actions only) pages back.
    swipe(window, from: CGPoint(x: 58.5, y: 120), to: CGPoint(x: 370.5, y: 120), start: 1)
    check(pager.viewControllers?.first === left, "rightward swipe over a row pages to the previous page")
    check(source.finished == [true], "delegate reports a completed transition: \(source.finished)")

    // A leftward swipe over a row (on the rows page) reveals its actions instead of paging.
    pager.setViewControllers([rows], direction: .forward, animated: false)
    window.layoutIfNeeded()
    source.finished.removeAll()
    swipe(window, from: CGPoint(x: 300, y: 120), to: CGPoint(x: 150, y: 120), start: 3)
    check(pager.viewControllers?.first === rows, "leftward swipe over a row stays on the page")
    let revealed = descendants(of: rows.view).contains {
        $0.accessibilityIdentifier == "SwiftUI.SwipeActions.actions" && !$0.isHidden
    }
    check(revealed, "leftward swipe reveals the row's trailing actions")
    check(source.finished.isEmpty, "no page transition for a row swipe: \(source.finished)")
    withExtendedLifetime((window, source)) {}
}

// MARK: 2. Scroll geometry reports for typed KVO

@MainActor func scrollReports() {
    var reports: [(String, Any, Any)] = []
    let saved = _OpenUIKitKeyValueObserving.didChange
    _OpenUIKitKeyValueObserving.didChange = { object, property, old, new in
        reports.append((property, old, new))
        _ = object
    }
    let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    scroll.contentSize = CGSize(width: 100, height: 300)
    scroll.contentOffset = CGPoint(x: 0, y: 40)
    scroll.contentOffset = CGPoint(x: 0, y: 40)
    check(reports.map(\.0) == ["contentSize", "contentOffset"], "size and offset changes reported once: \(reports.map(\.0))")
    check((reports.last?.2 as? CGPoint) == CGPoint(x: 0, y: 40), "offset report carries the new value")
    _OpenUIKitKeyValueObserving.didChange = saved

    // Key paths resolve on the static type the observer used.
    check(UIScrollView._openUIKitObservedProperty(for: \UIScrollView.contentOffset) == "contentOffset", "UIScrollView.contentOffset is reported")
    check(UICollectionView._openUIKitObservedProperty(for: \UICollectionView.contentSize) == "contentSize", "UICollectionView.contentSize is reported")
    let erased: any _OpenUIKitKeyValueObservable.Type = UICollectionView.self
    check(erased._openUIKitObservedProperty(for: \UICollectionView.contentSize) == "contentSize", "existential metatype resolves the subclass key path")
    check(UIScrollView._openUIKitObservedProperty(for: \UIScrollView.zoomScale) == nil, "unreported properties resolve to nil")
}

// MARK: 3. Rigid HStack children keep their width

struct ChatRowShape: View {
    let avatarIsColor: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if avatarIsColor {
                    ZStack {
                        Color.purple
                        Text("WC").font(.system(size: 18, weight: .semibold))
                    }
                } else {
                    Color.orange
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .accessibilityIdentifier("avatar")
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("apron.chat / general").font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("9:59").font(.subheadline)
                }
                HStack(alignment: .top) {
                    Text("Maya Chen: Telegram, X and Bluesky DMs all in one list now, every one of them")
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("3").padding(.horizontal, 7).background(Color.blue, in: Capsule())
                }
            }
        }
    }
}

@MainActor func rigidRow(avatarIsColor: Bool) {
    let host = UIHostingController(rootView: ChatRowShape(avatarIsColor: avatarIsColor))
    host.view.frame = CGRect(x: 0, y: 0, width: 366, height: 60)
    host.view.layoutIfNeeded()
    let clips = descendants(of: host.view).filter { $0.accessibilityIdentifier == "SwiftUI.ClipRoundedRectangle" }
    let widths = clips.map(\.frame.width)
    check(clips.first.map { near($0.frame.width, 48) } == true,
          "\(avatarIsColor ? "initials" : "colour") avatar keeps 48 pt beside long text: \(widths)")
    let labels = descendants(of: host.view).compactMap { $0 as? UILabel }
    if let preview = labels.first(where: { $0.text?.hasPrefix("Maya") == true }) {
        let frame = preview.convert(preview.bounds, to: host.view)
        check(frame.minX >= 58 - 0.5, "text column starts after the avatar: \(frame)")
    } else {
        check(false, "preview label not found")
    }
    withExtendedLifetime(host) {}
}

// MARK: 4. `.searchable(placement: .navigationBarDrawer)` under a large title

struct DrawerStack: View {
    @State var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<4, id: \.self) { Text("Chat \($0)") }
            }
            .listStyle(.plain)
            .navigationTitle("Chats")
            .searchable(text: $query, placement: .navigationBarDrawer, prompt: "Search")
        }
    }
}

@MainActor func drawerSearch() {
    OpenUIKitRuntime.configureDevice(.iPhone16e)
    let window = UIWindow(windowScene: UIWindowScene())
    let host = UIHostingController(rootView: DrawerStack())
    window.rootViewController = host
    window.makeKeyAndVisible()
    for _ in 0..<3 { window.layoutIfNeeded() }
    let views = descendants(of: window)
    guard let field = views.first(where: { $0 is UISearchTextField }) else {
        check(false, "drawer search field exists")
        return
    }
    let frame = field.convert(field.bounds, to: window)
    check(near(frame.minX, 16) && near(frame.minY, 153) && near(frame.width, 358) && near(frame.height, 44),
          "drawer field at [16, 153, 358, 44] (iOS 27, iPhone 16e): \(frame)")
    let list = views.compactMap { $0 as? UIScrollView }.first { $0.accessibilityIdentifier == "SwiftUI.List" }
    if let list, let row = list.subviews.first(where: { $0.accessibilityIdentifier == "SwiftUI.List.row.0" }) {
        let rowFrame = row.convert(row.bounds, to: window)
        check(near(rowFrame.minY, 207), "first row starts under the drawer at 207: \(rowFrame)")
        check(near(list.frame.minY, 0) && near(list.frame.height, 844), "list keeps the full frame: \(list.frame)")
    } else {
        check(false, "list row found")
    }
    withExtendedLifetime((window, host)) {}
}

// MARK: 5. Constraints inside a visual effect view's contentView size it

@MainActor func effectViewSizing() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let root = UIView(frame: window.bounds)
    window.addSubview(root)
    // stupid social's composer: a glass pill holding a stack holding a fixed-height text box,
    // in a horizontal stack in a vertical stack pinned only at the bottom and sides.
    let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    let box = UIView()
    box.translatesAutoresizingMaskIntoConstraints = false
    // Hidden previews above the text row (a reply quote, a staged attachment) take no height.
    let thumbnail = UIView()
    thumbnail.translatesAutoresizingMaskIntoConstraints = false
    let attachmentPreview = UIStackView(arrangedSubviews: [thumbnail, UILabel()])
    attachmentPreview.isHidden = true
    let replyPreview = UIStackView(arrangedSubviews: [UILabel(), UILabel()])
    replyPreview.axis = .vertical
    replyPreview.isHidden = true
    let textRow = UIStackView(arrangedSubviews: [box, UIButton()])
    textRow.alignment = .bottom
    textRow.arrangedSubviews[1].isHidden = true
    let inner = UIStackView(arrangedSubviews: [replyPreview, attachmentPreview, textRow])
    inner.spacing = 4
    NSLayoutConstraint.activate([
        thumbnail.widthAnchor.constraint(equalToConstant: 48),
        thumbnail.heightAnchor.constraint(equalToConstant: 48),
    ])
    inner.axis = .vertical
    inner.isLayoutMarginsRelativeArrangement = true
    inner.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
    inner.translatesAutoresizingMaskIntoConstraints = false
    pill.contentView.addSubview(inner)
    let row = UIStackView(arrangedSubviews: [pill])
    row.alignment = .bottom
    let composer = UIStackView(arrangedSubviews: [row])
    composer.axis = .vertical
    composer.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(composer)
    NSLayoutConstraint.activate([
        box.heightAnchor.constraint(equalToConstant: 36),
        inner.topAnchor.constraint(equalTo: pill.contentView.topAnchor),
        inner.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor),
        inner.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor),
        inner.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor),
        composer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
        composer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
        composer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -42),
    ])
    window.makeKeyAndVisible()
    for _ in 0..<3 { window.layoutIfNeeded() }
    let pillFrame = pill.convert(pill.bounds, to: root)
    check(near(pillFrame.height, 44) && near(pillFrame.maxY, 802), "glass pill is 44 pt tall at the bottom: \(pillFrame)")
    check(near(composer.frame.height, 44), "composer stack hugs its pill: \(composer.frame)")
    check(near(pill.contentView.frame.height, 44), "contentView follows the effect view: \(pill.contentView.frame)")
    withExtendedLifetime(window) {}
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    pagerSwipe()
    scrollReports()
    rigidRow(avatarIsColor: true)
    rigidRow(avatarIsColor: false)
    drawerSearch()
    effectViewSizing()
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "CHATS_PROBE=PASS" : "CHATS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
