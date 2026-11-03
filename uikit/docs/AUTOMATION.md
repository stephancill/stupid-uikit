# Automation: driving a running app headlessly

`Sources/OpenUIKit/Automation/` lets a host drive a running app the way `stupidsim` drives the iOS
Simulator — tap, swipe, type, press keys — and read back a screenshot and an accessibility tree
after each step, with no window system. It is generic: any app hosted by the SwiftUI `App` loop
(and any host loop that calls `OpenUIKitRuntime.hostTurnHook`) can use it.

## Pieces

- `OpenUIKitRuntime.hostTurnHook: (@MainActor (Double) -> Bool)?` — called by the SwiftUI
  application host loop (`_OpenSwiftUIApplicationLifecycle._runApplicationHost`) once per turn,
  after the main queue drained and the windows ticked, with the turn's host-clock time. Returning
  false ends the loop exactly as a bounded `OPENUIKIT_HOST_TURNS` count does
  (`_hostWillTerminate`, the app's entry point returns). Nil by default: nothing changes.
- `OpenUIKitRuntime.hostInputHook: (@MainActor (Double) -> Void)?` — called by the same loop
  once per turn *before* the windows tick, with the time they are about to tick to. The session
  delivers input events due by then first, so a scheduled lift reaches the recognizers before a
  slow turn's clock carries them past it (otherwise a 0.4 s tap after a long turn fired a 0.5 s
  long press, and the context menu cancelled the tap).
- `UIAutomationSession` — installs itself as the hooks and runs commands:
  - input goes through the ordinary event path: `UIWindow.sendTouch` (hit testing, gesture
    recognizers, scroll physics, delayed content touches, the software keyboard window),
    `sendText`, `sendKey`. Touch phases are stamped with their scheduled times on the host clock;
    a touch-down and a lift each get their own turn, drags keep every intermediate point.
  - after every input it runs turns until the app settles: a value fingerprint of the window
    (geometry, visibility, colours, text, images, content versions — not object identity, since
    the SwiftUI layer rebuilds UIViews) is unchanged for `settleStableTurns` (12) consecutive
    turns and no touch, scroll deceleration, navigation transition, sheet spring, pending UIView
    animation completion or recorded animation is active. It fails loudly after
    `settleTimeoutTurns` (900, ~15 s) with the reason (`diagnoseSettling` logs which views keep
    changing; `diagnoseInput` logs each touch's hit view and recognizer states).
  - `--verify` (as `stupidsim`): settle first (else exit 3), render at `verifyScale` (1x) before
    and after the input, exit 2 when the pixels are identical. A change answers with
    `stupidsim`'s verdict line, `verified: <n> pixels changed in <w>x<h> at <x>,<y>`, in the
    pixels of the `verifyScale` renders.
  - the caret is held solid (`UITextInputState.solidHold = .infinity`) so frames don't depend on
    the blink phase.
  - `type` and `key` need a focused input (exit 1 "nothing has keyboard focus" otherwise) and
    fail (exit 1, "keyboard focus was lost after N of M keys") when focus goes away part-way
    instead of dropping the remaining keys; see "Text input" below.
  - sources: `.script([String])` (run in order, end after the last) or
    `.controlDirectory(path)` (live; see below).
- `UIAutomationTree` — the accessibility tree iOS would expose, in `stupidsim ui-tree`'s shape:
  `Application` root (label: the display name the host passes), `Group` for the outermost
  non-paging scroll view of a screen, leaves `Button` / `StaticText` / `Heading` / `Image` /
  `TextField` / `Switch` / `Slider` / `Link` / `GenericElement` with label, value, identifier and
  frame in window points. `text(_:labelled:)` prints `Role "label" value="…" id=… @ x,y` (centre in
  normalized coordinates, absent off screen), `json(_:)` matches Foundation's sorted, pretty
  JSONEncoder output of the same fields (frames `[[x, y], [w, h]]`).

## Tree rules

UIKit's defaults live in the tree builder rather than on each class (OpenUIKit stores accessibility
properties but drives no assistive technology):

- hidden, alpha 0, `accessibilityElementsHidden` subtrees and views wholly beside the screen (an
  off-screen pager page) are skipped; rows scrolled above/below stay (no centre), as on iOS.
