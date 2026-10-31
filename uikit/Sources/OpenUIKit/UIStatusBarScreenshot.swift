// A status bar for screenshots, drawn over a window on request.
//
// OpenUIKit has no system status bar: apps see the configured device's
// safe area (OpenUIKitDeviceModel) but nothing is drawn in it. A host that
// compares renders with iOS Simulator screenshots asks for this overlay,
// which draws what `xcrun simctl status_bar override` / stupidsim's
// screenshot preset shows: a fixed time, full cellular bars, full Wi-Fi and
// a full battery (charging, as the simulator reports it).
//
// Geometry MEASURED from an iOS 27 iPhone 16e simulator screenshot (390 x
// 844 pt @3x, status bar preset, light appearance), in points:
//   time "09:41"  ink [42.33, 19.67] - [84.67, 32.33], semibold 17
//   cellular      4 bars 3.33 wide at x 285.33 + 5.33 n, bottom 32,
//                 heights 6.33 / 8.33 / 10.67 / 13
//   Wi-Fi         ink [310.67, 19] - [329, 32.67]
//   battery       body [335.67, 19.67, 25, 13] systemGreen, tip
//                 [361.33, 23.67, 2.33, 5], grey (178) charging bolt
// Horizontal positions are kept relative to the window's leading and
// trailing edges; other device families (Dynamic Island, home button) use
// the same layout centred in their top inset, which is an approximation.

@preconcurrency @MainActor
final class _UIScreenshotStatusBarView: UIView {
    let timeLabel = UILabel()

    init(frame: CGRect, time: String) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = nil
        accessibilityIdentifier = "OpenUIKit.ScreenshotStatusBar"
        timeLabel.text = time
        timeLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        timeLabel.textColor = .label
        addSubview(timeLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not decodable") }

    /// Vertical shift from the measured 47 pt notch bar to this bar.
    private var dy: CGFloat { (bounds.height - 47) / 2 }
    /// Trailing anchor: the measured layout's x minus 390 plus this width.
    private var trailing: CGFloat { bounds.width - 390 }

    override func layoutSubviews() {
        super.layoutSubviews()
        timeLabel.sizeToFit()
        let size = timeLabel.bounds.size
        // Ink centre x 63.5; digits sit on the baseline at y 32.33.
        let baseline = 32.33 + dy
        timeLabel.frame = CGRect(x: (63.5 - size.width / 2).rounded(),
                                 y: baseline - timeLabel.font.ascender,
                                 width: size.width, height: size.height)
    }

    override func draw(_ rect: CGRect) {
        let ink = UIColor.label
        let dx = trailing
        let dy = self.dy

        // Cellular: four rounded bars, all filled.
        let heights: [CGFloat] = [6.33, 8.33, 10.67, 13]
        for (i, h) in heights.enumerated() {
            let bar = CGRect(x: 285.33 + 5.33 * CGFloat(i) + dx, y: 32 - h + dy, width: 3.33, height: h)
            UIBezierPath(roundedRect: bar, cornerRadius: 1.1).fill(with: ink)
        }

        // Wi-Fi: a wedge and two round-capped arcs around one centre,
        // +/- 41 degrees about straight up.
        let centre = CGPoint(x: 319.83 + dx, y: 32.2 + dy)
        let half = 41 * CGFloat.pi / 180
        let up = -CGFloat.pi / 2
        let wedge = UIBezierPath()
        wedge.move(to: centre)
        wedge.addArc(withCenter: centre, radius: 4.6, startAngle: up - half, endAngle: up + half,
                     clockwise: true)
        wedge.close()
        wedge.fill(with: ink)
        for radius: CGFloat in [7.9, 11.9] {
            let arc = UIBezierPath()
            arc.addArc(withCenter: centre, radius: radius, startAngle: up - half, endAngle: up + half,
                       clockwise: true)
            arc.lineWidth = 2.6
            arc.lineCapStyle = .round
            ink.setStroke()
            arc.stroke()
        }

        // Battery: full green body, rounded tip, grey bolt with a white rim.
        let green = UIColor.systemGreen
        let body = CGRect(x: 335.67 + dx, y: 19.67 + dy, width: 25, height: 13)
        UIBezierPath(roundedRect: body, cornerRadius: 4.3).fill(with: green)
        let tip = UIBezierPath(roundedRect: CGRect(x: 361.33 + dx, y: 23.67 + dy, width: 2.33, height: 5),
                               byRoundingCorners: [.topRight, .bottomRight],
                               cornerRadii: CGSize(width: 2.33, height: 2.33))
        tip.fill(with: green)
        let bolt = UIBezierPath()
        let points: [(CGFloat, CGFloat)] = [
            (350.6, 19.8), (343.6, 26.6), (347.4, 26.6), (345.8, 32.6), (352.6, 24.8), (349.2, 24.8),
        ]
        for (i, p) in points.enumerated() {
            let point = CGPoint(x: p.0 + dx, y: p.1 + dy)
            if i == 0 { bolt.move(to: point) } else { bolt.addLine(to: point) }
        }
        bolt.close()
        bolt.lineWidth = 1.6
        bolt.lineJoinStyle = .round
        UIColor.white.setStroke()
        bolt.stroke()
        bolt.fill(with: UIColor(red: 178 / 255, green: 178 / 255, blue: 178 / 255, alpha: 1))
    }
}

extension UIWindow {
    /// Draws a screenshot-preset status bar (fixed `time`, full cellular,
    /// Wi-Fi and battery) over the top safe-area inset of this window, as
    /// the topmost subview. For hosts that compare renders with iOS
    /// Simulator screenshots; apps never see it in their own hierarchy
    /// unless a host installs it. Calling it again replaces the time.
    @discardableResult
    public func _installScreenshotStatusBar(time: String = "9:41") -> UIView {
        let height = max(safeAreaInsets.top, 20)
        let frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        if let existing = subviews.first(where: { $0 is _UIScreenshotStatusBarView })
            as? _UIScreenshotStatusBarView {
            existing.frame = frame
            existing.timeLabel.text = time
            bringSubviewToFront(existing)
            existing.setNeedsLayout()
            existing.setNeedsDisplay()
            return existing
        }
        let bar = _UIScreenshotStatusBarView(frame: frame, time: time)
        addSubview(bar)
        bar.layoutIfNeeded()
        return bar
    }
}
