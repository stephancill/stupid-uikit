// Native gate for SF Symbol accessibility labels in the automation tree
// (docs/SYMBOL_ACCESSIBILITY_LABELS.md): the iOS 27 label table and its
// language selection, symbol-only SwiftUI and UIKit controls, symbols next to
// text, app labels winning, and icon-only Labels taking their title.
//
//   swift run symbollabelsprobe     exits 0 when every check passes
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

@MainActor func host(_ controller: UIViewController) -> UIWindow {
    let window = UIWindow(windowScene: UIWindowScene())
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    for _ in 0..<4 {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
    return window
}

@MainActor func flatten(_ element: UIAutomationElement) -> [UIAutomationElement] {
    [element] + element.children.flatMap(flatten)
}

struct SymbolScreen: View {
    var body: some View {
        VStack {
            Button {} label: { Image(systemName: "xmark") }
            Button {} label: {
                HStack {
                    Text("GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                }
            }
            Image(systemName: "star.fill")
            Image(systemName: "speaker.slash.fill").accessibilityLabel("Muted")
            Button {} label: { Label("Preferences", systemImage: "gear").labelStyle(.iconOnly) }
            Button {} label: { Label("Add Account", systemImage: "plus") }
            Image(systemName: "doc")
        }
    }
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    OpenUIKitRuntime.configureDevice(.iPhone16e)

    // 1. The table and its language selection.
    func label(_ name: String, _ languages: [String]) -> String? {
        _UISymbolAccessibility.label(forSymbolNamed: name, preferredLanguages: languages)
    }
    check(label("star.fill", ["en-GB"]) == "Favourite", "en-GB star.fill is Favourite")
    check(label("star.fill", ["en-US"]) == "Favorite", "en-US star.fill is Favorite")
    check(label("star.fill", ["en"]) == "Favorite", "en star.fill is Favorite")
    check(label("xmark", ["en-GB"]) == "Close", "xmark is Close (override table)")
    check(label("speaker.wave.2.fill", ["en-GB"]) == "Volume High", "speaker.wave.2.fill is Volume High")
    check(label("arrow.up.forward.square", ["en-GB"]) == "Up-Forward Arrow In A Square",
          "arrow.up.forward.square from the last-resort table, capitalised at hyphens")
    check(label("trash", ["en-GB"]) == "Bin" && label("trash", ["en-AU"]) == "Trash",
          "regional table only for its own region")
    check(label("star.fill", ["de-DE"]) == nil, "no table for German: unlabelled")
    check(label("doc", ["en-GB"]) == nil, "an ambiguous (aliased) name stays unlabelled")
    check(label("not.a.symbol", ["en-GB"]) == nil, "an unlisted name is unlabelled")

    // 2. The tree, in British English.
    _UISymbolAccessibility.preferredLanguagesOverride = ["en-GB"]
    defer { _UISymbolAccessibility.preferredLanguagesOverride = nil }
    let controller = UIHostingController(rootView: SymbolScreen())
    let window = host(controller)
    let tree = flatten(UIAutomationTree.snapshot(of: window, applicationLabel: "probe"))
    func describe(_ e: UIAutomationElement?) -> String {
        e.map { UIAutomationTree.describe($0, screen: window.bounds) } ?? "nil"
    }
    let close = tree.first { $0.identifier == "xmark" }
    check(close?.role == "AXButton" && close?.label == "Close",
          "symbol-only Button is Button \"Close\" id=xmark: \(describe(close))")
    let github = tree.first { $0.label?.hasPrefix("GitHub") == true }
    check(github?.role == "AXButton" && github?.label == "GitHub" && github?.identifier == nil,
          "Button with text and a trailing symbol is just its text: \(describe(github))")
    let star = tree.first { $0.identifier == "star.fill" }
    check(star?.role == "AXImage" && star?.label == "Favourite",
          "Image(systemName:) is Image \"Favourite\" id=star.fill: \(describe(star))")
    check(tree.contains { $0.label == "Muted" } && !tree.contains { $0.label == "Mute" },
          "an app label wins over the symbol's")
    let preferences = tree.first { $0.identifier == "gear" || $0.label == "Preferences" }
    check(preferences?.role == "AXButton" && preferences?.label == "Preferences",
          "icon-only Label is labelled by its title, not the symbol (Settings): \(describe(preferences))")
    let add = tree.first { $0.label?.hasPrefix("Add") == true && $0.role == "AXButton" }
    check(add?.label == "Add Account", "a titled Label's symbol does not join its label: \(describe(add))")
    let doc = tree.first { $0.identifier == "doc" }
    check(doc != nil && doc?.label == nil, "an unlabelled symbol keeps only its name: \(describe(doc))")

    // 3. UIKit: image-only button and bar button item, titled button.
    let plain = UIViewController()
    let imageButton = UIButton(type: .system)
    imageButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    imageButton.frame = CGRect(x: 20, y: 200, width: 44, height: 44)
    let titledButton = UIButton(type: .system)
    titledButton.setTitle("Delete", for: .normal)
    titledButton.setImage(UIImage(systemName: "trash"), for: .normal)
    titledButton.frame = CGRect(x: 20, y: 260, width: 120, height: 44)
    plain.view.addSubview(imageButton)
    plain.view.addSubview(titledButton)
    plain.navigationItem.rightBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "gear"), style: .plain, target: nil, action: nil)
    let nav = UINavigationController(rootViewController: plain)
    let uikitWindow = host(nav)
    let uikitTree = flatten(UIAutomationTree.snapshot(of: uikitWindow, applicationLabel: "probe"))
    let uikitClose = uikitTree.first { $0.identifier == "xmark" }
    check(uikitClose?.role == "AXButton" && uikitClose?.label == "Close",
          "UIKit image-only button is Button \"Close\" id=xmark: \(describe(uikitClose))")
    check(uikitTree.contains { $0.role == "AXButton" && $0.label == "Delete" },
          "UIKit titled button keeps its title")
    let gear = uikitTree.first { $0.identifier == "gear" }
    check(gear?.role == "AXButton" && gear?.label == "Settings",
          "symbol bar button item is Button \"Settings\" id=gear: \(describe(gear))")

    withExtendedLifetime((window, controller, uikitWindow, nav)) {}
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "SYMBOL_LABELS_PROBE=PASS" : "SYMBOL_LABELS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
