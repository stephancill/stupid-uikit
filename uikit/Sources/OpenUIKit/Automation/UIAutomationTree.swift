// Accessibility tree for automation. Owner: automation module
// (docs/AUTOMATION.md).
//
// Builds the tree an iOS accessibility client reads from a window — the
// same shape `stupidsim ui-tree` prints for the iOS Simulator (an
// Application root, Group containers, Button / StaticText / Image /
// Heading / TextField leaves with labels, values, identifiers and frames in
// window points) — so an agent can compare a guest's tree with the
// simulator's and tap an element by the centre printed on its line.
//
// UIKit decides most of this itself: which views are elements by default
// (labels, controls, text inputs), how a control's label is composed from
// its content, which containers appear. OpenUIKit stores the accessibility
// properties (NSObjectAccessibility.swift) but drives no assistive
// technology, so the defaults live here, in one place, rather than as
// overrides on every class. A framework layered on UIKit (the SwiftUI
// layer) says what its own views mean through `_automationAccessibility`.

/// What a framework layered on UIKit means by one of the UIViews it
/// realises, for the accessibility tree. The SwiftUI layer sets this on the
/// views behind `Image`, `NavigationLink` and the accessibility modifiers,
/// whose plain UIKit reading would be wrong (a SwiftUI `.accessibilityLabel`
/// on a stack labels every element inside it; it is not itself an element).
public struct _UIAutomationAccessibility {
    public enum Role {
        case image
        case button
        case staticText
    }

    /// `.accessibilityElement(children:)`.
    public enum Children {
        case combine
        case ignore
        case contain
    }

    /// This view is a leaf element of this role.
    public var role: Role?
    /// Applies to every element inside the view (SwiftUI semantics of the
    /// accessibility modifiers on a container); outermost wins.
    public var label: String?
    public var hint: String?
    public var value: String?
    public var identifier: String?
    public var addedTraits: UIAccessibilityTraits
    /// The view is one element whose label combines (or ignores) its content.
    public var children: Children?
    /// The SF Symbol an image element draws (`Image(systemName:)`). Without
    /// a label of its own it takes iOS's label for the symbol
    /// (`_UISymbolAccessibility`).
    public var symbolName: String?

    public init(
        role: Role? = nil,
        label: String? = nil,
        hint: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        addedTraits: UIAccessibilityTraits = [],
        children: Children? = nil,
        symbolName: String? = nil
    ) {
        self.role = role
        self.label = label
        self.hint = hint
        self.value = value
        self.identifier = identifier
        self.addedTraits = addedTraits
        self.children = children
        self.symbolName = symbolName
    }
}

extension UIView {
    /// See `_UIAutomationAccessibility`. Nil for ordinary UIKit views.
    public var _automationAccessibility: _UIAutomationAccessibility? {
        get { _accessibility.automation }
        set { _accessibility.automation = newValue }
    }
}

/// One element of the tree. Field names, roles (`AX…`) and role
/// descriptions follow what `stupidsim ui-tree --json` reports for the iOS
/// Simulator; frames are window points.
public struct UIAutomationElement: Equatable {
    public var role: String
    public var roleDescription: String?
    public var label: String?
    public var title: String?
    public var identifier: String?
    public var value: String?
    public var frame: CGRect
    public var children: [UIAutomationElement]
    /// The label is iOS's default for an SF Symbol rather than text or a
    /// label the app set. iOS composes a container's label from such labels
    /// only when its content has no other label (a Button showing only a
    /// symbol is "Close"; a Button with a title and a trailing symbol is
    /// just its title). Not part of the printed tree.
    public var labelIsSymbolDefault: Bool = false

    public init(
        role: String,
        roleDescription: String?,
        label: String? = nil,
        title: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        frame: CGRect,
        children: [UIAutomationElement] = []
    ) {
        self.role = role
        self.roleDescription = roleDescription
        self.label = label
        self.title = title
        self.identifier = identifier
        self.value = value
        self.frame = frame
        self.children = children
    }

