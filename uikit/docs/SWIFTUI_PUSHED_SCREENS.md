# Screens beyond the root: navigation, inset-grouped lists, docked search

Reference: stupid social (demo mode, network on) on an iOS 27.0 iPhone 16e simulator (390 x 844 pt
@3x), screens reached from launch with `stupidsim` taps, compared at 2x with the x86_64
iOS-simulator guest driven by the same taps through the automation module (`SSG_SCRIPT`):

| screen | input from launch |
| --- | --- |
| notification detail ("Reply") | tap 0.50 0.40 |
| Settings | tap 0.89 0.082 (gear in the toolbar capsule) |
| Search | tap 0.745 0.082 (magnifier) |

## What changed

| area | change |
| --- | --- |
| `NavigationLink(value:)` | Native. The link node carries a target (`_OpenNavigationLinkTarget`: a destination controller, a path value, or inert for a nil value). Following a value link appends the value to the enclosing `NavigationStack(path:)`'s path binding; the stack's `navigationDestination(for:)` registration builds and pushes the destination. A stack without a path binding fails loudly by name (not needed yet). The stupid-app-preview compat module's fail-loud stand-in is removed. |
| toolbar NavigationLinks | A toolbar item whose content is a NavigationLink (stupid social's search and settings items) gets the link as its primary action, followed from the controller whose navigation item shows it. |
| stable toolbar items | Re-applying SwiftUI navigation chrome on every evaluation replaced every bar item (an empty leading side was re-assigned `nil`) and re-assigned `UIViewController.title` (which re-installs the bar's item stack), so the bar rebuilt its item views each evaluation and a touch that began on an old view could never end inside it. Equivalent items are now kept (only their actions / hosted nodes updated) and the title is assigned only when it changes. |
| large-title bar hit testing | Found here too (a large-title root's list took the toolbar taps); the fix that landed is agent in's `UINavigationBar.hitTest` on swift64 (controls in the bar take touches), kept on merge. |
| inset-grouped lists (iOS cut) | `Form` and `List` with `.insetGrouped` lay out as iOS 26/27 inset-grouped scroll views (`placeIOSInsetGroupedList`): content under the bar (the list's offset rests at the bar bottom), cards 16 pt from the edges with radius 26, rows of at least 52 pt with 16/15 pt content insets, 1 pt separators from the row's text column to 16 pt before the card edge (none after a section's last row), titled headers as 40.33 pt blocks (17 pt semibold secondary label 8.67 pt above the card), 17.5 pt (pixel-rounded) between a card and the next section, header-only sections without a card, empty sections and rows dropped, `listRowBackground` drawn behind the whole row, default-styled Button rows in the tint. Rows measure at their ideal height (spacers do not stretch them to the unbounded proposal). |
| list accessibility | A row that is a Button / NavigationLink / Link is one button element spanning the row; a LabeledContent row is one element ("Network, X"); a header is a full-width heading (a button header stays a button). `LabeledContent` combines its children. The form/list is a scroll view, so the tree groups it like the simulator (`Group`). |
| iOS 27 back button | With `OpenUIKitRuntime.chromeRelease = .iOS27` on the iOS cut the back control is a 44 pt glass circle at bar-local (16, 0) holding a 2.33 pt round-capped chevron in `label` colour; the previous title is kept as its accessibility label but not drawn. `.iOS26` keeps the chevron + title control (iOS 26.1's was not re-measured). |
| docked search | `.searchable` with `.automatic` placement on the phone (iOS cut, outside a tab bar controller) installs a `UISearchController` on the owning destination's navigation item, so UIKit's measured bottom-docked glass field draws it (`[28, H - 76, W - 56, 48]`), bound to the SwiftUI text; the content keeps the whole height. A large-title bar keeps its inline title hidden while the field is docked (it was forced visible). |
| ContentUnavailableView (iOS cut) | A `Label`-labelled view lays out as iOS does: the symbol (secondary, ~38.5 pt) above the title (title2 bold) 19 pt apart, the description in title3 secondary 3 pt below, centred, with the 26.67 pt iOS keeps under the description. The symbol is decorative (the label element is the title). |
| hand-drawn symbols | The two symbols the renderer draws by hand scale with the font on the iOS cut: `magnifyingglass` 18 pt at body size as before, `chevron.right` with SF's narrow proportions (MEASURED caption2 bold: ink 6.5 x 10). |

## Measurements (points, iOS 27 simulator vs guest, ink at 2x)

See the stupid-app-preview implementation notes (2026-10-31, "screens beyond the root") for the
full tables. Detail and Settings line up within 1 pt for cards, separators, headers, rows, back
platter and large title; Search within 1 pt for the docked field, symbol, title and description.

## Verification

- `swift run swiftuiscreensprobe` (uikit package, native): value links in content and toolbar,
  large-title bar item hit test, toolbar item and item-view reuse across re-evaluation, glass back button frame and tree, iOS 26
  back control unchanged, Form card/header/separator geometry and accessibility, docked search.
- `swift run swiftuinavchromeprobe` still passes.
- stupid social on the iOS triple, scripted taps, compared with the simulator references.
- Phase 2 rung b on the macOS triple (the changes are iOS-cut or `.iOS27` gated, except value
  links, toolbar item reuse and the large-title hit test).

## Known gaps

- `NavigationLink(value:)` in a `NavigationStack` without a `path:` binding fails loudly.
- Untitled later sections and section footers in inset-grouped lists are not measured on iOS 27
  (taken from UIKit's iOS 26.1 table numbers).
- (Resolved, `IOS27_CROSS_SCREEN.md`: the guest's light `systemBlue` was already iOS 27's
  (0, 136, 255); (0, 145, 255) is the dark value. The docked field's iOS 27 geometry is measured there.)
- The simulator's tree for Search shows the navigation bar as one `Group id=Search` and omits the
  back and filter buttons; the guest lists them.
