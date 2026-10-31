// Native gate for screens beyond a root (docs/SWIFTUI_PUSHED_SCREENS.md):
// value NavigationLinks, stable toolbar items, iOS inset-grouped Form/List
// geometry and accessibility, the iOS 27 glass back button and the
// bottom-docked `.searchable` field; section 6 the iOS 27 docked field,
// palette and ContentUnavailableView description (docs/IOS27_CROSS_SCREEN.md).
//
//   swift run swiftuiscreensprobe     exits 0 when every check passes
//
// Drives UIHostingController directly, as swiftuinavchromeprobe does.
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

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) < tolerance }

@MainActor final class PathStore {
    var path: [Int] = []
    var binding: Binding<[Int]> {
        Binding(get: { self.path }, set: { self.path = $0 })
    }
}

struct ValueLinkStack: View {
    let path: Binding<[Int]>

    var body: some View {
        NavigationStack(path: path) {
            NavigationLink(value: 7) { Text("Go") }
                .navigationTitle("Root")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(value: 9) { Image(systemName: "gear") }
                    }
                }
                .navigationDestination(for: Int.self) { value in
                    Text("Destination \(value)").navigationTitle("Pushed")
                }
        }
    }
}

struct SettingsForm: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Add Account") {}
                } header: {
                    Text("Accounts")
                }
                Section {
                    LabeledContent("Network", value: "X")
                    Text("Second")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct UnavailableScreen: View {
    var body: some View {
        ContentUnavailableView("Title", systemImage: "magnifyingglass",
                               description: Text("Description"))
    }
}

@MainActor func findLabel(_ text: String, in view: UIView) -> UILabel? {
    if let label = view as? UILabel, label.text == text { return label }
    for child in view.subviews {
        if let found = findLabel(text, in: child) { return found }
    }
    return nil
}

func rgba255(_ c: CanvasColor) -> [Int] {
    [c.red, c.green, c.blue].map { Int(($0 * 255).rounded()) } + [Int((c.alpha * 100).rounded())]
}

struct SearchStack: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Text("Row")
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .searchable(text: $query)
        }
    }
}

@MainActor func host(_ controller: UIViewController) -> UIWindow {
    let window = UIWindow(windowScene: UIWindowScene())
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    settle(controller)
    return window
}

@MainActor func settle(_ controller: UIViewController) {
    for _ in 0..<4 {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        for nav in navigationControllers(controller) {
            nav.view.layoutIfNeeded()
            nav.navigationBar.layoutIfNeeded()
            nav.topViewController?.view.layoutIfNeeded()
        }
    }
}

@MainActor func navigationControllers(_ controller: UIViewController) -> [UINavigationController] {
    var out: [UINavigationController] = []
    if let nav = controller as? UINavigationController { out.append(nav) }
    for child in controller.children { out += navigationControllers(child) }
    return out
}

@MainActor func find(_ id: String, in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == id { return view }
    for child in view.subviews {
        if let found = find(id, in: child) { return found }
    }
    return nil
}

@MainActor func frame(_ view: UIView?, in window: UIWindow) -> CGRect {
    guard let view else { return .null }
    return view.convert(view.bounds, to: window)
}