    /// Centre in the normalized coordinates a tap takes (0...1 across
    /// `screen`); nil for an empty frame or a centre off screen.
    public func normalizedCenter(in screen: CGRect) -> CGPoint? {
        guard screen.width > 0, screen.height > 0, !frame.isEmpty else { return nil }
        let point = CGPoint(
            x: (frame.midX - screen.minX) / screen.width,
            y: (frame.midY - screen.minY) / screen.height
        )
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        return point
    }
}

@preconcurrency @MainActor
public enum UIAutomationTree {
    /// The tree of `window`, rooted at an Application element labelled
    /// `applicationLabel` (iOS uses the bundle's display name).
    public static func snapshot(of window: UIWindow, applicationLabel: String?) -> UIAutomationElement {
        window.layoutIfNeeded()
        var builder = Builder(window: window)
        var children: [UIAutomationElement] = []
        for child in window.subviews {
            builder.collect(child, Inherited(), into: &children, inGroup: false)
        }
        return UIAutomationElement(
            role: "AXApplication",
            roleDescription: "application",
            label: applicationLabel,
            frame: window.bounds,
            children: children
        )
    }

    /// `stupidsim ui-tree` text: one element per line, indented by depth,
    /// `Role "label" title="…" value="…" id=… @ x,y` (centre in normalized
    /// coordinates, absent off screen). `labelled` keeps only elements with
    /// a label, title, identifier or value, unindented.
    /// `screen` is what centres are measured against: the window, which is `root`'s frame unless
    /// `root` is a subtree (`ui-tree --at`).
    public static func text(_ root: UIAutomationElement, labelled: Bool = false, screen: CGRect? = nil) -> String {
        let screen = screen ?? root.frame
        var lines: [String] = []
        func visit(_ element: UIAutomationElement, depth: Int) {
            let isLabelled = element.label != nil || element.title != nil
                || element.identifier != nil || element.value != nil
            if !labelled || isLabelled {
                let indent = String(repeating: "  ", count: labelled ? 0 : depth)
                lines.append(indent + describe(element, screen: screen))
            }
            for child in element.children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line of `text`.
    public static func describe(_ element: UIAutomationElement, screen: CGRect) -> String {
        var role = element.role
        if role.hasPrefix("AX") { role.removeFirst(2) }
        var parts = [role]
        if let label = element.label { parts.append("\"\(label)\"") }
        if let title = element.title, title != element.label { parts.append("title=\"\(title)\"") }
        if let value = element.value { parts.append("value=\"\(value)\"") }
        if let identifier = element.identifier { parts.append("id=\(identifier)") }
        if let center = element.normalizedCenter(in: screen) {
            parts.append("@ \(fixed2(center.x)),\(fixed2(center.y))")
        }
        return parts.joined(separator: " ")
    }

    /// `stupidsim ui-tree --json`: Foundation's pretty-printed, sorted-key
    /// JSONEncoder layout of the same fields, frames as [[x, y], [w, h]].
    public static func json(_ root: UIAutomationElement) -> String {
        var out = ""
        writeJSON(root, indent: 0, into: &out)
        return out + "\n"
    }

    /// The deepest element whose frame contains `point` (window points),
    /// drawn last wins — what a tap at that point would most likely reach.
    public static func element(at point: CGPoint, in root: UIAutomationElement) -> UIAutomationElement? {
        var best: UIAutomationElement?
        func visit(_ element: UIAutomationElement) {
            if element.frame.contains(point) { best = element }
            for child in element.children { visit(child) }
        }
        for child in root.children { visit(child) }
        return best
    }

    // MARK: - Building

    /// Accessibility a SwiftUI modifier on an ancestor applies to every
    /// element inside it.
    struct Inherited {
        var label: String?
        var hint: String?
        var value: String?
        var identifier: String?
        var traits: UIAccessibilityTraits = []
    }

    struct Builder {
        let window: UIWindow
        let screen: CGRect

        init(window: UIWindow) {
            self.window = window
            self.screen = window.bounds
        }

        /// Appends the elements `view`'s subtree contributes to `out`.
        mutating func collect(
            _ view: UIView,
            _ inherited: Inherited,
            into out: inout [UIAutomationElement],
            inGroup: Bool
        ) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            // Host overlays that are not the app's (the screenshot status bar).
            if view is _UIScreenshotStatusBarView { return }
            let frame = view.convert(view.bounds, to: window)
            // Wholly beside the screen (an off-screen page of a pager): iOS
            // leaves it out. Above or below stays (scrolled-off rows are
            // elements without a centre).
            if view.bounds.width > 0,
               frame.maxX <= screen.minX + 0.5 || frame.minX >= screen.maxX - 0.5 { return }

            var inherited = inherited
            let note = view._automationAccessibility
            if let note {
                inherited.label = inherited.label ?? note.label
                inherited.hint = inherited.hint ?? note.hint
                inherited.value = inherited.value ?? note.value
                inherited.identifier = inherited.identifier ?? note.identifier
                inherited.traits.formUnion(note.addedTraits)
                if let children = note.children, children != .contain {
                    out.append(combinedElement(view, frame: frame, inherited, ignoreContent: children == .ignore))
                    return
                }
                if let role = note.role {
                    out.append(leaf(view, frame: frame, kind: kind(of: role), inherited))
                    return
                }
            } else if view.isAccessibilityElement {
                out.append(leaf(view, frame: frame, kind: .explicit, inherited))
                return
            } else if view.accessibilityElementsHidden {
                return
            }
            if note == nil, let kind = implicitKind(of: view) {
                out.append(leaf(view, frame: frame, kind: kind, inherited))
                return
            }
            if note == nil, let scrollView = view as? UIScrollView, !inGroup,
               scrollView.isScrollEnabled, !scrollView.isPagingEnabled {
                var children: [UIAutomationElement] = []
                for child in view.subviews { collect(child, inherited, into: &children, inGroup: true) }
                if view is UICollectionView { children = Self.geometricOrder(children) }
                out.append(UIAutomationElement(
                    role: "AXGroup", roleDescription: "Group", frame: frame, children: children))
                return
            }
            // iOS lists a navigation bar's elements before the content it
            // floats over, and the back button first within the bar.
            func first(_ view: UIView) -> Bool { view is UINavigationBar || view is _UINavigationBarBackButton }
            let children = view.subviews.filter(first) + view.subviews.filter { !first($0) }
            for child in children { collect(child, inherited, into: &out, inGroup: inGroup) }
        }

        /// iOS reads a UIKit collection view's elements top to bottom by
        /// their centres, then leading to trailing, not in view order.
        /// Only collection views: a SwiftUI scroll view's nested containers
        /// (a feed's story carousels) keep their own order, and a flat sort
        /// interleaved them (the root feed's tree).
        /// MEASURED iOS 27 simulator (stupid social's chats): a chat's
        /// collection view lists its date header before the cells (the
        /// guest added the supplementary view last), and inside a message
        /// cell the avatar (centre 164.67) before the bubble's time (169)
        /// and after the text (164.5), though the time label is the
        /// bubble's subview and the avatar the cell's.
        static func geometricOrder(_ elements: [UIAutomationElement]) -> [UIAutomationElement] {
            elements.enumerated().sorted { a, b in
                let (ya, yb) = (a.element.frame.midY, b.element.frame.midY)
                if abs(ya - yb) > 0.5 { return ya < yb }
                let (xa, xb) = (a.element.frame.minX, b.element.frame.minX)
                if abs(xa - xb) > 0.5 { return xa < xb }
                return a.offset < b.offset
            }.map(\.element)
        }

        enum Kind {
            case explicit
            case staticText
            case heading
            case button
            case backButton
            case barButton
            case image
            case textField
            case textView
            case toggle
            case slider
        }

        func kind(of role: _UIAutomationAccessibility.Role) -> Kind {
            switch role {
            case .image: return .image
            case .button: return .button
            case .staticText: return .staticText
            }
        }

        /// Views iOS makes elements without being asked.
        func implicitKind(of view: UIView) -> Kind? {
            switch view {
            case let label as UILabel:
                guard let text = label.text, !text.isEmpty else { return nil }
                if let bar = label.superview as? UINavigationBar,
                   label === bar.titleLabel || label === bar.largeTitleLabel {
                    return .heading
                }
                // A label that takes taps (user interaction on, an enabled
                // tap recognizer) is a button to iOS. MEASURED iOS 27
                // simulator: stupid social's chat text labels (links,
                // mentions) are Buttons, its sender-name and time labels
                // StaticText.
                if label.isUserInteractionEnabled,
                   label.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer && $0.isEnabled }) == true {
                    return .button
                }
                return .staticText
            case is _UINavigationBarBackButton: return .backButton
            case is _UIBarButtonItemView: return .barButton
            case is UITextField: return .textField
            case let textView as UITextView: return textView.isEditable ? .textView : .staticText
            case is UISwitch: return .toggle
            case is UISlider: return .slider
            case is UIButton: return .button
            case let control as UIControl:
                return control.accessibilityTraits.contains(.button) ? .button : nil
            default:
                return nil
            }
        }

