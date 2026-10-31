// Native gate: SwiftUI text inputs keep keyboard focus while the hosting view
// rebuilds (uikit/docs/SWIFTUI_TEXT_INPUT.md).
//
//   swift run swiftuitextinputprobe     exits 0 when every check passes
//
// Regression it pins (stupid social, Chats / Search): the hosting view
// rebuilds its UIViews on every state change, so the field a tap focused was
// replaced by a new one on the first typed character and `type` failed with
// "nothing has keyboard focus". Each check drives the app path: touches
// through `UIWindow.sendTouch`, keys through `sendText` / `sendKey`, plain
// host turns (tick + layout) in between, as the SwiftUI App loop runs them.
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

@MainActor func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants(of: $0) }
}

@MainActor func labels(in window: UIWindow) -> [String] {
    descendants(of: window).compactMap { ($0 as? UILabel)?.text }
}

@MainActor var clock = 0.0

/// The window's first responder, only while it is in the window: a field the
/// hosting view replaced is detached but can stay alive (and first
/// responder) while something else holds it.
@MainActor func focused(_ window: UIWindow) -> UIView? {
    guard let view = window.firstResponder as? UIView, view.isDescendant(of: window) else { return nil }
    return view
}

@MainActor func turn(_ window: UIWindow, _ count: Int = 1) {
    for _ in 0 ..< count {
        clock += 1.0 / 60
        OpenUIKitRuntime.animationTime = clock
        window.tick(timestamp: clock)
        window.layoutIfNeeded()
    }
}

@MainActor func tap(_ window: UIWindow, _ view: UIView) {
    let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
    window.sendTouch(.began, at: point, timestamp: clock)
    turn(window)
    window.sendTouch(.ended, at: point, timestamp: clock + 0.09)
    turn(window, 20)
}

@MainActor func type(_ window: UIWindow, _ text: String) {
    for character in text {
        window.sendText(String(character), timestamp: clock)
        turn(window, 4)
    }
}

@MainActor func key(_ window: UIWindow, _ key: UIKeyEventKey) {
    window.sendKey(key, timestamp: clock)
    turn(window, 4)
}

@MainActor func mount<Content: View>(_ view: Content) -> (UIWindow, UIHostingController<Content>) {
    let window = UIWindow(windowScene: UIWindowScene())
    let host = UIHostingController(rootView: view)
    window.rootViewController = host
    window.makeKeyAndVisible()
    turn(window, 10)
    return (window, host)
}

// MARK: 1. TextField: tap, type, backspace, return across rebuilds

struct Filtered: View {
    @State var query = ""
    @State var submits = 0
    let names = ["maya chen", "alex smith", "torres"]

    var body: some View {
        VStack {
            TextField("Search", text: $query)
                .onSubmit { submits += 1 }
            ForEach(names.filter { query.isEmpty || $0.contains(query) }, id: \.self) { Text($0) }
            Text("query=\(query) submits=\(submits)")
        }
    }
}

@MainActor func textField() {
    let (window, host) = mount(Filtered())
    guard let field = descendants(of: window).first(where: { $0.accessibilityIdentifier == "SwiftUI.TextField" })
        as? UITextField else {
        check(false, "TextField mounted a UITextField")
        return
    }
    tap(window, field)
    check(focused(window) === field, "a tap focuses the field")
    type(window, "ma")
    check(focused(window) === field, "the same field keeps focus after typing (rebuilds), in the window")
    check(field.text == "ma", "the field holds the typed text: \(field.text ?? "nil")")
    let shown = labels(in: window)
    check(shown.contains("query=ma submits=0"), "the binding received the text: \(shown)")
    check(shown.contains("maya chen") && !shown.contains("torres"), "the list filters on the binding: \(shown)")
    key(window, .backspace)
    check(labels(in: window).contains("query=m submits=0"), "backspace edits the binding")
    key(window, .return)
    check(labels(in: window).contains("query=m submits=1"), "return runs onSubmit")
    check(descendants(of: window).filter { $0 is UITextField }.count == 1, "one editor in the window")
    withExtendedLifetime((window, host)) {}
}

// MARK: 2. @FocusState: programmatic focus, unfocus and moving focus

enum FieldName: Hashable { case first, second }

