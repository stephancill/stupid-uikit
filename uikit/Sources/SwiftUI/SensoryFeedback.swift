/// SwiftUI's `SensoryFeedback` (iOS 17): the haptic or audio feedback a
/// `sensoryFeedback` modifier plays when its trigger changes.
///
/// The portable host has no haptic engine and nothing to show for feedback:
/// on iOS it changes no pixels and no view, so the modifiers below install
/// nothing and leave the content's layout and rendering unchanged. The
/// trigger, condition and feedback closures are accepted and never called;
/// a host with an input loop and a haptics channel would evaluate them on
/// each trigger change (uikit/docs/APP_CATCHUP_APIS.md).
public struct SensoryFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case success, warning, error, selection, increase, decrease
        case start, stop, alignment, levelChange, pathComplete
        case impact(weight: Weight?, flexibility: Flexibility?, intensity: Double)
    }

    let kind: Kind

    public struct Weight: Equatable, Sendable {
        let value: Int
        public static let light = Weight(value: 0)
        public static let medium = Weight(value: 1)
        public static let heavy = Weight(value: 2)
    }

    public struct Flexibility: Equatable, Sendable {
        let value: Int
        public static let rigid = Flexibility(value: 0)
        public static let solid = Flexibility(value: 1)
        public static let soft = Flexibility(value: 2)
    }

    public static let success = SensoryFeedback(kind: .success)
    public static let warning = SensoryFeedback(kind: .warning)
    public static let error = SensoryFeedback(kind: .error)
    public static let selection = SensoryFeedback(kind: .selection)
    public static let increase = SensoryFeedback(kind: .increase)
    public static let decrease = SensoryFeedback(kind: .decrease)
    public static let start = SensoryFeedback(kind: .start)
    public static let stop = SensoryFeedback(kind: .stop)
    public static let alignment = SensoryFeedback(kind: .alignment)
    public static let levelChange = SensoryFeedback(kind: .levelChange)
    public static let pathComplete = SensoryFeedback(kind: .pathComplete)
    public static let impact = SensoryFeedback(kind: .impact(weight: nil, flexibility: nil, intensity: 1))

    public static func impact(weight: Weight = .medium, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(kind: .impact(weight: weight, flexibility: nil, intensity: intensity))
    }

    public static func impact(flexibility: Flexibility, intensity: Double = 1) -> SensoryFeedback {
        SensoryFeedback(kind: .impact(weight: nil, flexibility: flexibility, intensity: intensity))
    }
}

public extension _OpenView {
    func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T
    ) -> some _OpenView {
        _ = feedback
        _ = trigger
        return self
    }

    func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool
    ) -> some _OpenView {
        _ = feedback
        _ = trigger
        _ = condition
        return self
    }

    func sensoryFeedback<T: Equatable>(
        trigger: T,
        _ feedback: @escaping (_ oldValue: T, _ newValue: T) -> SensoryFeedback?
    ) -> some _OpenView {
        _ = trigger
        _ = feedback
        return self
    }
}
