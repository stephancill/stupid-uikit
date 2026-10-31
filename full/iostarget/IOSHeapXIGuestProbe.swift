// Heap-object extra inhabitants on the x86_64 iOS-simulator guest
// (full/shims/swiftcorepatch.c, docs/agent_reports/ios-heap-extra-inhabitants.md).
//
// Compiled by full/scripts/build_full.sh only for an iOS-simulator TARGET and
// run under machorun by full/iostarget/heap_xi_guest.sh. Each case moves a
// second-level extra inhabitant (`C??`'s `.none`, `[C?]`'s nil element seen
// through `IndexingIterator.next()`) between this file's simulator-compiled
// code and the macOS-built runtime's value witnesses. Before the fix the
// runtime wrote 0x2 where this code expects 0x1, which this code read as a
// non-nil reference and retained (a fault in swift_retain/objc_retain).
// Self-checking: every line is PASS or FAIL, then the verdict.
#if !os(iOS)
#error("IOSHeapXIGuestProbe must be compiled for an iOS triple")
#endif

final class Box {
    let value: Int
    init(_ value: Int) { self.value = value }
}

final class Other: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "Other" }
    var debugDescription: String { "Other" }
}

struct OneReference {
    let box: Box
}

var failures = 0

func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { failures += 1 }
}

/// Unspecialised generic code: the runtime's value witnesses build and read
/// the `T??` values.
@inline(never)
func elements<T>(_ values: [T?]) -> [String] {
    var out: [String] = []
    for value in values {
        out.append(value == nil ? "nil" : "some")
    }
    return out
}

@inline(never)
func wrapNone<T>(_ type: T.Type) -> T?? { .none }

@inline(never)
func wrapSomeNone<T>(_ type: T.Type) -> T?? { .some(.none) }

@inline(never)
func lookup<K: Hashable, V>(_ dictionary: [K: V?], _ key: K) -> V?? { dictionary[key] }

func describe<T>(_ value: T??) -> String {
    switch value {
    case .none: return "none"
    case .some(.none): return "some(none)"
    case .some(.some): return "some(some)"
    }
}

func runProbe() {
    // [C?] iterated through IndexingIterator (OpenUIKit's transition
    // coordinator crashed here on the first navigation push).
    check(elements([Box(1), nil, Box(3)]) == ["some", "nil", "some"], "[Box?] iteration")
    var seen: [Int] = []
    for box in [Box(1), nil, Box(3)] { seen.append(box?.value ?? 0) }
    check(seen == [1, 0, 3], "for-in over [Box?]: \(seen)")

    // Dictionary<K, V?> lookups return V?? (stupid social's story viewer
    // crashed reading a [String: URL?]; URL-like structs with one reference
    // share Builtin.UnknownObject's witnesses).
    let boxes: [String: Box?] = ["nil": nil, "one": Box(1)]
    check(describe(lookup(boxes, "missing")) == "none", "[String: Box?] missing key is none")
    check(describe(lookup(boxes, "nil")) == "some(none)", "[String: Box?] nil value is some(none)")
    check(describe(lookup(boxes, "one")) == "some(some)", "[String: Box?] value is some(some)")
    let structs: [String: OneReference?] = ["nil": nil]
    check(describe(lookup(structs, "missing")) == "none", "[String: OneReference?] missing key is none")
    check(describe(lookup(structs, "nil")) == "some(none)", "[String: OneReference?] nil value is some(none)")

    // Each family of patched value witnesses, built generically, read here.
    check(describe(wrapNone(Box.self)) == "none" && describe(wrapSomeNone(Box.self)) == "some(none)",
          "native class")
    check(describe(wrapNone(AnyObject.self)) == "none" && describe(wrapSomeNone(AnyObject.self)) == "some(none)",
          "AnyObject")
    check(describe(wrapNone(Box.Type.self)) == "none" && describe(wrapSomeNone(Box.Type.self)) == "some(none)",
          "metatype")
    check(describe(wrapNone(Any.self)) == "none" && describe(wrapSomeNone(Any.self)) == "some(none)",
          "Any")
    check(describe(wrapNone((any CustomStringConvertible & AnyObject).self)) == "none"
          && describe(wrapSomeNone((any CustomStringConvertible & AnyObject).self)) == "some(none)",
          "class-bound existential")
    check(describe(wrapNone((any CustomStringConvertible).Type.self)) == "none"
          && describe(wrapSomeNone((any CustomStringConvertible).Type.self)) == "some(none)",
          "existential metatype")
    check(describe(wrapNone(OneReference.self)) == "none" && describe(wrapSomeNone(OneReference.self)) == "some(none)",
          "one-reference struct")

    // And the other direction: built here, read by generic code.
    let built: Box?? = .some(.none)
    let viaGeneric: [Box??] = [built, .none, .some(Box(2))]
    check(viaGeneric.map { describe($0) } == ["some(none)", "none", "some(some)"], "[Box??] read generically")
    let any: [Any?] = [nil, Other(), 1]
    check(elements(any) == ["nil", "some", "some"], "[Any?] iteration")

    print(failures == 0 ? "IOS_HEAP_XI_GUEST_PROBE=PASS" : "IOS_HEAP_XI_GUEST_PROBE=FAIL (\(failures))")
}

@main
struct IOSHeapXIGuestProbeMain {
    static func main() { runProbe() }
}
