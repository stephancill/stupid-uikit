// Native gate for SwiftUI text-style line spacing (docs/SWIFTUI_TEXT_METRICS.md).
//
//   swift run swiftuitextmetricsprobe     exits 0 when every check passes
//
// Drives UIHostingController directly (SwiftUITests cannot host @MainActor
// XCTest methods on Linux; see swiftuinavchromeprobe) and reads the frames of
// the labels SwiftUI Text builds.
import Foundation
import OpenCoreGraphics
@testable import OpenUIKit
@testable import SwiftUI

@MainActor enum Probe {
    static var failures = 0
}

@MainActor func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { Probe.failures += 1 }
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

let long = "Love this — finally a feed I can open without getting lost. Shipping! And then some more words."
let short = "Do you have"

@MainActor let badge = UIImage(bitmap: Bitmap(width: 14, height: 14))

struct Column: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(long).font(.subheadline).lineLimit(2)
            Text(short).font(.subheadline).lineLimit(2)
            Text("B" + long).font(.body).lineLimit(2)
            Text("C" + long).font(.body.weight(.bold)).lineLimit(2)
            Text("D" + long).font(.headline).lineLimit(2)
            Text("E" + long).font(.system(size: 15)).lineLimit(2)
            Text("F" + long).font(.subheadline.italic()).lineLimit(2)
            Text("\(Text("G").bold()) \(Text(long))").font(.body).lineLimit(2)
            Text("\(Text("H").bold()) \(Text(long))").font(.subheadline).lineLimit(2)
            Text("I" + long + " " + long).font(.footnote).lineLimit(3)
            // A 14 pt bitmap badge lowered 1 pt, as stupid social's headlines.
            Text("\(Text(Image(uiImage: badge)).baselineOffset(-1)) \(Text("x").bold()) replied")
            Text("\(Text(Image(uiImage: badge))) y replied")
        }
        .frame(width: 290, alignment: .leading)
    }
}

@MainActor func labels(in view: UIView) -> [UILabel] {
    var out: [UILabel] = []
    if let l = view as? UILabel { out.append(l) }
    for s in view.subviews { out += labels(in: s) }
    return out
}

@MainActor var keepAlive: [AnyObject] = []

/// The view hosted in an iPhone 16e window, so labels take the window's
/// display scale (3) as on the device.
@MainActor func hosted(_ view: some View) -> UIView {
    let host = UIHostingController(rootView: view)
    let window = UIWindow(windowScene: UIWindowScene())
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.isHidden = false
    host.view.frame = window.bounds
    window.layoutIfNeeded()
    host.view.layoutIfNeeded()
    keepAlive.append(host)
    keepAlive.append(window)
    return host.view
}

/// Label scale of each styled (attributed) label: OpenUIKit lays attributed
/// text out on the label's trait scale (2 outside a scaled window here) and
/// plain text on the screen's (3); the guest render runs both at 2.
@MainActor var styledScale: [String: CGFloat] = [:]

func px(_ raw: CGFloat, _ scale: CGFloat) -> CGFloat { (raw * scale).rounded(.up) / scale }

@MainActor func heights() -> [String: CGFloat] {
    var out: [String: CGFloat] = [:]
    for l in labels(in: hosted(Column())) {
        guard let t = l.text, let first = t.unicodeScalars.first else { continue }
        let key = t == short ? "short" : (t == long ? "long"
            : first.value == 0xFFFC ? String(t.unicodeScalars.dropFirst(2).first!) : String(first))
        out[key] = l.frame.height
        if l.attributedText != nil { styledScale[key] = l.layoutScale }
    }
    return out
}

