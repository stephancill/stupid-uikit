// Native gate for colour emoji (docs/COLOR_EMOJI.md).
//
//   swift run coloremojiprobe     exits 0 when every check passes
//
// Needs Noto Color Emoji at OpenUIKitRuntime.fontPaths["emoji"], under the
// resource root's fonts/, or at the distro path
// /usr/share/fonts/truetype/noto/NotoColorEmoji.ttf (fonts-noto-color-emoji).
import Foundation
import OpenCoreGraphics
@testable import OpenUIKit

@MainActor enum Probe {
    static var failures = 0
}

@MainActor func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { Probe.failures += 1 }
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

func ch(_ s: String) -> Character { Character(s) }

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS

    // Classification (UTS #51 presentation).
    for (s, expected) in [
        ("👍", true), ("🤯", true), ("❤️", true), ("❤", false), ("❤︎", false),
        ("#️⃣", true), ("1⃣", true), ("1", false), ("#", false), ("©", false), ("©️", true),
        ("🇬🇧", true), ("👍🏽", true), ("🧗‍♀️", true), ("👨‍👩‍👧", true), ("🏴󠁧󠁢󠁥󠁮󠁧󠁿", true),
        ("🌡", true), ("a", false), ("—", false),
    ] {
        let scalars = s.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }
        check(ColorEmoji.isEmoji(ch(s)) == expected,
              "isEmoji(\(scalars.joined(separator: " "))) == \(expected)")
    }
    check(!ColorEmoji.mayContainEmoji("Hello, world — 9:41"), "plain text skips the emoji path")
    check(ColorEmoji.mayContainEmoji("ok 👍"), "emoji text takes the emoji path")

    // Font and shaping: each sequence is one glyph with a strike image.
    guard let font = ColorEmoji.font else {
        check(false, "a colour emoji font is readable (\(ColorEmoji.candidatePaths))")
        return
    }
    check(font.ppem == 109, "Noto Color Emoji's strike is 109 ppem (got \(font.ppem))")
    for s in ["👍", "❤️", "🧗", "🧗‍♀️", "👨‍👩‍👧", "🇬🇧", "👍🏽", "#️⃣", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "🤯", "📸", "🚀", "😄", "👀"] {
        let glyphs = ColorEmoji.glyphs(for: s.unicodeScalars)
        check(glyphs.count == 1 && font.image(glyph: glyphs[0]) != nil,
              "\(s) shapes to one glyph with an image (\(glyphs))")
    }
    // Two flags stay two clusters; each is one emoji.
    check(Array("🇬🇧🇺🇸").count == 2, "two regional-indicator pairs are two clusters")

    // Measurement: one emoji advance per cluster, no kerning across it.
    let f17 = UIFont.systemFont(ofSize: 17)
    let a = FontEngine.measure("a", font: f17), b = FontEngine.measure("b", font: f17)
    let emoji = ColorEmoji.advance(of: "👍".unicodeScalars, font: f17)
    check(near(ColorEmoji.advance(of: "👍".unicodeScalars, font: .systemFont(ofSize: 20)), 25),
          "20 pt emoji advance is 25 pt (iOS reaction chips)")
    check(near(ColorEmoji.advance(of: "🚀".unicodeScalars, font: .systemFont(ofSize: 15)), 15 * 1.415),
          "15 pt emoji advance is 21.225 pt (iOS chat preview)")
    check(near(emoji, 17 * ColorEmoji.advanceEm(size: 17)), "17 pt emoji advance interpolates (got \(emoji))")
    check(near(FontEngine.measure("a👍b", font: f17), a + emoji + b), "a👍b measures a + emoji + b")
    check(near(FontEngine.measure("🧗‍♀️", font: f17), emoji), "a ZWJ sequence measures one emoji")
    check(near(FontEngine.measure("AV", font: f17), FontEngine.measureClusters("AV", font: f17, extra: 0)),
          "the cluster path measures plain text exactly as the scalar path (kerned AV)")

    // Wrapping keeps a cluster whole.
    let wrapped = TextLayout.wrap("👍🏽👍🏽👍🏽", font: f17, maxWidth: emoji * 1.5, maxLines: 0)
    check(wrapped.count == 3 && wrapped.allSatisfy { $0.text == "👍🏽" },
          "character wrap breaks between clusters (\(wrapped.map { String($0.text) }))")

    // Drawing: a label draws the emoji in colour at the pen position,
    // whatever the text colour, and plain text is unchanged.
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
    label.font = f17
    label.textColor = UIColor.label.withAlphaComponent(0.5)
    label.text = "a👍b"
    let bitmap = UIRenderer.renderPassRender(label, scale: 2)
    var colour = (minX: Int.max, maxX: Int.min, maxSat: 0, maxAlpha: 0)
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width {
            let i = (y * bitmap.width + x) * 4
            let p = bitmap.pixels[i..<i + 4].map { Int($0) }
            let sat = Swift.max(p[0], p[1], p[2]) - Swift.min(p[0], p[1], p[2])
            if p[3] > 0 && sat > 80 {
                colour.minX = Swift.min(colour.minX, x)
                colour.maxX = Swift.max(colour.maxX, x)
                colour.maxSat = Swift.max(colour.maxSat, sat)
                colour.maxAlpha = Swift.max(colour.maxAlpha, p[3])
            }
        }
    }
    let pen = a * 2
    check(colour.minX >= Int(pen) - 1 && CGFloat(colour.maxX) <= pen + emoji * 2 + 1,
          "the emoji ink lies inside its advance (ink x \(colour.minX)...\(colour.maxX), advance \(pen)...\(pen + emoji * 2))")
    check(colour.maxAlpha == 255, "the emoji draws opaque under a 50% text colour")

    let plain = UILabel(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
    plain.font = f17
    plain.text = "ab"
    let attributed = UILabel(frame: plain.frame)
    attributed.attributedText = NSAttributedString(string: "a👍b", attributes: [.font: f17])
    let ab = UIRenderer.renderPassRender(attributed, scale: 2)
    check(ab.pixels == bitmap.pixels || colourColumns(ab) == colourColumns(bitmap),
          "an attributed label places the emoji where the plain label does")
}

func colourColumns(_ b: Bitmap) -> [Int] {
    var cols: [Int] = []
    for x in 0..<b.width {
        for y in 0..<b.height {
            let i = (y * b.width + x) * 4
            let p = b.pixels[i..<i + 4].map { Int($0) }
            if p[3] > 0 && Swift.max(p[0], p[1], p[2]) - Swift.min(p[0], p[1], p[2]) > 80 { cols.append(x); break }
        }
    }
    return cols
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "COLOR_EMOJI_PROBE=PASS" : "COLOR_EMOJI_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
