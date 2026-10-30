# SwiftUI lazy stacks

`LazyVStack` materialises only the rows near its scroll viewport, like Apple's.
Before this, it shared the eager stack node: an app that relies on laziness,
such as stupid social's story pager (`ForEach(0 ..< modes.count * 200)` inside
a one-row paging `ScrollView`), built every row (about 800 rows, a 20,402-view
hierarchy) before its first frame.

## What is lazy

A `LazyVStack` whose content is a single `ForEach` (directly: not wrapped in
modifiers, not next to sibling views) is lazy when it is evaluated inside a
graph host (`UIHostingController`, the app host).

1. **Evaluation** (`_OpenLazyVStack._makeOpenUIKitNode`, `Onboarding.swift`)
   reads every element's ID (cheap: no element is built) and builds only the
   elements in the window the last layout requested. Before any layout that is
   the first `_OpenLazyStackState.initialWindowCount` (8) elements. Element
   scopes are the eager ones (`.vStackContent` → `.forEachContent` →
   `.forEachElement(id)`), so a row's graph identity does not depend on whether
   it was built lazily. The node is the built rows' `.vStack` wrapped in
   `.modified(_, .lazyStack(_OpenLazyStackLayout))`, so every tree visitor
   (represented views, appearance actions, preferences, button styles,
   navigation metadata) sees the built rows unchanged.
2. **Layout** (`_ViewRenderer.lazyStackMetrics` / `placeLazyStack`,
   `Hosting.swift`) measures the built rows and records each extent by element
   ID on the retained state. Every other element takes its last measured extent,
   or the average measured extent when it was never built. Fixed-height rows,
   the common case, therefore give an exact and stable content size. Rows are
   proposed the scroll viewport's height, as the scroll view's own measurement
   pass proposes its content.
3. **Viewport** (`_SwiftUILazyStackTracker`): each placed lazy stack registers
   with its nearest SwiftUI `ScrollView`, which reports every offset change
   (`scrollViewDidScroll`, programmatic `scrollTo`, and the end of placement).
   When the rows within half a viewport of the visible region are not all
   built, or the built window holds more than twice the wanted rows plus 8, the
   tracker requests the rows within one and a half viewports and invalidates
   the graph. That re-evaluation builds the new window and releases rows far
   offscreen.
4. **Scroll offset**: every graph invalidation rebuilds the hosted UIView
   tree, scroll views included. A lazy stack records its scroll view's offset
   and restores it (clamped) on the rebuilt scroll view, so materialising rows
   does not jump back to the top.

Every element is also a `ScrollViewReader` target by its `ForEach` ID at its
(estimated) frame, so `scrollTo` reaches rows that are not built; an explicit
`.id(_:)` on a built row keeps its exact frame.

## State of unloaded rows

A row that leaves the window keeps its `@State` (and other graph state stored
by path) while its ID is still in the data: the stale-state sweep in
`_OpenGraphHost.evaluate` skips state below a lazy stack's
`.forEachElement(id)` scope for IDs it still contains. Scrolling back shows the
row as it was, matching Apple's lazy stacks in practice. Tasks, Combine
subscriptions, `onChange` values and represented views/controllers are not
retained: they end when the row is released and restart when it is rebuilt
(`onAppear`/`onDisappear` follow the row). Removing the ID from the data
releases its state.

## What stays eager

- Content that is not a lone `ForEach`: static rows, a header plus a
  `ForEach`, several `ForEach` siblings, `Section`, or a `ForEach` with
  modifiers applied outside it.
- A lazy stack whose data fits the initial window and that has never been laid
  out lazily produces exactly the eager `.vStack` node, so small stacks (Focus
  onboarding, What's New) render byte-for-byte as before.
- A lazy stack outside a SwiftUI `ScrollView` (directly in a hosting view, a
  `List` row, a plain container) has no viewport; its first layout requests
  every element.
- Without a graph host (a node built outside `UIHostingController`) there is no
  invalidation route, so the stack builds eagerly.
- `LazyHStack`, `LazyVGrid`, `LazyHGrid` and `List` have no lazy path in
  openuikit (`List` rows are built eagerly through `.list(rows:)`). Horizontal
  `ScrollView` axes are recorded only, so a lazy stack inside one tracks the
  vertical viewport.

## Known differences from Apple

- The window changes on the next host turn after the viewport leaves it, so a
  fast programmatic jump shows unbuilt rows for one turn.
- Re-windowing rebuilds the hosted UIView tree (as every graph invalidation
  does), which ends an in-flight scroll gesture or deceleration. Hysteresis
  (half a viewport required, one and a half built) keeps that to once every
  viewport or so of scrolling.
- Pinned section headers/footers (`pinnedViews`) are recorded only.
- Estimates for never-built rows are the plain average of measured rows;
  variable-height rows can shift content size as they are built.

## Gate

`swift run swiftuilazyprobe` (uikit package, native Linux or macOS) hosts
fixtures in `UIHostingController`, lets invalidations run between layout
passes and fails unless: the first evaluation builds 8 of 1000 rows, the
viewport window covers 500 pt plus margin with a 50,000 pt content size, a far
scroll keeps its offset, builds the new region and releases the top rows,
`@State` survives unload and reload, `scrollTo` reaches an unbuilt row, sibling
content stays eager, an unscrolled stack builds everything, a small stack lays
out exactly as the eager stack, and an 800-row one-row pager keeps 8 rows
built.
