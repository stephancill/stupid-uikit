// Constraints activated DURING a layout pass (after layoutIfNeeded's solve)
// are solved in that same pass. A SwiftUI host builds its
// UIViewControllerRepresentable controllers from layoutSubviews; stupid
// social's HomePager adds its page dots in viewDidLoad, pinned with
// `centerX` and `bottom == safeAreaLayoutGuide.bottom - 4` and sized by
// intrinsicContentSize. Before the fix they kept a zero frame: the solve
// had already run and the holder's setNeedsLayout was consumed by the same
// pass. iOS 27 simulator (iPhone 16e): the dots are at [178.67, 789, 33, 17]
// on a 390x844 screen with a 34 pt bottom safe area.

import XCTest
@testable import OpenUIKit

#if !os(Linux)
@MainActor
#endif
final class ConstraintsInstalledDuringLayoutTests: XCTestCase {
    private final class Pill: UIView {
        override var intrinsicContentSize: CGSize { CGSize(width: 33, height: 17) }
    }

    private final class Host: UIView {
        let content = UIView()
        let pill = Pill()
        private var built = false

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !built else { return }
            built = true
            content.frame = bounds
            addSubview(content)
            pill.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: content.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            ])
        }
    }

    func testConstraintsActivatedInLayoutSubviewsAreSolvedInTheSamePass() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        root._setSafeAreaInsets(UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0))
        let host = Host(frame: root.bounds)
        root.addSubview(host)
        root.layoutIfNeeded()
        XCTAssertEqual(host.pill.frame, CGRect(x: 179, y: 789, width: 33, height: 17))
        XCTAssertFalse(LayoutEngine.constraintsChangedSinceSolve)
    }
}