        mutating func leaf(_ view: UIView, frame: CGRect, kind: Kind, _ inherited: Inherited) -> UIAutomationElement {
            var traits = view.accessibilityTraits.union(inherited.traits)
            var label = inherited.label ?? view.accessibilityLabel
            var value = inherited.value ?? view.accessibilityValue
            var identifier = inherited.identifier ?? appIdentifier(view)
            var labelIsSymbolDefault = false
            switch kind {
            case .explicit:
                if label == nil { (label, labelIsSymbolDefault) = combinedLabel(of: view) }
            case .staticText, .heading:
                if label == nil { label = (view as? UILabel)?.text ?? (view as? UITextView)?.text }
                if kind == .heading { traits.insert(.header) }
            case .button:
                traits.insert(.button)
                if label == nil {
                    if let title = (view as? UIButton)?.currentTitle {
                        label = title
                    } else if let text = (view as? UILabel)?.text {
                        label = text
                    } else {
                        (label, labelIsSymbolDefault) = combinedLabel(of: view)
                    }
                }
                // A UIKit button showing only a symbol image (its image view is
                // not an element of its own).
                if label == nil, let name = firstSymbolName(in: view),
                   let symbolLabel = _UISymbolAccessibility.label(forSymbolNamed: name) {
                    label = symbolLabel
                    labelIsSymbolDefault = true
                }
                // The symbol's name stays the identifier of a control labelled
                // only by it (iOS: `Button "Close" id=xmark`).
                if label == nil || labelIsSymbolDefault, identifier == nil {
                    identifier = firstSymbolName(in: view)
                }
            case .backButton:
                traits.insert(.button)
                if label == nil { label = (view as? _UINavigationBarBackButton)?.backLabel.text }
                if identifier == nil { identifier = "BackButton" }
            case .barButton:
                traits.insert(.button)
                if let item = (view as? _UIBarButtonItemView)?.item {
                    if label == nil { label = item.accessibilityLabel ?? item.title }
                    // UIKit's own labels for system items (iOS: "Search", "Done", …).
                    if label == nil, let system = item.systemItem {
                        label = "\(system)".prefix(1).uppercased() + "\(system)".dropFirst()
                    }
                    if identifier == nil { identifier = item.accessibilityIdentifier }
                    let symbol = item.image?._systemSymbolName ?? firstSymbolName(in: view)
                    if label == nil, let symbol,
                       let symbolLabel = _UISymbolAccessibility.label(forSymbolNamed: symbol) {
                        label = symbolLabel
                        labelIsSymbolDefault = true
                    }
                    if label == nil || labelIsSymbolDefault, identifier == nil { identifier = symbol }
                }
            case .image:
                traits.insert(.image)
                if label == nil, let name = view._automationAccessibility?.symbolName {
                    label = _UISymbolAccessibility.label(forSymbolNamed: name)
                    labelIsSymbolDefault = label != nil
                }
            case .textField:
                if value == nil, let field = view as? UITextField {
                    let text = field.text ?? ""
                    value = text.isEmpty ? field.placeholder : text
                }
            case .textView:
                // An empty text area has no value (iOS 27: the chat
                // composer is `TextArea "Message"`, no value).
                if value == nil, let text = (view as? UITextView)?.text, !text.isEmpty { value = text }
            case .toggle:
                if value == nil, let toggle = view as? UISwitch { value = toggle.isOn ? "1" : "0" }
            case .slider:
                if value == nil, let slider = view as? UISlider { value = "\(slider.value)" }
            }
            let (role, description) = Self.role(kind: kind, traits: traits)
            var element = UIAutomationElement(
                role: role, roleDescription: description,
                label: label, identifier: identifier, value: value, frame: frame)
            element.labelIsSymbolDefault = labelIsSymbolDefault
            return element
        }

