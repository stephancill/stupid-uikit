// Native gate for screens beyond a root (docs/SWIFTUI_PUSHED_SCREENS.md):
// value NavigationLinks, stable toolbar items, iOS inset-grouped Form/List
// geometry and accessibility, the iOS 27 glass back button and the
// bottom-docked `.searchable` field.
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

    withExtendedLifetime((linkWindow, pushWindow, classicWindow, formWindow, searchWindow, store)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "SCREENS_PROBE=PASS" : "SCREENS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
