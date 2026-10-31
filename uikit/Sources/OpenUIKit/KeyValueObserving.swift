// Typed key-value observation of OpenUIKit properties.
//
// The guest has no automatic Objective-C KVO. The Foundation facade
// (full/foundation/Progress.swift) implements `NSObject.observe(_:options:)`
// with explicit change brackets, but it is compiled after OpenUIKit (it imports
// OpenUIKit), so OpenUIKit cannot call it. Instead OpenUIKit names the
// properties it reports and calls `didChange`, which the facade installs the
// first time anything is observed.
//
// Apps rely on this for scroll geometry: stupid social's home pager observes
// its page scroll view's `contentOffset` to move the page dots, and its chat
// screen observes the collection view's `contentSize` to keep short
// conversations at the bottom. UIKit posts both through KVO on iOS.

/// A class whose OpenUIKit-maintained properties report changes.
@preconcurrency @MainActor
public protocol _OpenUIKitKeyValueObservable: AnyObject {
    /// The property `keyPath` names when this class reports it, else nil.
    /// Called on the static type the observer used (`Self` is that type), so
    /// `\Self.contentOffset` compares equal to the observer's key path.
    static func _openUIKitObservedProperty(for keyPath: AnyKeyPath) -> String?
}

public enum _OpenUIKitKeyValueObserving {
    /// Installed by the Foundation facade: (object, property, old, new).
    @MainActor public static var didChange: ((AnyObject, String, Any, Any) -> Void)?
}

extension UIScrollView: _OpenUIKitKeyValueObservable {}

public extension _OpenUIKitKeyValueObservable where Self: UIScrollView {
    static func _openUIKitObservedProperty(for keyPath: AnyKeyPath) -> String? {
        if keyPath == \Self.contentOffset as AnyKeyPath { return "contentOffset" }
        if keyPath == \Self.contentSize as AnyKeyPath { return "contentSize" }
        return nil
    }
}
