// Native gate for stupid social's group chat (docs/GROUP_CHAT.md).
//
//   swift run groupchatprobe     exits 0 when every check passes
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

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(a - b) <= tolerance }

@MainActor func bodyText(_ parts: [Any], time: String) -> OpenUIKit.NSAttributedString {
    let body = UIFont.preferredFont(forTextStyle: .body)
    let text = OpenUIKit.NSMutableAttributedString()
    for part in parts {
        if let s = part as? String {
            text.append(NSAttributedString(string: s, attributes: [.font: body, .foregroundColor: UIColor.label]))
        } else if let a = part as? NSTextAttachment {
            text.append(NSAttributedString(string: "\u{FFFC}", attributes: [.font: body, .attachment: a]))
        }
    }
    text.append(NSAttributedString(string: "   \(time)", attributes: [
        .font: UIFont.preferredFont(forTextStyle: .caption2), .foregroundColor: UIColor.clear]))
    return text
}

/// The app's custom-emoji attachment: an inline image the height of the line.
@MainActor func emojiAttachment(font: UIFont) -> NSTextAttachment {
    let attachment = NSTextAttachment()
    let h = font.lineHeight
    attachment.bounds = CGRect(x: 0, y: font.descender, width: h, height: h)
    attachment.image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    return attachment
}

@MainActor func textWidth(_ text: OpenUIKit.NSAttributedString, max: CGFloat) -> CGFloat {
    ceil(text.boundingRect(with: CGSize(width: max, height: .greatestFiniteMagnitude),
                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).width)
}

/// stupid social's reply quote (ChatReplyQuoteView): a bar and a two-label
/// stack inset 4 pt top and bottom, all by constraints.
@MainActor func replyQuote() -> UIView {
    let view = UIView()
    let bar = UIView()
    let name = UILabel()
    name.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    name.text = "Nova"
    let text = UILabel()
    text.font = .preferredFont(forTextStyle: .footnote)
    text.text = "Linking the thread from #design so we don't lose it"
    let labels = UIStackView(arrangedSubviews: [name, text])
    labels.axis = .vertical
    labels.spacing = 1
    for v in [bar, labels] {
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
    }
    NSLayoutConstraint.activate([
        bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        bar.topAnchor.constraint(equalTo: view.topAnchor),
        bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        bar.widthAnchor.constraint(equalToConstant: 3),
        labels.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
        labels.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        labels.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
        labels.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
    ])
    return view
}

/// stupid social's reaction container: a chip row 4 pt below the top, its
/// bottom pinned at low priority.
@MainActor func reactions() -> (container: UIView, row: UIStackView) {
    let container = UIView()
    let row = UIStackView()
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(row)
    let bottom = row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    bottom.priority = .defaultLow
    NSLayoutConstraint.activate([
        row.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
        bottom,
        row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),
    ])
    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 11)
    var count = AttributedString(" 2")
    count.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    var emoji = AttributedString("💯")
    emoji.font = UIFont.systemFont(ofSize: 20)
    configuration.attributedTitle = emoji + count
    configuration.titleLineBreakMode = .byClipping
    row.addArrangedSubview(UIButton(configuration: configuration))
    return (container, row)
}

/// Theo's group-chat bubble (stupid social ChatMessageCell, message a5):
/// header stack (name, reply quote), hidden media stack, content stack
/// (body, hidden embeds, reactions, hidden time spacer), in one vertical
/// stack pinned to a bubble 302 pt wide.
@MainActor func theoBubble() -> (root: UIView, bubble: UIView, name: UILabel, quote: UIView,
                                  body: UILabel, reactions: UIView) {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    let bubble = UIView()
    bubble.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(bubble)
    let name = UILabel()
    name.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    name.text = "Theo"
    let reminder = UILabel()
    reminder.isHidden = true
    let quote = replyQuote()
    let body = UILabel()
    body.numberOfLines = 0
    body.attributedText = NSAttributedString(string: "One inbox for everything. No feed. That's the dream",
                                             attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
    let embeds = UIStackView()
    embeds.axis = .vertical
    embeds.isHidden = true
    let (container, _) = reactions()
    let timeSpacer = UIView()
    timeSpacer.heightAnchor.constraint(equalToConstant: 12).isActive = true
    timeSpacer.isHidden = true
    let header = UIStackView(arrangedSubviews: [reminder, name, quote])
    let content = UIStackView(arrangedSubviews: [body, embeds, container, timeSpacer])
    for section in [header, content] {
        section.axis = .vertical
        section.spacing = 4
        section.isLayoutMarginsRelativeArrangement = true
    }
    header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 4, trailing: 12)
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 7, trailing: 12)
    let media = UIStackView()
    media.axis = .vertical
    media.isLayoutMarginsRelativeArrangement = true
    media.isHidden = true
    let stack = UIStackView(arrangedSubviews: [header, media, content])
    stack.axis = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    bubble.addSubview(stack)
    let bubbleBottom = bubble.bottomAnchor.constraint(equalTo: root.bottomAnchor)
    bubbleBottom.priority = .defaultHigh
    let width = bubble.widthAnchor.constraint(equalToConstant: 302)
    width.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([
        bubble.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
        bubble.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
        bubbleBottom, width,
        stack.topAnchor.constraint(equalTo: bubble.topAnchor),
        stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
        stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
    ])
    return (root, bubble, name, quote, body, container)
}