- `isAccessibilityElement` views are elements (label from `accessibilityLabel`, else their
  content's labels joined with ", ").
- implicit elements: `UILabel` with text (StaticText; a navigation bar's title is a Heading),
  `UIButton`, `UIControl` with the button trait, the navigation bar's back button (`Button
  "<title>" id=BackButton`), bar button items (label, or UIKit's system item name such as
  "Search", or the SF Symbol name as id), `UITextField` (value: text or placeholder),
  `UITextView`, `UISwitch` (value 0/1), `UISlider`.
- a control's label is its content's labels joined with ", " (iOS's composition, e.g.
  `Button "Reply, Actors: alex_smith, 3m, ￼ alex_smith replied to you, …"`).
- SF Symbols take iOS 27's accessibility label for the symbol when the app gave none
  (`Image "Favourite" id=star.fill`, `Button "Close" id=xmark`; docs/SYMBOL_ACCESSIBILITY_LABELS.md).
  Composed labels use symbol labels only when the content has no other label; a control labelled
  only by symbols, or by none, reports its symbol name as id.
- the frameworks' own identifiers (`SwiftUI.…`, `OpenUIKit.…`) are never reported.
- only what iOS has built: a List or Form keeps the cells and section headers that intersect its
  bounds (a collection view's), and a cell whose content is one button is that button with the
  cell's frame (row insets included); a lazy stack keeps the rows within one viewport of the
  visible region (`UIView._automationLazyStackRows`, recorded by the SwiftUI layer), so a row the
  preview built only for its own prefetch is left out.
- once a presentation that covers its presenter (`shouldRemovePresentersView`: full screen) is in
  the window, only its container and what is above it are read: UIKit takes the presenter's view
  out of the window then, and OpenUIKit leaves it in place.
- a navigation bar whose top item has trailing bar button items is one empty `Group id=<title>`
  ("Nav bar") with no title, items or back button, as iOS 27 reports it; a bar with only a back
  button (or nothing) lists its heading and back button.

The SwiftUI layer states what its views mean through `UIView._automationAccessibility`
(`_UIAutomationAccessibility`, stored in the accessibility side table): `Image` views are Image
elements (`Image(systemName:)` with the symbol name as id and the symbol's iOS label,
`Image("name")` labelled by its name); `NavigationLink` is a Button;
`.accessibilityLabel/Hint/Value/AddTraits/Identifier` apply to every element inside the modified
view (SwiftUI semantics — a label on a stack labels each element in it) instead of making the
wrapper an element; `.accessibilityElement(children: .combine/.ignore)` makes
one element whose label combines (or ignores) the content.

Known differences from the iOS 27 simulator: SF Symbols outside OpenUIKit's label table (generated
for stupid social's symbols) and languages other than English have no label (the id carries the
name; iOS also spells some per region, "Favourite" in en_ZA), and element order is view order
(iOS sorts some containers geometrically).

## Text input

Tap a field, then `type` / `key`, as with `stupidsim`. Keys go to the window's first responder
through `UIWindow.sendText` / `sendKey`, the same path the drawn keyboard's keys take.

- SwiftUI text inputs (`TextField`, `SecureField`, `searchable` fields) keep one UIKit editor at
  their graph identity, so the field a tap focused stays focused while every typed character
  rebuilds the hosting view (`SWIFTUI_TEXT_INPUT.md`); `@FocusState` / `.focused` and
  `searchable(isPresented:)` move focus as in SwiftUI.
- Keyboard: `OpenUIKitRuntime.keyboard`. The iOS Simulator `stupidsim` drives has a hardware
  keyboard connected by default, so no software keyboard shows and nothing moves for one; a host
  comparing with `stupidsim` sets `.hardware` (stupid-app-preview's harness does, `SSG_KEYBOARD`).
  The default `.software` draws OpenUIKit's measured software keyboard (iPhone SE, iOS 26.1),
  which takes its own touches, insets enclosing scroll views and appears in screenshots.
- `--verify` on `type` / `key` compares rendered frames, so a key that changes nothing (backspace
  in an empty field) exits 2.

## Live control protocol

`.controlDirectory(dir)`: the session writes `dir/ready` once launched and settled. A client
publishes a request by writing `dir/request.tmp` and renaming it to `dir/request` (one command
line). The session removes it, runs the command and publishes `dir/response` the same way:
`exit <code>` on the first line, the command's output after it. Codes: 0 ok, 1 failed (bad command,
no focused input), 2 `--verify` saw no change, 3 the screen was already changing, 4 the app did not
settle. `quit` answers, ends the session and removes `ready`. Plain files and `rename` only, so it
works the same for a Darwin guest under machorun and a native host.

## Commands

Script lines and live requests share one syntax (`UIAutomationCommand.parse`), coordinates
normalized 0..1 as `stupidsim` takes them; `#` comments and blank lines are ignored:

    wait <turns> | wait idle
    tap <x> <y> [--hold-milliseconds 90] [--verify]          (also --x/--y)
    swipe <x1> <y1> <x2> <y2> [<duration-ms>] [--steps 16] [--step-milliseconds 12] [--verify]
                                                             (also --from-x/--from-y/--to-x/--to-y)
    type [--verify] <text>                                   one character per 25 ms
    key <name>... [--repeat N] [--verify]                    backspace|delete, return|enter,
                                                             left, right, up, down, space, tab, a character
    snapshot <name>          <name>.png, <name>.tree.txt, <name>.tree.json (+ host extras)
    screenshot <path> | ui-tree [--json] [--labelled] [--at <x>,<y>] [-o <path>] | quit

`ui-tree --at x,y` prints only the deepest element whose frame contains that normalized point
(drawn last wins), with its children, as `stupidsim ui-tree --at`; centres stay measured against
the window. No element there exits 1.

Unsupported keys (escape, home/end, modifier chords) are rejected, not ignored.

## Presses across SwiftUI rebuilds

The SwiftUI layer rebuilds its UIViews on layout, where SwiftUI keeps one platform control per
Button. A rebuild while a finger was down (an image arriving under it) left the touch on a detached
control, so the lift landed outside it and the tap was lost. The hosting view now keeps a pressed
button control (tracking, or the view of an active touch still behind a scroll view's
content-touch delay, `UIWindow._activeTouchViews`): it goes back in place of the control the
rebuild made under its centre, taking that control's frame, label and actions.
stupid-app-preview's `scripts/stupidsim/tap-race.sh` reproduces both this and the tick-order
loss above with a proxy that releases the images mid-tap.

## Related fixes made with this module

- `UIView._finishRebuildingSubviews()`: the SwiftUI hosting view rebuilds its subviews in
  `layoutSubviews`; adding/removing them marked it for layout again, so every `layoutIfNeeded`
  (every host turn of a SwiftUI app under a host that lays out per turn) rebuilt the whole
  hierarchy and re-ran presentation hosts' push/present side effects. It now clears its own layout
  request after the rebuild.
- `_UITransitionCoordinator.attach` iterates by index: on the x86_64 iOS-simulator guest the
  `IndexingIterator` over `[UIViewController?]` produced 0x2 for an element and `objc_retain`
  faulted on the first navigation push.

Found by driving stupid social with this module (each general, none app-specific):

- `.swipeActions(edge:)` rows install a pan that only begins for a horizontal drag toward the
  actions' edge (`_SwiftUISwipeActionsPanGate`); it claimed every drag before, so a List inside a
  `UIPageViewController` never let the pager page.
- `UIScrollView.flashIndicators`/`fadeIndicators` iterate `compactMap`ed indicators (same guest
  iteration fault as `attach`; the first pager drag crashed).
- `mktemp` is implemented in `full/foundation/fm_unimplemented.c` (FoundationEssentials' atomic
  `Data.write`; the Chats page aborted on its first cache write).
- A List's scroll offset is retained in its graph state (`_OpenViewNode.retainedScrollState`,
  `_SwiftUIListScrollTracker`): the hosting view rebuilds the List's scroll view, so a scrolled feed
  snapped back to the top. Only the user's scrolling (drag, deceleration) is retained, as a
  distance from the rest offset each rebuild computes, clamped to that rest. The first version
  stored raw offsets and also recorded the scroll view's own inset rebase (-116 -> -153); a plain
  render (no automation, which settles through more rebuilds) restored it against the new view's
  still-zero inset and drew the feed at offset 0 under the status bar and large title. Gate:
  `swift run swiftuilistrestprobe` (plain host turns only: rest below the bar, rest kept across
  rebuilds, a non-user offset not restored, a user drag kept); it fails on the first version.
- Subviews of a scroll view that folds the safe area into its adjusted content inset get no safe
  area of their own (UIKit's rule; a nested ScrollView in a scrolled List row adopted the bar's
  inset and re-laid out every turn).
- A large-title `UINavigationBar` hit-tests every control in the bar (bar button items, custom
  item views), not only the back button; toolbar taps went to the list under the capsule.

Not fixed here (other work): `NavigationLink(value:)` (the stupid social toolbar's search and
settings links) has no destination support, so tapping them changes nothing.

## Use from stupid-app-preview

`scripts/openuikit/stupid-social-guest.sh run` with `SSG_SCRIPT=<file>` (scripted) or `serve`
(live) plus `scripts/openuikit/preview-ctl.sh` (client); see the harness header.