        /// `.accessibilityElement(children: .combine / .ignore)`: one element.
        mutating func combinedElement(
            _ view: UIView, frame: CGRect, _ inherited: Inherited, ignoreContent: Bool
        ) -> UIAutomationElement {
            var parts: [UIAutomationElement] = []
            if !ignoreContent {
                for child in view.subviews { collect(child, Inherited(), into: &parts, inGroup: true) }
            }
            var flat: [UIAutomationElement] = []
            func flatten(_ element: UIAutomationElement) {
                flat.append(element)
                element.children.forEach(flatten)
            }
            parts.forEach(flatten)
            let composed = Self.composedLabel(flat)
            let label = inherited.label ?? composed.label
            var role = "AXGenericElement"
            var description = ""
            if inherited.traits.contains(.header) {
                (role, description) = ("AXHeading", "heading")
            } else if inherited.traits.contains(.button) || flat.contains(where: { $0.role == "AXButton" }) {
                (role, description) = ("AXButton", "button")
            } else if inherited.traits.contains(.image) {
                (role, description) = ("AXImage", "image")
            } else if !flat.isEmpty, flat.allSatisfy({ $0.role == "AXStaticText" }) {
                (role, description) = ("AXStaticText", "text")
            }
            var element = UIAutomationElement(
                role: role, roleDescription: description,
                label: label, identifier: inherited.identifier ?? appIdentifier(view),
                value: inherited.value, frame: frame)
            element.labelIsSymbolDefault = inherited.label == nil && composed.fromSymbols
            return element
        }