@MainActor func run() {
    OpenUIKitRuntime.configureDevice(.iPhone16e)
    check(UIScreen.main.scale == 3, "iPhone 16e scale 3")

    // 1. Fonts: SwiftUI text styles carry the style's line spacing on iOS.
    OpenUIKitRuntime.systemFontCut = .iOS
    let sub = Font.subheadline.resolve(weight: nil)
    check(near(sub.lineHeight + sub.leading, 20), "subheadline lineHeight + leading = 20: \(sub.lineHeight + sub.leading)")
    let body = Font.body.resolve(weight: nil)
    check(near(body.lineHeight + body.leading, 22), "body = 22: \(body.lineHeight + body.leading)")
    let bold = Font.body.weight(.bold).resolve(weight: nil)
    check(bold.weight == .bold && near(bold.lineHeight + bold.leading, 22), "body.weight(.bold) keeps body spacing")
    let override = Font.subheadline.resolve(weight: .semibold)
    check(near(override.lineHeight + override.leading, 20), "fontWeight override keeps subheadline spacing")
    let fixed = Font.system(size: 15).resolve(weight: nil)
    check(fixed.leading == 0, "system(size:) has no text-style leading: \(fixed.leading)")
    let styled = Font.system(.subheadline, design: .default, weight: .bold).resolve(weight: nil)
    check(near(styled.lineHeight + styled.leading, 20), "system(.subheadline, weight:) keeps spacing")

    // 2. Text heights on the iOS cut (iPhone 16e, 3x).
    //    iOS 27.0 simulator: 2-line .subheadline Text 38, 1-line 18.
    let ios = heights()
    check(near(ios["long"] ?? 0, 38), "2-line subheadline Text is 38: \(ios["long"] ?? 0)")
    check(near(ios["short"] ?? 0, 18), "1-line subheadline Text is 18: \(ios["short"] ?? 0)")
    // body: ceil_3x(2 x 20.287 + 1.713) = 42.333
    check(near(ios["B"] ?? 0, 42.333333333333336) , "2-line body Text is 42.333: \(ios["B"] ?? 0)")
    check(near(ios["C"] ?? 0, 42.333333333333336), "2-line bold body Text is 42.333: \(ios["C"] ?? 0)")
    check(near(ios["D"] ?? 0, 42.333333333333336), "2-line headline Text is 42.333: \(ios["D"] ?? 0)")
    check(near(ios["E"] ?? 0, 36), "2-line system(size: 15) Text stays 36: \(ios["E"] ?? 0)")
    check(near(ios["F"] ?? 0, 38), "2-line italic subheadline Text is 38: \(ios["F"] ?? 0)")
    // Styled (attributed) Text takes the same leading between lines.
    let g = px(2 * 20.287109375 + (22 - 20.287109375), styledScale["G"] ?? 0)
    check(near(ios["G"] ?? 0, g), "2-line styled body Text is \(g): \(ios["G"] ?? 0)")
    check(near(ios["H"] ?? 0, 38), "2-line styled subheadline Text is 38: \(ios["H"] ?? 0)")
    // footnote: 3 lines, 15.514 x 3 + 2 x 2.486 = 51.514 -> 51.667
    check(near(ios["I"] ?? 0, 51.666666666666664), "3-line footnote Text is 51.667: \(ios["I"] ?? 0)")

    // Inline image lowered by baselineOffset(-1): the line grows by the
    // offset (iOS 27.0 simulator: stupid social's headline is 21.333).
    // At 3x 21.333 / 20.333 (the simulator's numbers); 21.5 / 20.5 at 2x.
    let lowered = px(16.1865234375 + 4.1005859375 + 1, styledScale["x"] ?? 0)
    let onBaseline = px(16.1865234375 + 4.1005859375, styledScale["y"] ?? 0)
    check(near(ios["x"] ?? 0, lowered), "image lowered 1 pt: \(lowered): \(ios["x"] ?? 0)")
    check(near(ios["y"] ?? 0, onBaseline), "image on the baseline: \(onBaseline): \(ios["y"] ?? 0)")

    // 3. `.bold()` is the bold trait: semibold over regular on iOS (iOS 27.0
    //    simulator, stupid social's actor names), `fontWeight(.bold)` stays bold.
    check(Font.body.resolve(weight: .boldTrait).weight == .semibold, "body + bold trait is semibold")
    check(Font.body.bold().resolve(weight: nil).weight == .semibold, "Font.body.bold() is semibold")
    check(Font.headline.resolve(weight: .boldTrait).weight == .semibold, "headline + bold trait is semibold")
    check(Font.title2.weight(.semibold).bold().resolve(weight: nil).weight == .bold,
          "title2.weight(.semibold).bold() keeps the style rule: bold")
    check(Font.body.weight(.medium).bold().resolve(weight: nil).weight == .semibold,
          "body.weight(.medium).bold() is semibold")
    let t2 = Font.title2.weight(.semibold).resolve(weight: nil)
    check(near(t2.lineHeight + t2.leading, 28), "title2.weight(.semibold) keeps title2 spacing")
    check(Font.body.resolve(weight: .bold).weight == .bold, "fontWeight(.bold) is bold")
    check(Font.system(size: 17).bold().resolve(weight: nil).weight == .semibold, "system(size:).bold() is semibold")
    let named = labels(in: hosted(HStack(spacing: 0) {
        Text("alex_smith").bold()
        Text("\(Text("nova.builds").bold()) x")
    }))
    let plainBold = named.first { $0.text == "alex_smith" }?.font
    check(plainBold?.weight == .semibold, "Text.bold() label font is semibold: \(String(describing: plainBold?.weight))")
    if let styled = named.first(where: { $0.text == "nova.builds x" })?.attributedText,
       let font = styled.attributes(at: 0, effectiveRange: nil)[OpenUIKit.NSAttributedString.Key.font] as? UIFont {
        check(font.weight == .semibold, "styled .bold() run is semibold: \(font.weight)")
    } else {
        check(false, "styled bold label not found")
    }

    // 4. A modified EmptyView takes no stack slot or spacing (stupid social's
    //    follow row: `previewContent.padding(.trailing, 24)` is EmptyView).
    let root = hosted(VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Q1").font(.subheadline)
            EmptyView().padding(.trailing, 24)
        }
        Text("Q2").font(.subheadline)
    })
    let stacked = labels(in: root)
    if let q1 = stacked.first(where: { $0.text == "Q1" }), let q2 = stacked.first(where: { $0.text == "Q2" }) {
        let gap = q2.convert(q2.bounds, to: root).minY - q1.convert(q1.bounds, to: root).maxY
        check(near(gap, 0), "padded EmptyView adds no spacing: gap \(gap)")
    } else {
        check(false, "stack labels not found")
    }

    // 5. Orphan avoidance (iOS 27.0 simulator: stupid social's 302 pt preview
    //    "Big fan of showing notifications without / the feed.").
    let maya = "Big fan of showing notifications without the feed."
    let sub15 = Font.subheadline.resolve(weight: nil)
    let greedyLines = TextLayout.wrap(maya, font: sub15, maxWidth: 302, maxLines: 2)
    check(greedyLines.map { String($0.text) } == ["Big fan of showing notifications without the", "feed."],
          "greedy wrap leaves an orphan: \(greedyLines.map { String($0.text) })")
    let pushed = TextLayout.avoidingOrphan(greedyLines, text: maya, font: sub15, maxWidth: 302)
    check(pushed.map { String($0.text) } == ["Big fan of showing notifications without", "the feed."],
          "orphan pushed out: \(pushed.map { String($0.text) })")
    let plainLabel = UILabel()
    plainLabel.text = maya
    plainLabel.font = sub15
    plainLabel.numberOfLines = 2
    let greedyWidth = plainLabel.sizeThatFits(CGSize(width: 302, height: 1000)).width
    plainLabel._avoidsOrphanLastWord = true
    let pushedWidth = plainLabel.sizeThatFits(CGSize(width: 302, height: 1000)).width
    check(pushedWidth < greedyWidth, "pushed-out label is narrower: \(pushedWidth) < \(greedyWidth)")
    let two = "Love this — finally a feed I can open without getting lost. Shipping!"
    let keep = TextLayout.wrap(two, font: sub15, maxWidth: 302, maxLines: 2)
    check(TextLayout.avoidingOrphan(keep, text: two, font: sub15, maxWidth: 302).map { String($0.text) }
          == keep.map { String($0.text) }, "a multi-word last line is unchanged")
    let styledRoot = hosted(Text("\(Text("Big").bold()) fan of showing notifications without the feed.")
        .font(.subheadline).lineLimit(2).frame(width: 302, alignment: .leading))
    if let l = labels(in: styledRoot).first, let t = l.attributedLayoutText {
        let ranges = l.attributedDrawLines(t, width: l.bounds.width).map(\.range)
        check(ranges.count == 2 && ranges.last?.count == "the feed.".unicodeScalars.count,
              "styled orphan pushed out: \(ranges)")
    } else {
        check(false, "styled orphan label not found")
    }

    // 6. The macOS cut is unchanged: no text-style leading, `.bold()` is bold.
    OpenUIKitRuntime.systemFontCut = .macOS
    check(Font.subheadline.resolve(weight: nil).leading == UIFont.systemFont(ofSize: 15).leading,
          "macOS cut: subheadline has the font-file leading")
    check(Font.body.resolve(weight: .boldTrait).weight == .bold, "macOS cut: bold trait is bold")
    let mac = heights()
    check(mac["long"] == mac["E"], "macOS cut: subheadline height equals system(size: 15)")
    OpenUIKitRuntime.systemFontCut = .iOS
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "TEXT_METRICS_PROBE=PASS" : "TEXT_METRICS_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
