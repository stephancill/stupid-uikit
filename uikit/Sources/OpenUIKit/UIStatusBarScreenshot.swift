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
//
// Appearance, as iOS resolves it: the topmost controller that covers the
// screen (the root, or a `.fullScreen` / `.overFullScreen` presentation)
// supplies `preferredStatusBarStyle`. `.lightContent` draws white ink,
// `.darkContent` black. `.default` adapts to what is under the bar
// (UIStatusBarStyle.default: "automatically chooses light or dark content
// to maintain contrast"): `UIRenderer.render` of the window first renders
// it without the bar at a quarter of the scale and takes the mean
// luminance of the bar's strip; below 0.5 the bar is light. iOS's own
// sampling algorithm is not public; on uniform backgrounds (a white app
// screen, a black full-screen cover) both agree.
// MEASURED (iOS 27 iPhone 16e, story viewer over black): light ink is
// white, the charging bolt is grey 128 with a black rim (178 with a white
// rim on light), the battery stays systemGreen.

@preconcurrency @MainActor
final class _UIScreenshotStatusBarView: UIView {
    let timeLabel = UILabel()
    /// Light ink (white glyphs) over dark content; set before each capture.
    var lightContent = false {
        didSet {
            guard lightContent != oldValue else { return }
            timeLabel.textColor = ink
            setNeedsDisplay()
        }
    }

    private var ink: UIColor { lightContent ? .white : .black }

    init(frame: CGRect, time: String) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = nil
        accessibilityIdentifier = "OpenUIKit.ScreenshotStatusBar"
        timeLabel.text = time
        timeLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        timeLabel.textColor = ink
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
        let ink = self.ink
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
        (lightContent ? UIColor.black : UIColor.white).setStroke()
        bolt.stroke()
        let boltGrey: CGFloat = lightContent ? 128 / 255 : 178 / 255
        bolt.fill(with: UIColor(red: boltGrey, green: boltGrey, blue: boltGrey, alpha: 1))
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

extension UIWindow {
    /// Resolves the screenshot status bar's appearance for the frame about
    /// to be captured (see the file header). `render` draws the window; it
    /// is the caller's compositor, called with the bar hidden.
    func _resolveScreenshotStatusBarAppearance(render: (UIView, CGFloat) -> Bitmap) {
        guard let bar = subviews.last(where: { $0 is _UIScreenshotStatusBarView })
            as? _UIScreenshotStatusBarView, !bar.isHidden else { return }
        // The system status bar is above everything the app shows, including
        // presentations, which OpenUIKit adds to the window after the bar.
        if subviews.last !== bar { bringSubviewToFront(bar) }
        var controller = rootViewController
        while let presented = controller?.presentedViewController,
              presented._resolvedPresentationStyle == .fullScreen
                || presented._resolvedPresentationStyle == .overFullScreen {
            controller = presented
        }
        switch controller?.preferredStatusBarStyle ?? .default {
        case .lightContent: bar.lightContent = true
        case .darkContent: bar.lightContent = false
        case .default:
            let sampleScale: CGFloat = 0.25
            bar.isHidden = true
            let bitmap = render(self, sampleScale)
            bar.isHidden = false
            let rows = Swift.min(bitmap.height, Swift.max(1, Int((bar.frame.maxY * sampleScale).rounded())))
            var total: Double = 0
            var count = 0
            for y in 0..<rows {
                for x in 0..<bitmap.width {
                    let o = (y * bitmap.width + x) * 4
                    let a = Double(bitmap.pixels[o + 3]) / 255
                    // Over the window's white backing, as the screen shows it.
                    func channel(_ i: Int) -> Double { Double(bitmap.pixels[o + i]) / 255 * a + (1 - a) }
                    total += 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2)
                    count += 1
                }
            }
            bar.lightContent = count > 0 && total / Double(count) < 0.5
        }
        bar.layoutIfNeeded()
    }
}