        /// A control's label as iOS composes it: its content's labels
        /// (text, labelled images, nested labels) joined with ", ";
        /// `fromSymbols` when only SF Symbol defaults made it.
        mutating func combinedLabel(of view: UIView) -> (label: String?, fromSymbols: Bool) {
            var parts: [UIAutomationElement] = []
            for child in view.subviews { collect(child, Inherited(), into: &parts, inGroup: true) }
            var flat: [UIAutomationElement] = []
            func visit(_ element: UIAutomationElement) {
                flat.append(element)
                element.children.forEach(visit)
            }
            parts.forEach(visit)
            return Self.composedLabel(flat)
        }

        /// Joins the labels of `elements` with ", ". SF Symbol default labels
        /// count only when nothing else is labelled — measured on iOS 27:
        /// SwiftUI `Button { HStack { Text("GitHub"); Spacer();
        /// Image(systemName: "arrow.up.forward.square") } }` is
        /// `Button "GitHub"`, `Button { Image(systemName: "xmark") }` is
        /// `Button "Close" id=xmark`.
        static func composedLabel(_ elements: [UIAutomationElement]) -> (label: String?, fromSymbols: Bool) {
            let labelled = elements.filter { ($0.label ?? "").isEmpty == false }
            let own = labelled.filter { !$0.labelIsSymbolDefault }
            let chosen = own.isEmpty ? labelled : own
            guard !chosen.isEmpty else { return (nil, false) }
            return (chosen.compactMap(\.label).joined(separator: ", "), own.isEmpty)
        }

