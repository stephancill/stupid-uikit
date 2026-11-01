// SwiftUI S3: the list/navigation vocabulary used by Mozilla Focus's exact
// Licenses target. NavigationLink creates a fresh retained hosting graph for
// its destination and pushes it through the enclosing UIKit navigation
// controller; application source does not participate in that bridge.

import OpenUIKit

public struct _OpenList<Content: _OpenView>: _OpenView {
    public typealias Body = Never
    public let content: Content

    public init(@_OpenViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// SwiftUI's single-selection `List(selection:content:)` (ios-oss
    /// Library PaginatingList.swift:48). The list renders as the plain list;
    /// OpenUIKit's list rows have no selection state yet, so the binding is
    /// never written (no row reads as selected) — recorded in
    /// docs/KNOWN_GAPS.md.
    public init<SelectionValue: Hashable>(selection: _OpenBinding<SelectionValue?>?,
                                          @_OpenViewBuilder content: () -> Content) {
        _ = selection
        self.content = content()
    }

    /// `List(_:id:rowContent:)`: one row per element, like
    /// `List { ForEach(data, id: id, content: rowContent) }`.
    public init<Data, ID, RowContent>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @_OpenViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
    ) where Content == _OpenForEach<Data, ID, RowContent>,
            Data: RandomAccessCollection, ID: Hashable, RowContent: _OpenView {
        content = _OpenForEach(data, id: id, content: rowContent)
    }

    /// `List(_:rowContent:)` over Identifiable elements.
    public init<Data, RowContent>(
        _ data: Data,
        @_OpenViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
    ) where Content == _OpenForEach<Data, Data.Element.ID, RowContent>,
            Data: RandomAccessCollection, Data.Element: Identifiable, RowContent: _OpenView {
        content = _OpenForEach(data, id: \.id, content: rowContent)
    }

    public func _makeOpenUIKitNode() -> _OpenViewNode {
        // Retained at the List's own graph identity, before its content.
        let scrollState = _OpenGraphContext.lazyStackState()
        let node = _OpenViewNode(
            .list(
                rows: _openFlattenGroup(
                    _OpenGraphContext.withStructuralScope(.listContent) {
                        content._makeOpenUIKitNode()
                    }
                )
            )
        )
        node.retainedScrollState = scrollState
        return node
    }
}

public struct _OpenNavigationLink<Destination: _OpenView, Label: _OpenView>: _OpenView {
    public typealias Body = Never
    /// Nil for a value link (`Destination == Never`).
    let destination: Destination?
    /// `NavigationLink(value:)`: appended to the enclosing NavigationStack's
    /// path when the link is followed.
    let value: AnyHashable?
    let isValueLink: Bool
    /// `NavigationLink(destination:isActive:label:)`: the binding pushes and pops the destination.
    var isActive: Binding<Bool>?
    public let label: Label

    public init(
        @_OpenViewBuilder destination: () -> Destination,
        @_OpenViewBuilder label: () -> Label
    ) {
        self.destination = destination()
        self.label = label()
        value = nil
        isValueLink = false
    }

    public init(
        destination: Destination,
        @_OpenViewBuilder label: () -> Label
    ) {
        self.destination = destination
        self.label = label()
        value = nil
        isValueLink = false
    }

    /// iOS 16-deprecated `NavigationLink(destination:isActive:label:)`: the label is a link row whose
    /// tap sets the binding, and the binding presents the destination as
    /// `navigationDestination(isPresented:)` does, so setting it in code pushes too.
    public init(
        destination: Destination,
        isActive: Binding<Bool>,
        @_OpenViewBuilder label: () -> Label
    ) {
        self.destination = destination
        self.label = label()
        value = nil
        isValueLink = false
        self.isActive = isActive
    }

    public func _makeOpenUIKitNode() -> _OpenViewNode {
        let labelNode = _OpenGraphContext.withStructuralScope(.navigationLinkLabel) {
            label._makeOpenUIKitNode()
        }
        if let isActive, let destination {
            let row = _OpenViewNode(.modified(
                _OpenViewNode(.navigationLink(label: labelNode, target: .inert)),
                .gesture(_OpenGestureNode(kind: .tap({ isActive.wrappedValue = true })))))
            return _OpenPrebuiltNodeView(node: row)
                .navigationDestination(isPresented: isActive) { destination }
                ._makeOpenUIKitNode()
        }
        if isValueLink {
            // A nil value makes an inert link, as in SwiftUI (the label
            // still renders as a link row).
            return _OpenViewNode(
                .navigationLink(label: labelNode, target: value.map { .value($0) } ?? .inert)
            )
        }
        guard let destination else {
            preconditionFailure("SwiftUI.NavigationLink has neither a destination nor a value")
        }
        return _OpenViewNode(
            .navigationLink(
                label: labelNode,
                target: .destination {
                    _OpenUIHostingController(rootView: destination)
                }
            )
        )
    }
}

/// `NavigationLink(value:)`: following the link appends the value to the
/// enclosing NavigationStack's path; the stack's `navigationDestination(for:)`
/// registration for the value's type builds the destination.
public extension _OpenNavigationLink where Destination == Never {
    init<P: Hashable>(value: P?, @_OpenViewBuilder label: () -> Label) {
        destination = nil
        self.value = value.map(AnyHashable.init)
        isValueLink = true
        self.label = label()
    }
}

public extension _OpenNavigationLink where Destination == Never, Label == _OpenText {
    init<P: Hashable>(_ titleKey: String, value: P?) {
        self.init(value: value) { _OpenText(titleKey) }
    }
}

public typealias List<Content> = _OpenList<Content> where Content: _OpenView
public typealias NavigationLink<Destination, Label> =
    _OpenNavigationLink<Destination, Label>
    where Destination: _OpenView, Label: _OpenView

/// A view whose node is already built (a NavigationLink row composed with modifiers).
struct _OpenPrebuiltNodeView: _OpenView {
    typealias Body = Never
    let node: _OpenViewNode
    func _makeOpenUIKitNode() -> _OpenViewNode { node }
}