struct Focused: View {
    @State var a = ""
    @State var b = ""
    @State var flag = false
    @FocusState var single: Bool
    @FocusState var named: FieldName?

    var body: some View {
        VStack {
            TextField("Single", text: $a).focused($single)
            TextField("First", text: $b).focused($named, equals: .first)
            TextField("Second", text: $b).focused($named, equals: .second)
            Text("single=\(single) named=\(String(describing: named)) flag=\(flag)")
            Button("focus single") { single = true }
            Button("blur single") { single = false }
            Button("first") { named = .first }
            Button("second") { named = .second }
        }
    }
}

@MainActor func focusState() {
    let (window, host) = mount(Focused())
    func field(_ placeholder: String) -> UITextField? {
        descendants(of: window).compactMap { $0 as? UITextField }.first { $0.placeholder == placeholder }
    }
    func button(_ title: String) -> UIView? {
        descendants(of: window).first { ($0 as? UIControl) != nil && descendants(of: $0).contains { ($0 as? UILabel)?.text == title } }
    }
    guard let b1 = button("focus single"), let single = field("Single") else {
        check(false, "focus probe mounted")
        return
    }
    tap(window, b1)
    check(window.firstResponder === single, "@FocusState = true focuses the field")
    check(labels(in: window).contains { $0.hasPrefix("single=true") }, "the binding reads true")
    type(window, "x")
    check(focused(window) != nil && focused(window) === field("Single"), "focus survives the rebuild typing causes")
    if let blur = button("blur single") { tap(window, blur) }
    check(!(window.firstResponder is UITextField), "@FocusState = false ends editing")
    if let first = button("first") { tap(window, first) }
    check(focused(window) != nil && focused(window) === field("First"), "focused(equals: .first) focuses First")
    if let second = button("second") { tap(window, second) }
    check(focused(window) != nil && focused(window) === field("Second"), "moving the value focuses Second")
    check(labels(in: window).contains { $0.contains("named=Optional(") && $0.contains("second") },
          "the binding keeps .second after First resigns: \(labels(in: window).filter { $0.hasPrefix("single=") })")
    if let firstField = field("First") { tap(window, firstField) }
    check(labels(in: window).contains { $0.contains("first)") }, "a tap on First writes .first back")
    withExtendedLifetime((window, host)) {}
}

// MARK: 3. A focused field that leaves the view stops editing

struct Removable: View {
    @State var text = ""
    @State var shown = true

    var body: some View {
        VStack {
            if shown { TextField("Gone", text: $text) }
            Button("hide") { shown = false }
        }
    }
}

@MainActor func removal() {
    let (window, host) = mount(Removable())
    guard let field = descendants(of: window).first(where: { $0 is UITextField }) else {
        check(false, "removable field mounted")
        return
    }
    tap(window, field)
    check(window.firstResponder === field, "removable field focused")
    window.sendText("q", timestamp: clock)
    turn(window, 4)
    if let hide = descendants(of: window).first(where: { v in (v as? UIControl) != nil && !(v is UITextField) }) {
        tap(window, hide)
    }
    check(window.firstResponder == nil, "removing the focused field ends editing: \(String(describing: window.firstResponder))")
    check(!descendants(of: window).contains { $0 is UITextField }, "the removed field left the window")
    withExtendedLifetime((window, host)) {}
}

// MARK: 4. .searchable in the navigation-bar drawer and docked at the bottom

struct DrawerSearch: View {
    @State var query = ""
    let chats = ["Maya Chen", "Alex Smith", "Torres"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(chats.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) {
                    Text($0)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chats")
            .searchable(text: $query, placement: .navigationBarDrawer, prompt: "Search")
        }
    }
}

struct DockedSearch: View {
    @State var query = ""

    var body: some View {
        NavigationStack {
            List { Text("query=\(query)") }
                .navigationTitle("Search")
                .searchable(text: $query)
        }
    }
}

struct PresentedSearch: View {
    @State var query = ""
    @State var presented = false

    var body: some View {
        NavigationStack {
            List {
                Text("presented=\(presented)")
                Button("present") { presented = true }
                Button("dismiss") { presented = false }
            }
            .navigationTitle("Chat")
            .searchable(text: $query, isPresented: $presented, placement: .navigationBarDrawer)
        }
    }
}

