// Native gate for the framework APIs stupid social addc1744 needed
// (docs/APP_CATCHUP_APIS.md): UIFont.monospacedDigitSystemFont, UICollectionView
// .indexPathsForVisibleSupplementaryElements, CALayer.insertSublayer(_:above:/below:),
// accessibilityAction(named: String), Animation's named springs,
// sensoryFeedback, searchable(text:isPresented:), onSubmit(of: .search), and
// Combine's Publishers.MergeMany (full/combine/Publishers.MergeMany.swift,
// compiled here from the same file the guest's Combine module builds).
//
//   swift run appcatchupprobe     exits 0 when every check passes
import Foundation
@testable import OpenUIKit
@testable import SwiftUI
import OpenCombine

@MainActor enum Probe {
    static var failures = 0
}

@MainActor func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { Probe.failures += 1 }
}

@MainActor func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
    if let match = view as? T { return match }
    for s in view.subviews { if let f = find(type, in: s) { return f } }
    return nil
}

final class HeaderSource: NSObject, UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 10 }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
    }
}

final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor func run() {
    // 1. UIFont.monospacedDigitSystemFont: a distinct system font, same size,
    //    weight and (documented gap) proportional metrics.
    let digits = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    let system = UIFont.systemFont(ofSize: 12)
    check(digits.pointSize == 12 && digits.weight == .regular && digits.design == .default,
          "monospacedDigit font keeps size, weight and the default design")
    check(digits != system, "monospacedDigit font is not the plain system font")
    check(digits == UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
          "monospacedDigit fonts of the same size and weight are equal")
    check(digits.withSize(17) == UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular),
          "withSize keeps monospaced digits")
    check(digits.lineHeight == system.lineHeight && digits.ascender == system.ascender,
          "monospacedDigit font has the system font's vertical metrics")

    // 2. indexPathsForVisibleSupplementaryElements(ofKind:).
    let layout = UICollectionViewFlowLayout()
    layout.itemSize = CGSize(width: 300, height: 50)
    layout.headerReferenceSize = CGSize(width: 300, height: 30)
    layout.minimumLineSpacing = 0
    let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: layout)
    let source = HeaderSource()
    collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
    let header = UICollectionView.elementKindSectionHeader
    collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: header, withReuseIdentifier: "header")
    collection.dataSource = source
    collection.layoutIfNeeded()
    let paths = collection.indexPathsForVisibleSupplementaryElements(ofKind: header)
    let viewPaths = collection.visibleSupplementaryViews(ofKind: header).compactMap { view in
        paths.first { collection.supplementaryView(forElementKind: header, at: $0) === view }
    }
    // Sections are 30 + 150 = 180 pt: headers of sections 0, 1 and 2 are in 400 pt.
    check(paths == [IndexPath(item: 0, section: 0), IndexPath(item: 0, section: 1), IndexPath(item: 0, section: 2)],
          "visible header index paths in 400 pt: \(paths)")
    check(viewPaths.count == paths.count, "each index path names a visible header view")
    check(collection.indexPathsForVisibleSupplementaryElements(ofKind: "badge").isEmpty, "no views of another kind")
    collection.contentOffset = CGPoint(x: 0, y: 720)
    collection.layoutIfNeeded()
    let scrolled = collection.indexPathsForVisibleSupplementaryElements(ofKind: header)
    check(scrolled.first == IndexPath(item: 0, section: 4), "after scrolling 720 pt the first visible header is section 4: \(scrolled)")

    // 3. Named springs map onto spring(response:dampingFraction:).
    check(Animation.snappy == .spring(response: 0.5, dampingFraction: 0.85), "snappy is bounce 0.15 at 0.5 s")
    check(Animation.smooth == .spring(response: 0.5, dampingFraction: 1), "smooth is bounce 0")
    check(Animation.bouncy == .spring(response: 0.5, dampingFraction: 0.7), "bouncy is bounce 0.3")
    check(Animation.snappy(duration: 0.3, extraBounce: 0.1) == .spring(response: 0.3, dampingFraction: 0.75),
          "snappy(duration:extraBounce:)")
    check(Animation.spring(duration: 0.4, bounce: 0.2) == .spring(response: 0.4, dampingFraction: 0.8),
          "spring(duration:bounce:)")

    // 4. sensoryFeedback changes no layout.
    func textFrame(_ view: some View) -> CGRect {
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        host.view.layoutIfNeeded()
        guard let label = find(UILabel.self, in: host.view) else { return .null }
        return label.convert(label.bounds, to: host.view)
    }
    let plain = textFrame(Text("Feedback"))
    check(plain != .null, "plain text placed")
    check(textFrame(Text("Feedback").sensoryFeedback(.impact, trigger: 1) { _, new in new > 0 }) == plain,
          "sensoryFeedback(_:trigger:condition:) leaves layout unchanged")
    check(textFrame(Text("Feedback").sensoryFeedback(.selection, trigger: true)) == plain,
          "sensoryFeedback(_:trigger:) leaves layout unchanged")
    check(textFrame(Text("Feedback").sensoryFeedback(trigger: 0) { _, _ in .impact(weight: .light) }) == plain,
          "sensoryFeedback(trigger:_:) leaves layout unchanged")

    // 5. searchable(text:isPresented:) and onSubmit(of: .search).
    let text = Box(""), presented = Box(true), searched = Box(0), submittedText = Box(0)
    let search = Color.clear
        .searchable(text: Binding(get: { text.value }, set: { text.value = $0 }),
                    isPresented: Binding(get: { presented.value }, set: { presented.value = $0 }),
                    prompt: "Search Messages")
        .onSubmit(of: .search) { searched.value += 1 }
        .onSubmit { submittedText.value += 1 }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
    let host = UIHostingController(rootView: search)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    guard let bar = find(UISearchBar.self, in: host.view) else {
        check(false, "searchable installed no search bar")
        return
    }
    check(bar.placeholder == "Search Messages", "search bar prompt")
    check(bar.showsCancelButton, "isPresented == true shows the cancel button")
    check(bar.searchTextField.isFirstResponder, "isPresented == true focuses the field")
    bar.delegate?.searchBarSearchButtonClicked(bar)
    check(searched.value == 1, "the search button runs onSubmit(of: .search)")
    check(submittedText.value == 0, "the search button does not run onSubmit(of: .text)")
    bar.delegate?.searchBarCancelButtonClicked(bar)
    check(presented.value == false, "cancel writes isPresented = false")
    check(!bar.searchTextField.isFirstResponder, "cancel resigns the field")
    bar.delegate?.searchBarTextDidBeginEditing(bar)
    check(presented.value == true, "beginning to edit writes isPresented = true")

    // 6. Publishers.MergeMany.
    let a = PassthroughSubject<Int, Never>(), b = PassthroughSubject<Int, Never>(), c = PassthroughSubject<Int, Never>()
    var received: [Int] = []
    var finished = false
    let merged = Publishers.MergeMany(a, b, c).sink(receiveCompletion: { _ in finished = true }) { received.append($0) }
    a.send(1); b.send(2); c.send(3); a.send(4)
    check(received == [1, 2, 3, 4], "MergeMany forwards every upstream in arrival order: \(received)")
    a.send(completion: .finished); b.send(completion: .finished)
    check(!finished, "MergeMany waits for every upstream to finish")
    c.send(5)
    c.send(completion: .finished)
    check(finished && received == [1, 2, 3, 4, 5], "MergeMany finishes after the last upstream")
    withExtendedLifetime(merged) {}

    struct Failure: Error {}
    let x = PassthroughSubject<Int, Failure>(), y = PassthroughSubject<Int, Failure>()
    var failed = false
    var afterFailure: [Int] = []
    let failing = Publishers.MergeMany([x, y]).sink(receiveCompletion: { completion in
        if case .failure = completion { failed = true }
    }) { afterFailure.append($0) }
    x.send(completion: .failure(Failure()))
    y.send(9)
    check(failed && afterFailure.isEmpty, "MergeMany fails on the first failure and drops later values")
    withExtendedLifetime(failing) {}

    // Demand: a subscriber asking for two values gets exactly two, the rest
    // wait until it asks again.
    final class Limited: Subscriber {
        typealias Input = Int
        typealias Failure = Never
        var values: [Int] = []
        var subscription: Subscription?
        func receive(subscription: Subscription) {
            self.subscription = subscription
            subscription.request(.max(2))
        }
        func receive(_ input: Int) -> Subscribers.Demand {
            values.append(input)
            return .none
        }
        func receive(completion: Subscribers.Completion<Never>) {}
    }
    let limited = Limited()
    Publishers.MergeMany([1, 2, 3].publisher, [10, 20].publisher).subscribe(limited)
    check(limited.values.count == 2, "MergeMany honours a demand of 2: \(limited.values)")
    limited.subscription?.request(.max(10))
    check(Set(limited.values) == [1, 2, 3, 10, 20] && limited.values.count == 5,
          "MergeMany delivers the rest on more demand: \(limited.values)")

    var empty = false
    let none = Publishers.MergeMany([PassthroughSubject<Int, Never>]()).sink(receiveCompletion: { _ in empty = true }) { _ in }
    check(empty, "MergeMany of no publishers finishes at once")
    withExtendedLifetime((none, window, host)) {}

    // 7. CALayer.insertSublayer(_:above:) / (_:below:) among explicit sublayers.
    let parent = CALayer(), first = CALayer(), second = CALayer(), above = CALayer(), below = CALayer()
    parent.addSublayer(first)
    parent.addSublayer(second)
    parent.insertSublayer(above, above: first)
    parent.insertSublayer(below, below: first)
    check(parent.sublayers.map { $0.map(ObjectIdentifier.init) } == [below, first, above, second].map(ObjectIdentifier.init),
          "insertSublayer above/below orders next to the sibling")
    parent.insertSublayer(second, below: below)
    check(parent.sublayers?.first === second && parent.sublayers?.count == 4, "re-inserting a sublayer moves it")

    // 8. accessibilityAction(named:) takes a string as well as a Text.
    let named = Text("Row").accessibilityAction(named: "Search Messages") {}
    let variable: Substring = "Search"
    let fromString = Text("Row").accessibilityAction(named: variable) {}
    check(textFrame(named) == textFrame(Text("Row")) && textFrame(fromString) == textFrame(Text("Row")),
          "accessibilityAction(named:) with a string literal and a StringProtocol value")
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "APP_CATCHUP_PROBE=PASS" : "APP_CATCHUP_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
