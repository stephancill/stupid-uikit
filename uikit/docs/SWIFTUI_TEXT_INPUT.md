# SwiftUI text input across hosting rebuilds

The SwiftUI layer renders by rebuilding the hosting view's UIView hierarchy whenever it lays
out, and every state change (every typed character is one) lays it out again. Text inputs used
to get a new `UITextField` / `UISearchBar` each time, so the field a tap focused was gone after
the first character: the window's (weak) first responder became nil, the rest of the keys were
dropped and `type` failed with "nothing has keyboard focus". Found driving stupid social's Chats
search field (`.searchable(placement: .navigationBarDrawer)`): only the first letter arrived.

## What changed

| area | change |
| --- | --- |
| retained editors | `TextField`, `SecureField`, vertical-axis `TextField` (a `UITextView`) and `.searchable` fields keep one UIKit editor per input at the input's graph identity (`_OpenGraphHost.textInputState(role:)`, `_OpenTextInputState`), as SwiftUI keeps one platform view per text input. The renderer reuses it while it is the same kind of view and updates its properties and closures in place; text is assigned only when the binding differs from the editor's (assigning moves the caret), so selection, marked text and the caret survive. Targets are installed once and read the current closures. An input that leaves the tree is retired after the evaluation: it resigns if it was focused (UIKit ends editing when a focused field is removed). |
| keeping focus in the window | `_SwiftUIHostingView.layoutSubviews` parks the retained editor that holds the window's first responder on itself before removing the old wrappers (as it already does for represented views), so it stays in the window and first responder while the hierarchy is rebuilt; placement moves it back. When placement did not put it back (the input disappeared), it resigns and is removed. Only the editor's nearest hosting view parks it. |
| focus bindings | `.focused($bool)` and `.focused($value, equals:)` are applied on every placement: true focuses the editor, false ends its editing; without a binding the user's focus is left alone. `focused(_:equals:)` losing focus clears the binding only while it still names that field (moving focus from A to B used to end with nil, because A's resignation cleared B's value). |
| `searchable(isPresented:)` | The binding is applied on every placement of the drawer or inline bar (true focuses the field and shows Cancel, false ends the search); beginning a search and Cancel write it back as before. The drawer and inline bars now also run `onSubmit(of: .search)`. |
| docked search | `.searchable` docked at the bottom (`.automatic` on a phone) already kept its `UISearchController` on the owning navigation item, so it kept focus before this change; unchanged. |
| keyboard mode | `OpenUIKitRuntime.keyboard` (`.software` default, `.hardware`). `.hardware` models an iOS Simulator with a connected hardware keyboard, which is what `stupidsim type` drives: focus, caret and keys work, no software keyboard is drawn and no scroll view is inset for one. `.software` keeps the drawn keyboard every existing gate pins (measured on an iPhone SE / iOS 26.1). |
| automation | `type` / `key` fail (exit 1) when keyboard focus goes away part-way ("keyboard focus was lost after N of M keys") instead of dropping the remaining keys; `--verify` passed before when only the first character landed. |

`TextEditor` is not implemented in this SwiftUI layer (no app in the route uses it); a
vertical-axis `TextField` is its closest form and is covered.

## Keyboard: why hardware

On a device a focused field raises the software keyboard, which covers the bottom ~40% of the
screen and lifts content anchored to the keyboard layout guide. The reference workflow is
`stupidsim` on the iOS Simulator, where "Connect Hardware Keyboard" is on by default and `type`
sends hardware key events: no software keyboard shows and the layout does not move. A preview
meant to be compared with `stupidsim` screenshots therefore types with a hardware keyboard.
stupid-app-preview's harness sets `.hardware` by default (`SSG_KEYBOARD=software` restores the
drawn keyboard, whose geometry is the SE's, not the iOS 27 reference device's). The guest does
not draw iOS's floating hardware-keyboard assistant bar (not measured).

## Verification

- `swift run swiftuitextinputprobe` (uikit package, native): tap, type, backspace and return into
  a TextField with the list filtering on the binding and the same field focused throughout;
  `@FocusState` true/false, moving `focused(equals:)` between fields with the binding kept; a
  focused field that leaves the tree resigns and leaves the window; drawer search filters a
  List while typing; docked search; `searchable(isPresented:)` true/false; software vs hardware
  keyboard. It fails on the previous renderer (the first typed character drops focus).
- stupid social on the iOS triple (scripted and live), and phase 2 rung b on the macOS triple
  (default software keyboard; the Focus text-input gates are exact-match).