@MainActor func run() {
    OpenUIKitRuntime.systemFontCut = .iOS
    let body = UIFont.preferredFont(forTextStyle: .body)
    print("body lineHeight \(body.lineHeight) ascender \(body.ascender) descender \(body.descender) leading \(body.leading)")

    // Theo's line: "Yes! <:stupid-social:> works in reactions too" + reserved time.
    // MEASURED iOS 27 simulator: label 267 x 20.333 (one line).
    let theo = bodyText(["Yes! ", emojiAttachment(font: body), " works in reactions too"], time: "09:21")
    let maxW: CGFloat = min(390 * 0.8, 390 - 88) - 24
    let tw = textWidth(theo, max: maxW)
    let label = UILabel()
    label.numberOfLines = 0
    label.attributedText = theo
    let fit = label.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude))
    print("theo textWidth \(tw) fit \(fit) intrinsic \(label.intrinsicContentSize)")
    check(near(tw, 267, 1), "attachment line width (\(tw)) is iOS's 267")
    check(near(fit.height, 20.333, 0.4), "attachment line is one line high (\(fit.height))")

    // Maya's line with a colour emoji: two lines, 270 wide, 42.333 tall.
    let maya = bodyText(["Telegram, X and Bluesky DMs all in one list now 🤯"], time: "09:59")
    let mw = textWidth(maya, max: maxW)
    label.attributedText = maya
    let mfit = label.sizeThatFits(CGSize(width: mw, height: .greatestFiniteMagnitude))
    print("maya textWidth \(mw) fit \(mfit)")
    check(near(mfit.height, 42.333, 0.4), "emoji line pair is two lines high (\(mfit.height))")

    // An own bubble's text (no time reserved: it has reactions). MEASURED
    // iOS 27: label 269 pt, two lines.
    let shipped = OpenUIKit.NSAttributedString(string: "Shipped # autocomplete for rooms today, try it in the composer",
                                               attributes: [.font: body])
    let shippedWidth = textWidth(shipped, max: min(390 * 0.8, 390 - 70) - 24)
    check(near(shippedWidth, 269, 1), "own bubble text width (\(shippedWidth)) is iOS's 269")

    // Theo's bubble. MEASURED iOS 27 simulator (window points, bubble top at
    // 496.67): name 7 pt down, 18 tall; quote 29 down, 40.33 tall; body 73.33
    // down; chips 123.67 down; bubble 165 tall.
    let theoCell = theoBubble()
    let fitted = theoCell.root.systemLayoutSizeFitting(
        CGSize(width: 390, height: 0), withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel)
    theoCell.root.frame = CGRect(x: 0, y: 0, width: 390, height: fitted.height)
    theoCell.root.layoutIfNeeded()
    func inBubble(_ v: UIView) -> CGRect { v.convert(v.bounds, to: theoCell.bubble) }
    let nameFrame = inBubble(theoCell.name), quoteFrame = inBubble(theoCell.quote)
    let bodyFrame = inBubble(theoCell.body), reactionsFrame = inBubble(theoCell.reactions)
    print("theo bubble \(theoCell.bubble.frame) name \(nameFrame) quote \(quoteFrame) body \(bodyFrame) reactions \(reactionsFrame)")
    check(near(nameFrame.minY, 7) && near(nameFrame.height, 18), "sender name keeps its line (\(nameFrame))")
    check(near(quoteFrame.minY, 29) && near(quoteFrame.height, 40.33, 1), "reply quote keeps its height (\(quoteFrame))")
    check(near(bodyFrame.minY, 73.33, 1), "body follows the header (\(bodyFrame.minY))")
    check(near(reactionsFrame.height, 38.33, 1), "reaction container hugs its chips (\(reactionsFrame.height))")
    check(near(theoCell.bubble.frame.height, 165, 1.5), "bubble is 165 pt tall (\(theoCell.bubble.frame.height))")

    // A configuration image asked for its original colours keeps them.
    let red = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    }.withRenderingMode(.alwaysOriginal)
    var configuration = UIButton.Configuration.filled()
    configuration.image = red
    configuration.baseForegroundColor = .white
    let chip = UIButton(configuration: configuration)
    check(chip.image(for: .normal)?.renderingMode == .alwaysOriginal,
          "configuration image keeps .alwaysOriginal")
    configuration.image = red.withRenderingMode(.automatic)
    chip.configuration = configuration
    check(chip.image(for: .normal)?.renderingMode == .alwaysTemplate,
          "configuration image without a mode is a template")

    // Scroll-edge pocket engagement: only content under the container.
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let scroll = UIScrollView(frame: host.bounds)
    host.addSubview(scroll)
    let composer = UIView(frame: CGRect(x: 12, y: 754, width: 366, height: 56))
    composer.addSubview(UILabel())
    host.addSubview(composer)
    let interaction = UIScrollEdgeElementContainerInteraction()
    interaction.scrollView = scroll
    interaction.edge = .bottom
    composer.addInteraction(interaction)
    scroll.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
    scroll.contentSize = CGSize(width: 390, height: 2000)
    let rest = scroll.contentSize.height + 100 - 844
    scroll.contentOffset = CGPoint(x: 0, y: rest - 0.4)
    interaction._update()
    check(interaction.pocket?.isHidden != false, "no pocket a fraction short of the bottom with nothing under the composer")
    scroll.contentOffset = CGPoint(x: 0, y: rest - 40)
    interaction._update()
    check(interaction.pocket?.isHidden == false, "pocket once content passes under the composer")

    // A self-sizing composer text view: iOS 27 measures 38 pt empty.
    let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 290, height: 36))
    textView.font = .preferredFont(forTextStyle: .body)
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    textView.isScrollEnabled = false
    let textFit = textView.sizeThatFits(CGSize(width: 290, height: CGFloat.greatestFiniteMagnitude))
    check(near(textFit.height, 38, 0.34), "empty body text view fits 38 pt (\(textFit.height))")

    // A UIGlassEffect view on iOS 27 is a glass platter with corners.
    OpenUIKitRuntime.chromeRelease = .iOS27
    let glass = UIVisualEffectView(effect: UIGlassEffect())
    glass.cornerConfiguration = .uniformCorners(radius: .fixed(13))
    glass.frame = CGRect(x: 0, y: 0, width: 58, height: 25.67)
    check(glass._usesIOSGlass && glass._isIOSGlassPlatter, "UIGlassEffect view draws as an iOS 27 glass platter")
    let tinted = UIGlassEffect()
    tinted.tintColor = .red
    check(!UIVisualEffectView(effect: tinted)._usesIOSGlass, "tinted glass keeps its tinted filter")
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 60))
    container.backgroundColor = .white
    glass.frame = CGRect(x: 20, y: 16, width: 58, height: 25.67)
    container.addSubview(glass)
    let bitmap = UIRenderer.renderPassRender(container, scale: 3)
    func grey(_ x: Int, _ y: Int) -> Int { Int(bitmap.pixels[(y * bitmap.width + x) * 4]) }
    print("glass pixels corner \(grey(61, 49)) interior \(grey(87, 87)) left rim \(grey(59, 87))")
    check(grey(61, 49) >= 250, "glass corner is rounded (backdrop shows through)")
    check(grey(59, 87) < 200, "grey rim at the left extreme (\(grey(59, 87)))")
    check(grey(87, 87) >= 248, "near-white glass interior (\(grey(87, 87)))")
    OpenUIKitRuntime.chromeRelease = .iOS26
}

let failures = MainActor.assumeIsolated { () -> Int in
    run()
    return Probe.failures
}
print(failures == 0 ? "GROUP_CHAT_PROBE=PASS" : "GROUP_CHAT_PROBE=FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