@MainActor func searchField(_ window: UIWindow) -> UISearchTextField? {
    descendants(of: window).compactMap { $0 as? UISearchTextField }.first { $0.window != nil && !$0.isHidden }
}

@MainActor func search() {
    do {
        let (window, host) = mount(DrawerSearch())
        guard let field = searchField(window) else {
            check(false, "drawer search field mounted")
            return
        }
        tap(window, field)
        check(window.firstResponder === field, "a tap focuses the drawer field")
        type(window, "may")
        check(focused(window) === field, "the drawer field keeps focus while typing, in the window")
        let shown = labels(in: window)
        check(shown.contains("Maya Chen") && !shown.contains("Torres"), "the list filters: \(shown)")
        key(window, .backspace)
        check(field.text == "ma", "backspace edits the drawer field: \(field.text ?? "nil")")
        withExtendedLifetime((window, host)) {}
    }
    do {
        let (window, host) = mount(DockedSearch())
        guard let field = searchField(window) else {
            check(false, "docked search field mounted")
            return
        }
        tap(window, field)
        check(window.firstResponder === field, "a tap focuses the docked field")
        type(window, "stu")
        check(focused(window) === field, "the docked field keeps focus while typing, in the window")
        check(labels(in: window).contains("query=stu"), "the binding receives docked text: \(labels(in: window))")
        withExtendedLifetime((window, host)) {}
    }
    do {
        let (window, host) = mount(PresentedSearch())
        func button(_ title: String) -> UIView? {
            descendants(of: window).first { ($0 as? UIControl) != nil && !($0 is UITextField)
                && descendants(of: $0).contains { ($0 as? UILabel)?.text == title } }
        }
        if let present = button("present") { tap(window, present) }
        check(window.firstResponder is UISearchTextField, "isPresented = true focuses the search field")
        type(window, "hi")
        check(focused(window) is UISearchTextField, "the presented field keeps focus while typing")
        if let dismiss = button("dismiss") {
            // The keyboard does not cover the list with a hardware keyboard.
            tap(window, dismiss)
        }
        check(!(window.firstResponder is UISearchTextField), "isPresented = false ends the search")
        check(labels(in: window).contains("presented=false"), "the binding reads false")
        withExtendedLifetime((window, host)) {}
    }
}

// MARK: 5. Keyboard modes

@MainActor func keyboardModes() {
    func keyboardShowing() -> Bool {
        UIApplication.shared.windows.contains { $0 is _UIKeyboardWindow && !$0.isHidden }
    }
    OpenUIKitRuntime.keyboard = .software
    do {
        let (window, host) = mount(Filtered())
        if let field = descendants(of: window).first(where: { $0 is UITextField }) { tap(window, field) }
        check(keyboardShowing(), "software keyboard: focus shows the drawn keyboard")
        _ = window.firstResponder?.resignFirstResponder()
        turn(window, 40)
        withExtendedLifetime((window, host)) {}
    }
    OpenUIKitRuntime.keyboard = .hardware
    do {
        let (window, host) = mount(Filtered())
        if let field = descendants(of: window).first(where: { $0 is UITextField }) { tap(window, field) }
        check(window.firstResponder is UITextField, "hardware keyboard: the field takes focus")
        check(!keyboardShowing(), "hardware keyboard: no software keyboard is drawn")
        type(window, "a")
        check(labels(in: window).contains("query=a submits=0"), "hardware keyboard: keys reach the field")
        withExtendedLifetime((window, host)) {}
    }
}

let failures = MainActor.assumeIsolated { () -> Int in
    // State changes publish on the host clock (as under the App loop), so
    // each plain turn applies them; no run loop runs here.
    _OpenInvalidationScheduler.forceHostClockForTesting = true
    OpenUIKitRuntime.systemFontCut = .iOS
    OpenUIKitRuntime.chromeRelease = .iOS27
    OpenUIKitRuntime.configureDevice(.iPhone16e)
    keyboardModes()
    OpenUIKitRuntime.keyboard = .hardware
    textField()
    focusState()
    removal()
    search()
    return Probe.failures
}
print(failures == 0 ? "TEXT_INPUT_PROBE=PASS" : "TEXT_INPUT_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
