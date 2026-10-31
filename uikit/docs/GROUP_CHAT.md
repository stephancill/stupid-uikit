# Group chat: mixed stack content, attachment lines, iOS 27 glass

Reference: stupid social (demo mode, network on) on an iOS 27.0 iPhone 16e simulator (390 x 844 pt
@3x), compared at 2x with the x86_64 iOS-simulator guest driven by the same `stupidsim` inputs
(`SSG_SCRIPT`, `SSG_LOCALE=en_GB`): Chats (swipe 0.15 0.6 -> 0.95 0.6), the Telegram chat
(tap 0.50 0.37), back (tap 0.10 0.08), the Apron group chat "general" (tap 0.50 0.29). The chat is
`ChatUIKitView`, a UICollectionView of self-sizing UIKit cells; each bubble is a vertical
`UIStackView` (header stack: name, reply quote; media stack; content stack: text, embeds, reaction
container, time spacer) pinned by constraints to a bubble whose width the app computes.

Native gate: `swift run groupchatprobe` (a replica of the bubble, the attachment and emoji lines,
the chip image, the composer text view, scroll-edge engagement, a glass capsule's pixels).

## What changed

| area | change |
| --- | --- |
| `UIStackView` `.fill` (iOS cut) | A flexible arranged view (a nested stack, a plain view sized by its subviews' constraints) keeps its natural length; only the slack goes to the last flexible view (up to 1 pt short is rounding and is taken from it). Taking every flexible view to 0 collapsed the bubble's header stack (sender name, reply quote) and gave its height to the reaction container. A real overflow keeps the old rule. |
| constraint-fitted arranged views | When the engine fits a plain arranged view's height from its subviews' constraints, that height is used and the margin-floor estimate is not added on top (a reply quote is 40.33 pt, a reaction container 4 + 34.33; the floor had added the plain view's 8 pt margins on both sides). |
| nested stacks measured at their width | A vertical filling stack measures nested stacks and constraint-sized views at the width it gives them (less its margins), not at their current bounds (zero before the first layout). |
| engine: vertical stacks re-measured (iOS cut) | Like a wrapping label, a constraint-sized vertical `UIStackView` is re-measured at the width the solver gave it (second pass). Its intrinsic size had been read at its previous width, so a bubble came out a line short and the stack compressed its first rows. |
| `NSAttributedString.boundingRect` with `.usesLineFragmentOrigin` | Lays the runs out like a label (fonts, attachments, colour emoji, wrapping at the width) instead of measuring the whole string in the first run's font on one line. The app sizes bubbles from it; a line with a custom-emoji attachment and a smaller clear time run measured 3.5 pt narrower than the label, which then wrapped the time onto a line of its own (the "taller than it draws" line). MEASURED: 267 pt, one line. Without that option the old single-line measure stays. |
| `UIButton.Configuration.image` | `.alwaysOriginal` images keep their colours (custom emoji in reaction chips drew as foreground-coloured squares); others are templates as before. |
| `UITextView.sizeThatFits` (iOS cut) | The height the text needs at the width: insets + lines x (line height + leading). MEASURED: an empty body-font composer is 38 pt (16 + 20.287 + 1.713); UIView's answer (its current size) kept it at 36 and moved the whole list 2 pt down. |
| `UIGlassEffect` views (iOS cut, iOS 27 chrome) | An untinted glass `UIVisualEffectView` is a glass platter (`_usesIOSGlass`): the measured light material clipped to its corners (`cornerConfiguration` radii now reach `_iosGlassPath`), the iOS 27 grey rim just outside its outline (any corner radius, `_UIBarPlatterRimView.drawRim`) and the light platter shadow; the backdrop view no longer paints a square copy. MEASURED "Today" capsule (radius 13): rim 177 at the left extreme, interior 249-253 over white; guest rim 182, interior 253, edges within 0.2 pt. Tinted glass keeps the tinted filter. |
| SwiftUI principal `.glassEffect` (iOS 27) | The capsule is the bar's 44 pt platter height centred on the 36 pt title host (glass [47, 91] like the back button) with the iOS 27 rim; content stays centred. It had been sized to the content with its vertical padding collapsed (34.67 pt). |
| scroll-edge container pocket | Engaged only while content is under the container (past its inner edge by more than 0.5 pt), not whenever the offset is off its rest. The chat rests a fraction short of its maximum offset with nothing under the composer; iOS 27 shows no pocket there, the guest drew the dark scrim over the composer. |
| automation tree | A UIKit collection view's elements are ordered by centre y, then x (only collection views: a flat sort of a SwiftUI scroll view interleaved the root feed's story carousels) (iOS: the date header before the cells, a cell's avatar between its text and its time). A `UILabel` that takes taps (user interaction on, an enabled tap recognizer) is a Button (chat text labels). An empty `UITextView` has no value. |

## Measurements (points, iOS 27 simulator vs guest)

Apron group chat, every element of the tree matched by role and label (times ignored): all within
0.4 pt in x, width and height except the time labels (wall-clock text widths); y offsets are the
residual listed in the stupid-app-preview implementation notes for the verified head. Theo's reply
bubble: name 7 pt below the bubble top, quote at 29 (40.33 tall), text at 73.33, chips at 123.67,
bubble 165 tall, as on iOS.

## Known gaps

- The soft scroll-edge effect (`.soft`, the white wash under the bar and the composer) is recorded,
  not painted; the top messages draw crisp under the title where iOS fades them.
- The glass interior is the flat platter mix (253 over white); iOS 27 shades it (244-253 down the
  composer pill).
- Demo times follow the wall clock, so time widths and the bubbles they widen differ.
