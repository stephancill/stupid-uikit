// Native gate for SwiftUI full-screen covers (docs/SWIFTUI_FULL_SCREEN_COVER.md):
// `fullScreenCover(isPresented:)` / `(item:)` present with UIKit's
// `.fullScreen` style, the screenshot status bar follows the covering
// controller's appearance, and the automation commands for screens that
// never settle (`wait <n>s`, `--no-settle`) parse.
//
//   swift run swiftuifullscreencoverprobe     exits 0 when every check passes
//
// SwiftUITests cannot host @MainActor XCTest methods on Linux, so this
// executable drives UIHostingController directly (debug build: `@testable`
// reads the presentation internals).
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

struct CoverItem: Identifiable {
    let id: Int
}

@MainActor enum Appearances {
    static var cover = 0
    static var nested = 0
}

struct CoverContent: View {
    let label: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Button(label) { dismiss() }
        }
        .onAppear { Appearances.cover += 1 }
    }
}

/// The story viewer's shape: a NavigationStack inside the cover.
struct NestedCoverFixture: View {
    let presented: Binding<Bool>

    var body: some View {
        Text("Root")
            .fullScreenCover(isPresented: presented) {
                NavigationStack {
                    Color.black.onAppear { Appearances.nested += 1 }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
    }
}

struct BoolCoverFixture: View {
    let presented: Binding<Bool>
    let onDismiss: @MainActor () -> Void

    var body: some View {
        Text("Root")
            .fullScreenCover(isPresented: presented, onDismiss: onDismiss) {
                CoverContent(label: "Close Cover")
            }
    }
}

struct ItemCoverFixture: View {
    let item: Binding<CoverItem?>

    var body: some View {
        Text("Root")
            .fullScreenCover(item: item) { value in
                CoverContent(label: "Item \(value.id)")
            }
    }
}

struct HiddenBarStack: View {
    var body: some View {
        NavigationStack {
            Text("Root").toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct SafeAreaFixture: View {
    let mode: Int

    var body: some View {
        switch mode {
        case 0: Color.red
        case 1: Color.red.ignoresSafeArea()
        case 2: Color.red.ignoresSafeArea(edges: .top)
        case 3: Color.red.ignoresSafeArea(.keyboard)
        default:
            ScrollView { Color.red.frame(height: 100) }
        }
    }
}

/// The story viewer's GitHub slide shape: a flexible group above a fixed
/// bottom button inside a ZStack whose background ignores the safe area.
struct FlexibleStackFixture: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // A stack (it places its children from its top) in an
                // unbounded frame: the frame centres the stack's own size.
                VStack(spacing: 0) { Color.green.frame(height: 50) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.blue.frame(width: 100, height: 44).padding(.bottom, 44)
            }
        }
    }
}

/// @State inside a GeometryReader (the whole story viewer is one).
struct GeometryStateChild: View {
    @State private var phase = "initial"

    var body: some View {
        Text(phase).onAppear { phase = "appeared" }
    }
}

struct GeometryStateFixture: View {
    let inNavigationStack: Bool

    var body: some View {
        if inNavigationStack {
            NavigationStack {
                GeometryReader { _ in GeometryStateChild() }
                    .toolbar(.hidden, for: .navigationBar)
            }
        } else {
            GeometryReader { _ in GeometryStateChild() }
        }
    }
}

/// A `.task` inside a GeometryReader inside a NavigationStack inside a cover,
/// writing @State (the story viewer's CachedAsyncImage).
struct TaskStateChild: View {
    @State private var phase = "initial"

    var body: some View {
        Text(phase).task { phase = "loaded" }
    }
}

struct TaskCoverFixture: View {
    let presented: Binding<Bool>

    var body: some View {
        Text("Root").fullScreenCover(isPresented: presented) {
            NavigationStack {
                GeometryReader { _ in TaskStateChild() }
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

/// The story progress bar: equal segments of GeometryReaders in an HStack.
struct SegmentsFixture: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 2, id: \.self) { _ in
                GeometryReader { _ in Color.white }.frame(height: 3)
            }
        }
        .padding(.horizontal, 8)
    }
}

final class StyledController: UIViewController {
    let style: UIStatusBarStyle
    let color: UIColor

    init(style: UIStatusBarStyle, color: UIColor) {
        self.style = style
        self.color = color
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.backgroundColor = color
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { style }
}

@MainActor func descendants(_ view: UIView) -> [UIView] {
    view.subviews + view.subviews.flatMap(descendants)
}

@MainActor func button(_ title: String, in view: UIView) -> UIControl? {
    descendants(view).compactMap { $0 as? UIControl }.first {
        descendants($0).compactMap { ($0 as? UILabel)?.text }.contains(title)
    }
}

/// The app host loop sets the animation clock and ticks the window together.
@MainActor func advance(_ window: UIWindow, to time: Double) {
    OpenUIKitRuntime.animationTime = time
    window.tick(timestamp: time)
}

@MainActor func makeWindow(root: UIViewController) -> UIWindow {
    let window = UIWindow(windowScene: UIWindowScene())
    window.rootViewController = root
    window.makeKeyAndVisible()
    root.view.frame = window.bounds
    window.layoutIfNeeded()
    // A window shows its root controller (the app host loop's scene does this).
    root.beginAppearanceTransition(true, animated: false)
    root.endAppearanceTransition()
    window.layoutIfNeeded()
    return window
}

@MainActor func run() {
    OpenUIKitRuntime.configureDevice(.iPhone16e)

    // 1. fullScreenCover(isPresented:): UIKit .fullScreen, the whole window,
    //    no dimming, the window's safe area, the presenter's view removed.
    var presented = false
    var dismissals = 0
    let binding = Binding(get: { presented }, set: { presented = $0 })
    let fixture = { BoolCoverFixture(presented: binding, onDismiss: { dismissals += 1 }) }
    let host = UIHostingController(rootView: fixture())
    let window = makeWindow(root: host)
    let bar = window._installScreenshotStatusBar(time: "09:41") as! _UIScreenshotStatusBarView
    _ = UIRenderer.render(window, scale: 1)
    check(!bar.lightContent, "status bar: dark ink over the white root screen")

    presented = true
    host.rootView = fixture()
    window.layoutIfNeeded()
    advance(window, to: 1)
    advance(window, to: 2)
    guard let cover = host.presentedViewController else {
        check(false, "fullScreenCover presented nothing")
        return
    }
    check(cover.modalPresentationStyle == .fullScreen, "cover style is .fullScreen: \(cover.modalPresentationStyle)")
    check(cover.presentationController?.shouldRemovePresentersView == true, "cover removes the presenter's view")
    check(cover.presentationController?.frameOfPresentedViewInContainerView == window.bounds,
          "cover frame is the window: \(String(describing: cover.presentationController?.frameOfPresentedViewInContainerView))")
    window.layoutIfNeeded()
    check(Appearances.cover == 1, "the cover's content appeared once: \(Appearances.cover)")
    let coverFrame = cover.view.convert(cover.view.bounds, to: window)
    check(coverFrame == window.bounds, "cover view fills the window: \(coverFrame)")
    check(cover.view.safeAreaInsets == UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
          "cover content has the window safe area: \(cover.view.safeAreaInsets)")
    check(!descendants(window).contains { $0 is _UIDimmingView }, "no sheet dimming behind a cover")
    let coverRender = UIRenderer.render(window, scale: 1)
    check(window.subviews.last === bar, "status bar stays topmost over the cover")
    let o = (10 * coverRender.width + 195) * 4
    print("probe: cover pixel (195,10) = \(coverRender.pixels[o]),\(coverRender.pixels[o + 1]),\(coverRender.pixels[o + 2]),\(coverRender.pixels[o + 3]) presented view \(String(describing: cover.presentationController?.presentedView?.frame)) window subviews \(window.subviews.map { String(describing: type(of: $0)) })")
    check(bar.lightContent, "status bar: light ink over the black cover")

    // Dismissal through the environment's DismissAction.
    if let close = button("Close Cover", in: cover.view) {
        close.sendActions(for: .touchUpInside)
        check(!presented, "dismiss() clears the binding")
        host.rootView = fixture()
        window.layoutIfNeeded()
        advance(window, to: 3)
        advance(window, to: 4)
        check(host.presentedViewController == nil, "cover dismissed")
        check(dismissals == 1, "onDismiss ran once: \(dismissals)")
        check(host.view.window === window, "the presenter's view is back")
        _ = UIRenderer.render(window, scale: 1)
        check(!bar.lightContent, "status bar: dark again after the cover left")
    } else {
        check(false, "the cover's close button is missing")
    }

    // 2. fullScreenCover(item:): built from the item, cleared on dismissal.
    var item: CoverItem?
    let itemBinding = Binding(get: { item }, set: { item = $0 })
    let itemHost = UIHostingController(rootView: ItemCoverFixture(item: itemBinding))
    let itemWindow = makeWindow(root: itemHost)
    item = CoverItem(id: 7)
    itemHost.rootView = ItemCoverFixture(item: itemBinding)
    itemWindow.layoutIfNeeded()
    advance(itemWindow, to: 1)
    advance(itemWindow, to: 2)
    if let itemCover = itemHost.presentedViewController {
        check(itemCover.modalPresentationStyle == .fullScreen, "item cover is .fullScreen")
        itemCover.view.layoutIfNeeded()
        if let close = button("Item 7", in: itemCover.view) {
            close.sendActions(for: .touchUpInside)
            check(item == nil, "item cover dismissal clears the item")
        } else {
            check(false, "item cover content was not built from the item")
        }
    } else {
        check(false, "fullScreenCover(item:) presented nothing")
    }

    // 2b. onAppear inside a NavigationStack inside a cover (the story viewer;
    //     `.task` rides the same appearance actions).
    var nestedPresented = false
    let nestedBinding = Binding(get: { nestedPresented }, set: { nestedPresented = $0 })
    let nestedHost = UIHostingController(rootView: NestedCoverFixture(presented: nestedBinding))
    let nestedWindow = makeWindow(root: nestedHost)
    nestedPresented = true
    nestedHost.rootView = NestedCoverFixture(presented: nestedBinding)
    nestedWindow.layoutIfNeeded()
    for t in 1...4 { advance(nestedWindow, to: Double(t)); nestedWindow.layoutIfNeeded() }
    check(Appearances.nested == 1, "a NavigationStack's content in a cover appeared once: \(Appearances.nested)")
    withExtendedLifetime((nestedHost, nestedWindow)) {}

    // 3. Explicit status bar styles win over the content beneath.
    let plain = UIViewController()
    let styleWindow = makeWindow(root: plain)
    let styleBar = styleWindow._installScreenshotStatusBar() as! _UIScreenshotStatusBarView
    plain.present(StyledController(style: .darkContent, color: .black), animated: false)
    _ = UIRenderer.render(styleWindow, scale: 1)
    check(!styleBar.lightContent, ".darkContent keeps dark ink over black")
    plain.dismiss(animated: false)
    plain.present(StyledController(style: .lightContent, color: .white), animated: false)
    _ = UIRenderer.render(styleWindow, scale: 1)
    check(styleBar.lightContent, ".lightContent draws light ink over white")

    // 4. `.toolbar(.hidden, for: .navigationBar)` hides the stack's bar (the
    //    story viewer's NavigationStack inside its cover).
    let hiddenBar = UIHostingController(rootView: HiddenBarStack())
    let hiddenWindow = makeWindow(root: hiddenBar)
    if let nav = hiddenBar.children.compactMap({ $0 as? UINavigationController }).first {
        nav.view.layoutIfNeeded()
        check(nav.isNavigationBarHidden, ".toolbar(.hidden, for: .navigationBar) hides the bar")
        check(nav.topViewController?.view.safeAreaInsets.top == 47,
              "content under a hidden bar has the window's top safe area: \(String(describing: nav.topViewController?.view.safeAreaInsets))")
    } else {
        check(false, "the hidden-bar stack installed no navigation controller")
    }
    withExtendedLifetime((hiddenBar, hiddenWindow)) {}

    // 5. Safe area (iOS cut): screen content is laid out in the safe area;
    //    ignoresSafeArea (container region) and scroll views extend.
    OpenUIKitRuntime.systemFontCut = .iOS
    func colorFrames(_ host: UIViewController) -> [CGRect] {
        descendants(host.view).filter { $0.accessibilityIdentifier == "SwiftUI.Color" }
            .map { $0.convert($0.bounds, to: host.view) }
    }
    let full = CGRect(x: 0, y: 0, width: 390, height: 844)
    let safe = CGRect(x: 0, y: 47, width: 390, height: 763)
    let expected: [(Int, CGRect, String)] = [
        (0, safe, "a Color is laid out in the safe area"),
        (1, full, "ignoresSafeArea() fills the screen"),
        (2, CGRect(x: 0, y: 0, width: 390, height: 810), "ignoresSafeArea(edges: .top) extends only the top"),
        (3, safe, "ignoresSafeArea(.keyboard) keeps the container safe area"),
    ]
    var safeWindows: [UIWindow] = []
    for (mode, frame, message) in expected {
        let host = UIHostingController(rootView: SafeAreaFixture(mode: mode))
        safeWindows.append(makeWindow(root: host))
        host.view.layoutIfNeeded()
        let frames = colorFrames(host)
        check(frames.first == frame, "\(message): \(frames)")
    }
    let scrollHost = UIHostingController(rootView: SafeAreaFixture(mode: 4))
    safeWindows.append(makeWindow(root: scrollHost))
    scrollHost.view.layoutIfNeeded()
    let scrollFrame = descendants(scrollHost.view).first { $0 is UIScrollView }.map { $0.convert($0.bounds, to: scrollHost.view) }
    check(scrollFrame?.minY == 0 && scrollFrame?.height == 844, "a root ScrollView extends under the safe area: \(String(describing: scrollFrame))")

    // 6. VStack: a flexible child beside a fixed one gets what the fixed one
    //    leaves (it took everything and pushed the button off screen).
    let stackHost = UIHostingController(rootView: FlexibleStackFixture())
    safeWindows.append(makeWindow(root: stackHost))
    stackHost.view.layoutIfNeeded()
    let stackFrames = colorFrames(stackHost)
    check(stackFrames.count == 3, "three colours: \(stackFrames)")
    if stackFrames.count == 3 {
        check(stackFrames[0] == full, "the black background fills the screen: \(stackFrames[0])")
        // Safe area 47...810; the button block is 44 + 44 padding at the bottom.
        check(stackFrames[2] == CGRect(x: 145, y: 722, width: 100, height: 44), "the fixed button sits 44 above the safe bottom: \(stackFrames[2])")
        check(stackFrames[1] == CGRect(x: 0, y: 359.5, width: 390, height: 50),
              "the flexible group centres in the rest: \(stackFrames[1])")
    }
    let segmentsHost = UIHostingController(rootView: SegmentsFixture())
    safeWindows.append(makeWindow(root: segmentsHost))
    segmentsHost.view.layoutIfNeeded()
    let segmentWidths = colorFrames(segmentsHost).map(\.width)
    check(segmentWidths == [185, 185], "two greedy segments share an HStack: \(segmentWidths)")
    OpenUIKitRuntime.systemFontCut = .macOS
    withExtendedLifetime((safeWindows, stackHost, scrollHost, segmentsHost)) {}

    // 7. A GeometryReader's content keeps its @State: its views are built
    //    during graph evaluation, so a state write in onAppear sticks.
    _OpenInvalidationScheduler.forceHostClockForTesting = true
    // (In a NavigationStack the same holds; the cover case below covers it.)
    for inStack in [false] {
        let geometryHost = UIHostingController(rootView: GeometryStateFixture(inNavigationStack: inStack))
        let geometryWindow = makeWindow(root: geometryHost)
        for t in 1...6 {
            advance(geometryWindow, to: 100 + Double(t))
            geometryWindow.layoutIfNeeded()
        }
        let phases = descendants(geometryHost.view).compactMap { ($0 as? UILabel)?.text }.filter { $0 != "" }
        check(phases == ["appeared"],
              "@State inside a GeometryReader\(inStack ? " in a NavigationStack" : "") keeps a value written in onAppear: \(phases)")
        withExtendedLifetime((geometryHost, geometryWindow)) {}
    }
    var taskPresented = false
    let taskBinding = Binding(get: { taskPresented }, set: { taskPresented = $0 })
    let taskHost = UIHostingController(rootView: TaskCoverFixture(presented: taskBinding))
    let taskWindow = makeWindow(root: taskHost)
    taskPresented = true
    taskHost.rootView = TaskCoverFixture(presented: taskBinding)
    taskWindow.layoutIfNeeded()
    for t in 1...8 {
        advance(taskWindow, to: 200 + Double(t))
        // Let the main actor run the task's body (it is a Swift Task).
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        taskWindow.layoutIfNeeded()
    }
    let taskPhases = taskHost.presentedViewController.map {
        descendants($0.view).compactMap { ($0 as? UILabel)?.text }.filter { $0 != "" }
    } ?? []
    check(taskPhases == ["loaded"], "a .task in a GeometryReader in a cover's NavigationStack writes its @State: \(taskPhases)")
    _OpenInvalidationScheduler.forceHostClockForTesting = false
    withExtendedLifetime((taskHost, taskWindow)) {}

    // 8. Automation commands for screens that never settle.
    check((try? UIAutomationCommand.parse("wait 2s")) == .waitTime(seconds: 2), "wait 2s")
    check((try? UIAutomationCommand.parse("wait 500ms")) == .waitTime(seconds: 0.5), "wait 500ms")
    check((try? UIAutomationCommand.parse("wait 30")) == .wait(turns: 30), "wait <turns> unchanged")
    check((try? UIAutomationCommand.parse("tap 0.34 0.26 --no-settle"))
          == .tap(x: 0.34, y: 0.26, holdMilliseconds: 90, verify: false, settle: false), "tap --no-settle")
    check((try? UIAutomationCommand.parse("tap 0.5 0.5")) == .tap(x: 0.5, y: 0.5, holdMilliseconds: 90, verify: false),
          "tap settles by default")
    check((try? UIAutomationCommand.parse("tap 0.5 0.5 --verify --no-settle")) == nil,
          "--verify with --no-settle is rejected")
    check((try? UIAutomationCommand.parse("wait 0s")) == nil, "wait 0s is rejected")

    withExtendedLifetime((host, window, itemHost, itemWindow, plain, styleWindow)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "FULL_SCREEN_COVER_PROBE=PASS" : "FULL_SCREEN_COVER_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