@MainActor func flatten(_ element: UIAutomationElement) -> [UIAutomationElement] {
    [element] + element.children.flatMap(flatten)
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    OpenUIKitRuntime.configureDevice(.iPhone16e)

    // 1. NavigationLink(value:) appends to the stack's path, in the content
    //    and as a toolbar item.
    let store = PathStore()
    let linkHost = UIHostingController(rootView: ValueLinkStack(path: store.binding))
    let linkWindow = host(linkHost)
    if let link = find("SwiftUI.NavigationLink", in: linkHost.view) as? UIControl {
        link.sendActions(for: .touchUpInside)
        check(store.path == [7], "value link appends its value: \(store.path)")
    } else {
        check(false, "value link control rendered")
    }
    if let nav = navigationControllers(linkHost).first,
       let item = nav.viewControllers.first?.navigationItem.rightBarButtonItems?.first {
        // A large-title bar passes touches through except on its controls:
        // the bar item must still be hit.
        if let itemView = nav.navigationBar.rightItemViews.first {
            let center = itemView.convert(CGPoint(x: itemView.bounds.midX, y: itemView.bounds.midY),
                                          to: linkWindow)
            var hit = linkWindow.hitTest(center, with: nil)
            while let view = hit, view !== itemView { hit = view.superview }
            check(hit === itemView, "large-title bar item takes the touch at \(center)")
        } else {
            check(false, "toolbar item view")
        }
        item.primaryAction?.performWithSender(item, target: nil)
        check(store.path == [7, 9], "toolbar value link appends its value: \(store.path)")

        // 2. Re-applying the chrome keeps equivalent items (and their views).
        // (Back at the root: the appended values would push destinations.)
        store.path = []
        let before = nav.navigationBar.rightItemViews.first
        linkHost.rootView = ValueLinkStack(path: store.binding)
        settle(linkHost)
        let after = nav.viewControllers.first?.navigationItem.rightBarButtonItems?.first
        check(after === item, "re-evaluation keeps the toolbar item")
        check(before != nil && nav.navigationBar.rightItemViews.first === before,
              "re-evaluation keeps the item view")
    } else {
        check(false, "toolbar value link installed a bar item")
    }

    // 3. Pushed destination: the iOS 27 back control is a 44 pt glass circle.
    OpenUIKitRuntime.chromeRelease = .iOS27
    let pushStore = PathStore()
    pushStore.path = [7]
    let pushHost = UIHostingController(rootView: ValueLinkStack(path: pushStore.binding))
    let pushWindow = host(pushHost)
    if let nav = navigationControllers(pushHost).first {
        check(nav.viewControllers.count == 2, "path [7] pushes one destination: \(nav.viewControllers.count)")
        let bar = nav.navigationBar
        bar.layoutIfNeeded()
        if let back = bar.backButton {
            check(back.isGlass, "iOS 27 back control is glass")
            let f = back.convert(back.bounds, to: pushWindow)
            check(near(f.minX, 16) && near(f.minY, 47) && near(f.width, 44) && near(f.height, 44),
                  "back circle [16, 47, 44, 44]: \(f)")
            check(back.backLabel.isHidden && back.backLabel.text == "Root",
                  "back title is hidden and kept as its label")
            let tree = flatten(UIAutomationTree.snapshot(of: pushWindow, applicationLabel: "probe"))
            check(tree.contains { $0.role == "AXButton" && $0.label == "Root" && $0.identifier == "BackButton" },
                  "back control in the tree")
        } else {
            check(false, "pushed destination has a back control")
        }
    }
    OpenUIKitRuntime.chromeRelease = .iOS26
    let classicStore = PathStore()
    classicStore.path = [7]
    let classicHost = UIHostingController(rootView: ValueLinkStack(path: classicStore.binding))
    let classicWindow = host(classicHost)
    if let back = navigationControllers(classicHost).first?.navigationBar.backButton {
        check(!back.isGlass && !back.backLabel.isHidden, "iOS 26 chrome keeps chevron + title")
    }

    // 4. Form = inset-grouped list on the iOS cut.
    let formHost = UIHostingController(rootView: SettingsForm())
    let formWindow = host(formHost)
    let card0 = frame(find("SwiftUI.Form.card.0", in: formHost.view), in: formWindow)
    let card1 = frame(find("SwiftUI.Form.card.1", in: formHost.view), in: formWindow)
    let header0 = frame(find("SwiftUI.Form.header.0", in: formHost.view), in: formWindow)
    let header1 = frame(find("SwiftUI.Form.header.1", in: formHost.view), in: formWindow)
    check(near(header0.minY, 153) && near(header0.height, 40 + 1.0 / 3.0) && near(header0.minX, 16)
          && near(header0.width, 358), "first header block [16, 153, 358, 40.33]: \(header0)")
    check(near(card0.minX, 16) && near(card0.width, 358) && near(card0.minY, header0.maxY)
          && near(card0.height, 52), "first card under its header, one 52 pt row: \(card0)")
    check(near(header1.minY, card0.maxY + 17 + 2.0 / 3.0), "17.5 pt (pixel) section gap: \(header1)")
    check(near(card1.minY, header1.maxY) && near(card1.height, 104), "second card two rows: \(card1)")
    let cardView = find("SwiftUI.Form.card.1", in: formHost.view)
    check(cardView?.layer.cornerRadius == 26 && cardView?.clipsToBounds == true, "card radius 26")
    let separator = frame(find("SwiftUI.Form.separator", in: formHost.view), in: formWindow)
    check(near(separator.minX, 32) && near(separator.maxX, 358) && near(separator.height, 1)
          && near(separator.maxY, card1.minY + 52), "separator from the text column to 16 pt in: \(separator)")
    let tree = flatten(UIAutomationTree.snapshot(of: formWindow, applicationLabel: "probe"))
    func element(_ label: String) -> UIAutomationElement? { tree.first { $0.label == label } }
    check(element("Accounts")?.role == "AXHeading" && element("Accounts").map { near($0.frame.width, 358) } == true,
          "header is a full-width heading: \(String(describing: element("Accounts")))")
    check(element("Add Account")?.role == "AXButton" && element("Add Account").map { $0.frame == card0 } == true,
          "button row is one row-sized button: \(String(describing: element("Add Account")))")
    check(element("Network, X")?.role == "AXStaticText"
          && element("Network, X").map { near($0.frame.minY, card1.minY) && near($0.frame.height, 52) } == true,
          "LabeledContent row is one element: \(String(describing: element("Network, X")))")
    check(tree.contains { $0.role == "AXGroup" }, "the form scrolls (a group)")

    // 5. `.searchable` (automatic) docks at the bottom on the phone.
    let searchHost = UIHostingController(rootView: SearchStack())
    let searchWindow = host(searchHost)
    if let nav = navigationControllers(searchHost).first {
        let item = nav.topViewController?.navigationItem
        check(item?.searchController != nil, "automatic searchable installs a search controller")
        check(nav.navigationBar.usesBottomSearch, "the field docks at the bottom")
        if let bar = item?.searchController?.searchBar {
            let f = frame(bar.superview, in: searchWindow)
            check(near(f.minX, 28) && near(f.minY, 768) && near(f.width, 334) && near(f.height, 48),
                  "glass capsule [28, 768, 334, 48]: \(f)")
            check(bar.placeholder == "Search", "prompt is the placeholder")
        }
        check(find("SwiftUI.Searchable", in: searchHost.view) == nil, "no inline search bar")
        let list = frame(find("SwiftUI.List.card.0", in: searchHost.view), in: searchWindow)
        check(near(list.minY, 153) && near(list.minX, 16), "inset-grouped list card under the bar: \(list)")
    }

    // 6. iOS 27 cross-screen values (docs/IOS27_CROSS_SCREEN.md), against the iOS 26 chrome.
    let light = UITraitCollection(userInterfaceStyle: .light)
    let dark = UITraitCollection(userInterfaceStyle: .dark)
    let savedChrome = OpenUIKitRuntime.chromeRelease
    var keep: [AnyObject] = []
    for release in [OpenUIKitChromeRelease.iOS26, .iOS27] {
        OpenUIKitRuntime.chromeRelease = release
        let tag = release == .iOS27 ? "iOS 27" : "iOS 26"
        let h = UIHostingController(rootView: SearchStack())
        let w = host(h)
        keep += [h, w]
        guard let nav = navigationControllers(h).first,
              let bar = nav.topViewController?.navigationItem.searchController?.searchBar,
              let platter = bar.superview else {
            check(false, "\(tag): docked search bar present")
            continue
        }
        let field = bar.searchTextField
        let ff = frame(field, in: w)
        let text = field.textRect(forBounds: field.bounds)
        let rim = platter.subviews.first { $0 is _UIBarPlatterRimView }
        let sep = rgba255(UIColor.opaqueSeparator.resolvedCGColor(with: light))
        let sepDark = rgba255(UIColor.opaqueSeparator.resolvedCGColor(with: dark))
        let blue = rgba255(UIColor.systemBlue.resolvedCGColor(with: light))
        let placeholder = rgba255(field.defaultPlaceholderColor.resolvedCGColor(with: light))
        check(blue == [0, 136, 255, 100], "\(tag): systemBlue light (0, 136, 255): \(blue)")
        if release == .iOS27 {
            check(near(ff.minX, 28) && near(ff.minY, 778) && near(ff.width, 334) && near(ff.height, 28),
                  "iOS 27: field [28, 778, 334, 28]: \(ff)")
            let line = field.subviews.flatMap(\.subviews).first { ($0 as? UILabel)?.text == "Search" }
            let lineY = line.map { frame($0, in: w).minY }
            check(near(text.minX, 40.667) && lineY.map { near($0, 783) } == true,
                  "iOS 27: text box x 40.667, placeholder line box top 783: \(text) \(String(describing: lineY))")
            let icon = UISearchBar.BottomDock.iOS27IconFrame
            check(near(icon.minX + UISearchTextField.ringCenter.x, 20.667)
                  && near(icon.minY + UISearchTextField.ringCenter.y, 11.333),
                  "iOS 27: magnifier ring centre (20.667, 11.333) in the field: \(icon)")
            check(placeholder == [0, 0, 0, 41], "iOS 27: placeholder black at 0.41: \(placeholder)")
            check(rim != nil && rim?.isHidden == false
                  && rim.map { frame($0, in: w) == CGRect(x: 27.5, y: 767.5, width: 335, height: 49) } == true,
                  "iOS 27: platter rim 0.5 pt outside: \(String(describing: rim.map { frame($0, in: w) }))")
            check(platter.layer.shadowOpacity == _UIBarMetrics.iOS27ShadowOpacity, "iOS 27: light platter shadow")
            check(sep == [231, 231, 232, 100] && sepDark == [42, 42, 44, 100],
                  "iOS 27: opaqueSeparator (231, 231, 232) / (42, 42, 44): \(sep) \(sepDark)")
        } else {
            check(near(ff.minX, 33) && near(ff.minY, 773) && near(ff.width, 324) && near(ff.height, 38),
                  "iOS 26: field [33, 773, 324, 38] unchanged: \(ff)")
            let line = field.subviews.flatMap(\.subviews).first { ($0 as? UILabel)?.text == "Search" }
            let lineY = line.map { frame($0, in: w).minY }
            check(near(text.minX, 41.5) && lineY.map { near($0, 782) } == true,
                  "iOS 26: text box x 41.5, line box top 782 unchanged: \(text) \(String(describing: lineY))")
            check(placeholder == [60, 60, 67, 60], "iOS 26: placeholder secondaryLabel: \(placeholder)")
            check(rim == nil, "iOS 26: no rim view")
            check(platter.layer.shadowOpacity == UITabBar.shadowOpacity, "iOS 26: tab platter shadow unchanged")
            check(sep == [198, 198, 200, 100] && sepDark == [56, 56, 58, 100],
                  "iOS 26: opaqueSeparator (198, 198, 200) / (56, 56, 58): \(sep) \(sepDark)")
        }
        let cuv = UIHostingController(rootView: UnavailableScreen())
        let cw = host(cuv)
        keep += [cuv, cw]
        let description = findLabel("Description", in: cuv.view)
        let dc = description.map { rgba255($0.textColor.resolvedCGColor(with: light)) }
        check(dc == [60, 60, 67, 60], "\(tag): ContentUnavailableView description is secondaryLabel: \(String(describing: dc))")
        let title = findLabel("Title", in: cuv.view)
        check(title.map { near($0.font.pointSize, 20) && $0.font.weight == .bold } == true,
              "\(tag): ContentUnavailableView title is 20 pt bold: \(String(describing: title?.font))")
    }
    OpenUIKitRuntime.chromeRelease = savedChrome

    withExtendedLifetime((linkWindow, pushWindow, classicWindow, formWindow, searchWindow, store, keep)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "SCREENS_PROBE=PASS" : "SCREENS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
