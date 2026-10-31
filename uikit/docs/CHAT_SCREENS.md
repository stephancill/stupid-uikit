# The Chats side of stupid social

Reference: stupid social (demo mode, network on) on an iOS 27.0 iPhone 16e simulator (390 x 844 pt
@3x), compared at 2x with the x86_64 iOS-simulator guest driven by the same `stupidsim` inputs through
the automation module (`SSG_SCRIPT`):

| screen | input from launch |
| --- | --- |
| Chats (HomePager page 1 of 2) | swipe 0.15 0.6 -> 0.95 0.6 |
| Telegram chat with Maya Chen | ... then tap 0.50 0.37 |
| Apron group chat "general" | ... back (tap 0.10 0.08), tap 0.50 0.29 |

The pager swipe itself (a feed row's `.swipeActions` pan no longer claiming every drag) landed on
swift64 from agent in; `swiftuichatsprobe` keeps a page-view-controller swipe check for it.

## What changed

| area | change |
| --- | --- |
| typed KVO of scroll geometry | `UIScrollView` reports `contentOffset` and `contentSize` changes through `_OpenUIKitKeyValueObserving.didChange`; the Foundation facade (`full/foundation/Progress.swift`, compiled after OpenUIKit) installs it on the first `observe(_:)` and resolves the observer's key path by name on the static type it used (`_OpenUIKitKeyValueObservable`, so `\UICollectionView.contentSize` matches). The HomePager's page dots follow the swipe (the tree reads "Chats, page 1 of 2"); the chat keeps short conversations above the composer. |
| `fchmod` | `full/foundation/fm_unimplemented.c` implements it through `/proc/self/fd/N` + `chmod` (machorun re-exports `chmod`, not `fchmod`): swift-foundation's atomic write keeps a replaced file's mode, and stupid social rewrites its caches when the pager reaches Chats. (`mktemp` landed on swift64 from agent ap.) |
| HStack compression | One helper (`_hStackCompressedWidths`) for measure and placement. A child with a `.frame(width:)` in its modifier chain is rigid and only gives way after every flexible peer; `Spacer(minLength:)` keeps its minimum. MEASURED: the Chats row avatars (initials ones contain a Text) keep 48 pt beside a two-line preview, which wraps 8 pt before the unread pill. |
| `.searchable(placement: .navigationBarDrawer)` (iOS cut) | The field is stacked under the (large) title: the content keeps its full frame with 54 pt more top safe area (`UIView._openAdditionalSafeAreaInsets`, the per-view form of a controller's `additionalSafeAreaInsets`) and the bar sits at the safe-area top. MEASURED: field `[16, 153, 358, 44]`, first row at 207. The drawer field is a flat `tertiarySystemFill` capsule (239, 239, 240 over white) without the standalone field's drop shadow, with a `label` magnifier (`UISearchBar._openInNavigationBarDrawer`). `.automatic` (bottom-docked) is nv's `UISearchController` path, unchanged. |
| pushed `navigationDestination(isPresented:/item:)` chrome | The presentation container mirrors its hosted view's navigation item (title, `navigationBarTitleDisplayMode` as `largeTitleDisplayMode`, principal `titleView`, bar items) and re-mirrors when the hosted view re-evaluates; the SwiftUI stack honours the container's `.never`/`.always`. The chat screens get their inline bar and the glass title pill (avatar, "Maya Chen", "online"). |
| collection list sections from a section provider | `NSCollectionLayoutSection.list(using:)` sections self-size like `init(list:)` layouts (the layout keeps each section's list configuration), cells read their own section's configuration (separators, background), an estimated list header self-sizes from its constraints (the "Today" date header, 37.5 vs 37.7 pt), and a sectioned list adds no first-row header padding. |
| custom-content list cells | A `UICollectionViewListCell` whose app filled `contentView` (no content configuration) sizes to its constraints, with no 52 pt floor (that belongs to `UIListContentConfiguration`). |
| `UIVisualEffectView.contentView` in Auto Layout | Enters the solver as UIKit's autoresizing translation (edges follow the effect view) instead of a frozen frame, so constraints inside size the effect view (glass composer pill, date capsule). |
| `UIStackView` arranged views sized by constraints (iOS cut) | A plain arranged view whose height comes from its own subviews' constraints contributes its Auto Layout fitting height (reentrant engine fitting solve) at a known width, and an aspect-ratio constraint (`height == width * k`, a chat photo) gives its height from the width the stack gives it. A margin-relative vertical stack wraps labels at its width less the margins (a bubble's text took one line fewer than it was laid out with, and the stack compressed the sender name away). |
| automation tree | `snapshot` / `ui-tree` lay the window out first, so views placed in `layoutSubviews` are where the PNG shows them. |

## Measurements (points, iOS 27 simulator vs guest)

- Chats: large title (16, 104.7) vs (16, 104.5); search field identical; every row at the same y (the
  guest's row buttons are the 48 pt content inside the 8 pt row insets; the simulator reports whole
  64 pt cells); page dots (178.7, 789) identical; avatars, badges and pills in place.
- Maya Chen chat: back button, title pill (avatar 124.5 vs 124.3, name, "online") within 1 pt; the
  date header 10 pt high and the first two bubbles 10 pt high, "New Messages" +1.7 pt, the photo and
  composer within 2 pt.

## Verification

- `swift run swiftuichatsprobe` (uikit package, native): pager swipe over rows with trailing swipe
  actions, scroll-geometry reports and key-path resolution, rigid HStack children, drawer search
  field and first row, a glass pill sized by its contentView's constraints in a bottom-pinned stack
  with hidden previews.
- The other native probes still pass (lazy, nav chrome, shape mask, stroke, text metrics, root
  residuals, app catch-up).
- stupid social (the reference app version) on the iOS triple with the step files above.
- Phase 2 rung b on the macOS triple.

## Known gaps

- Colour emoji: the guest has no colour emoji font, so emoji (and the 👍 reaction chip) do not draw.
- Times follow the guest's 12-hour locale ("10:43 AM"); the reference simulator's locale is 24-hour.
- The Apron group chat's bubbles still mis-measure: sender names and some reply quotes collapse,
  and a reaction row's container takes slack (frame-based `UIStackView` measurement against
  constraint-based content; a custom-emoji attachment line measures taller than it draws).
- Custom emoji images in chat text and reactions (`:apron:`) do not show.
- Pinned section headers (`pinToVisibleBounds`) are not modelled; the date capsule draws as a flat
  rectangle instead of the glass capsule.
- The bottom scroll-edge pocket under the composer engages at rest when the list is not exactly at
  its maximum offset.
