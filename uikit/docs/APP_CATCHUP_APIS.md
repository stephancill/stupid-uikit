# Framework APIs added for stupid social addc1744

stupid social (the stupid-app-preview target app) at `addc1744` uses framework
API the guest frameworks did not have. Each is added generally, for any app.
The app-facing `libCombine.dylib` now links the system libraries before
re-exporting libOpenCombine, so the operator's Swift runtime references bind
to libswiftCore (they bound to libOpenCombine, which machorun refused).

| API | Where | Behaviour |
| --- | --- | --- |
| `DispatchWorkItem` (`init(qos:flags:block:)`, `perform`, `cancel`, `isCancelled`, `wait`, `wait(timeout:)`, `notify(queue:execute:)`), `DispatchQueue.async(execute:)`, `asyncAfter(deadline:execute:)`, `sync(execute:)` with a work item | `full/dispatch/Dispatch.swift` | As libdispatch: `cancel()` makes later executions return at once and never interrupts a running one; notifications run after the item is performed, also when cancelled; waiters wake when it has been performed. `qos` and `flags` are accepted and, like queue QoS here, do not change scheduling. |
| `mktemp(3)` (libSystem) | `full/foundation/fm_unimplemented.c` | Was a loud stub; stupid social's launch-time `Data.write(to:options: .atomic)` reaches it through swift-foundation's `createTemporaryFile`. Implemented: replaces the trailing X's with letters from a per-process counter mixed with the pid until the name does not exist (`access`). The caller opens it `O_CREAT | O_EXCL` and retries on `EEXIST`, so the check-to-open race is handled as with libSystem's. |
| `Publishers.MergeMany` (`init(_:...)`, `init(_: Sequence)`, `publishers`, `merge(with:)`) | `full/combine/Publishers.MergeMany.swift`, compiled into the app-facing `Combine` module by `build_full.sh` | The pinned OpenCombine revision has no Merge operators. Values are serialized across upstreams and never exceed the downstream's demand (one outstanding request per upstream, at most one buffered value each); it finishes when all upstreams finish and fails, cancelling the rest, on the first failure. The hash-pinned re-export shim `full/oracle-opencombine/Combine.swift` (and so the widget and onboarding gates) is unchanged. |
| `UIFont.monospacedDigitSystemFont(ofSize:weight:)` | `uikit/Sources/OpenUIKit/UIFont.swift` | A system font with an identity of its own (not equal to `systemFont(ofSize:weight:)`; `withSize` keeps it). **Gap:** digits are measured and drawn with SF's default proportional advances. `font_metrics.json` has no tabular-figure (`tnum`) advances, so tabular widths would be invented; a fontprobe harvest of `monospacedDigitSystemFont` digit advances would close it. |
| `UICollectionView.indexPathsForVisibleSupplementaryElements(ofKind:)` | `uikit/Sources/OpenUIKit/UICollectionView.swift` | Index paths of the visible supplementary views of that kind, sorted. |
| `CALayer.insertSublayer(_:above:)`, `insertSublayer(_:below:)` | `uikit/Sources/OpenUIKit/UIView.swift` | Next to an explicit sibling sublayer; a nil sibling inserts on top / at the bottom. Explicit sublayers always draw between the layer's contents and its view's subviews, so a sibling that is a subview's backing layer fails loudly by name (as does a sibling that is not a sublayer, which Core Animation also rejects). stupid social inserts a GIF's player layer above its poster image view, after `AVQueuePlayer()` has already failed loudly. |
| `accessibilityAction(named:_:)` with a `LocalizedStringKey` or any `StringProtocol` | `uikit/Sources/SwiftUI/View.swift` | Same as the `Text` form. |
| `Animation.spring(duration:bounce:blendDuration:)`, `.smooth`, `.snappy`, `.bouncy` and their `(duration:extraBounce:)` forms | `uikit/Sources/SwiftUI/Onboarding.swift` | SwiftUI's duration/bounce springs as `spring(response: duration, dampingFraction: 1 - bounce)` (bounce 0, 0.15, 0.3 at 0.5 s). A negative bounce maps to `1 / (1 + bounce)`, which the existing spring clamps to critical damping. |
| `sensoryFeedback(_:trigger:)`, `sensoryFeedback(_:trigger:condition:)`, `sensoryFeedback(trigger:_:)`, `SensoryFeedback` | `uikit/Sources/SwiftUI/SensoryFeedback.swift` | Haptics change no pixels and no views on iOS, and the headless host has no haptic engine, so the modifiers return the content unchanged and never call their closures. |
| `searchable(text:isPresented:placement:prompt:)` | `uikit/Sources/SwiftUI/View.swift`, `Hosting.swift` | `isPresented == true` focuses the search field and shows its cancel button; beginning to edit writes `true`, cancelling writes `false`. |
| `onSubmit(of:_:)`, `SubmitTriggers` (`.text`, `.search`) | `View.swift`, `Hosting.swift`, `Values.swift` | `.text` is the old `onSubmit` (text fields and editors); `.search` runs when the user submits a `searchable` field inside the modifier. |

Native gate: `swift run appcatchupprobe` (uikit package) checks each row
except Dispatch (the native build links the host's libdispatch, whose
`DispatchWorkItem` it would test instead); `Publishers.MergeMany.swift` in the
probe is a link to the same `full/combine` source the guest compiles.