        /// The SF Symbol an unlabelled image-only control draws, so an
        /// agent can still tell which icon it is.
        func firstSymbolName(in view: UIView) -> String? {
            if !view.isHidden, let note = view._automationAccessibility, note.role == .image,
               let identifier = note.identifier { return identifier }
            if !view.isHidden, let image = (view as? UIImageView)?.image, let name = image._systemSymbolName {
                return name
            }
            for child in view.subviews where !child.isHidden {
                if let name = firstSymbolName(in: child) { return name }
            }
            return nil
        }

        /// An identifier the app set; the frameworks' own structural
        /// identifiers ("SwiftUI.…", "OpenUIKit.…") are not reported.
        func appIdentifier(_ view: UIView) -> String? {
            guard let id = view.accessibilityIdentifier, !id.isEmpty,
                  !id.hasPrefix("SwiftUI."), !id.hasPrefix("OpenUIKit.") else { return nil }
            return id
        }

        static func role(kind: Kind, traits: UIAccessibilityTraits) -> (String, String) {
            if traits.contains(.header) { return ("AXHeading", "heading") }
            switch kind {
            case .textField: return ("AXTextField", "text field")
            case .textView: return ("AXTextArea", "text entry area")
            case .toggle: return ("AXSwitch", "switch")
            case .slider: return ("AXSlider", "slider")
            default: break
            }
            if traits.contains(.link) { return ("AXLink", "link") }
            if traits.contains(.button) { return ("AXButton", "button") }
            if traits.contains(.searchField) { return ("AXTextField", "search text field") }
            if traits.contains(.adjustable) { return ("AXSlider", "slider") }
            if traits.contains(.image) || kind == .image { return ("AXImage", "image") }
            if traits.contains(.staticText) || kind == .staticText { return ("AXStaticText", "text") }
            return ("AXGenericElement", "")
        }
    }

    // MARK: - Formatting

    /// "%.2f" without Foundation.
    static func fixed2(_ value: CGFloat) -> String {
        let hundredths = Int((Double(value) * 100).rounded())
        let sign = hundredths < 0 ? "-" : ""
        let magnitude = hundredths.magnitude
        let fraction = magnitude % 100
        return "\(sign)\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// A JSON number as Foundation prints a Double: integral values
    /// without a fraction.
    static func jsonNumber(_ value: CGFloat) -> String {
        let double = Double(value)
        if double.isFinite, double == double.rounded(), double.magnitude < 1e15 {
            return "\(Int(double))"
        }
        return "\(double)"
    }

    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += "\\/"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    static func writeJSON(_ element: UIAutomationElement, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent + 1)
        let close = String(repeating: "  ", count: indent)
        var fields: [String] = []
        if element.children.isEmpty {
            fields.append("\"children\" : [\n\n\(pad)]")
        } else {
            var children = "\"children\" : [\n"
            for (index, child) in element.children.enumerated() {
                children += pad + "  "
                writeJSON(child, indent: indent + 2, into: &children)
                children += index == element.children.count - 1 ? "\n" : ",\n"
            }
            fields.append(children + pad + "]")
        }
        let f = element.frame
        let inner = pad + "  "
        let leaf = inner + "  "
        fields.append(
            "\"frame\" : [\n\(inner)[\n\(leaf)\(jsonNumber(f.minX)),\n\(leaf)\(jsonNumber(f.minY))\n\(inner)],\n"
                + "\(inner)[\n\(leaf)\(jsonNumber(f.width)),\n\(leaf)\(jsonNumber(f.height))\n\(inner)]\n\(pad)]"
        )
        if let identifier = element.identifier { fields.append("\"identifier\" : \(jsonString(identifier))") }
        if let label = element.label { fields.append("\"label\" : \(jsonString(label))") }
        fields.append("\"role\" : \(jsonString(element.role))")
        if let description = element.roleDescription {
            fields.append("\"roleDescription\" : \(jsonString(description))")
        }
        if let title = element.title { fields.append("\"title\" : \(jsonString(title))") }
        if let value = element.value { fields.append("\"value\" : \(jsonString(value))") }
        out += "{\n" + fields.map { pad + $0 }.joined(separator: ",\n") + "\n" + close + "}"
    }
}
