# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

**Magic-link sign-in fixed — structurally could never complete before
(2026-08-04)**, caught live by the user asking "Send magic link dies? is
that correct?" after tapping it inside the app. Investigated the full
chain across both repos before touching code: the backend
(`sparklet/src/app/login/page.tsx:38-41,51`) correctly encodes the mobile
completion URL as a `callbackUrl` query param on the emailed magic-link
itself (via Auth.js's own `nodemailer` provider), and that link correctly
lands on `/api/auth/mobile-complete` and redirects to
`sparklet-ios://auth?code=...` exactly as designed — the backend was never
the problem. The break was entirely client-side: confirming a magic-link
email means leaving the sandboxed `ASWebAuthenticationSession` browser for
Mail → Safari, a different process whose eventual `sparklet-ios://auth`
redirect that session's own `callbackURLScheme` handler can never observe
(it only fires for redirects *within* that same session). Google/Apple
OAuth never hit this because those complete without ever leaving the
session's own tab. `LoginController.requestCode()`'s
`withCheckedThrowingContinuation` had no timeout either, so it just hung
forever — matching "dies" exactly.
- New `AuthCallback.code(from:)` (`Sparklet/Auth/AuthCallback.swift`) —
  parses the one-time code out of a `sparklet-ios://auth?code=...` URL,
  mirroring the existing `InviteLink.refId(from:)` pattern exactly (a free
  function so it's unit-testable independent of the view hierarchy). 3 new
  tests in `AuthCallbackTests.swift`.
- `SparkletApp.swift`'s `RootView.onOpenURL` now checks for this case
  first (both it and `InviteLink` share the same custom scheme) — when the
  code arrives this way instead of through `ASWebAuthenticationSession`'s
  own callback, it calls a new `LoginController
  .completeSignInFromExternalRedirect(code:)`, which cancels the still-open
  session (otherwise its "Check your email" sheet is left dangling on
  screen even after the user is actually signed in — `ASWebAuthentication
  Session` is presented at the window level, not tied to SwiftUI's view
  lifecycle, so swapping `LoginView` out for `FeedView` underneath it
  doesn't dismiss it on its own) before exchanging the code the normal way.
- This required moving `LoginController` ownership from a private `@State`
  inside `LoginView` up to `RootView` (`LoginView` now takes an injected
  `controller: LoginController` instead of creating its own), so both the
  button-driven `signIn()` path and the URL-driven fallback path share the
  exact same session instance to cancel.
- **Verification is partial, documented honestly rather than overclaimed**:
  all 30 `SparkletTests` pass (27 existing + 3 new `AuthCallbackTests`),
  and the live smoke test via `xcrun simctl openurl
  "sparklet-ios://auth?code=..."` (the same technique already established
  for testing `InviteLink` locally) confirmed the app doesn't crash and the
  existing signed-in session survives the `LoginController`-ownership
  refactor unaffected — but it could not confirm the fallback branch
  actually fires, because this iOS/simulator version shows an "Open in
  Sparklet?" system confirmation sheet before delivering *any*
  `simctl openurl` custom-scheme open (unlike this project's own prior
  notes about `InviteLink` testing, written against an earlier OS version
  that apparently didn't show this), and confirming it needs a tap this
  sandbox has no Accessibility permission to script. A real end-to-end
  test (request a magic link, receive the real email, tap it, confirm the
  app actually signs in) needs the user, on a real device or by tapping
  through that confirmation sheet in Simulator.app themselves.

**Real pull-to-refresh + a more obvious category-filter pill, both
live-flagged by the user (2026-08-04)** — "The pull down to refresh the
feed also doesn't work or doesn't do anything" / "Id rather that then the
refresh button in the top bar" / "I think the categories button needs to
be a bit more obvious when some categories are selected."
- **Pull-to-refresh**: previously an explicit header button, because the
  old SwiftUI `ScrollView` + `.scrollTargetBehavior(.paging)` consumed the
  overscroll drag before SwiftUI's own `.refreshable` ever saw it
  (confirmed live 2026-07-29, documented on `FeedView.refresh()`). Once
  this session's UIKit paging rewrite landed, that conflict no longer
  applies — `isPagingEnabled` only affects snap behavior once a drag ends,
  not the overscroll drag itself — so a plain `UIRefreshControl` on the
  `UICollectionView` (`FeedPagingView.swift`) has nothing to fight. Wired
  its `.valueChanged` action to the same `FeedView.refresh()` the old
  button called. The header button is gone (`StatsHeaderView` dropped
  `isRefreshing`/`onRefresh` and `refreshButton` entirely) — asked for
  directly by the user in favor of the gesture, not a discovery made here.
  **Verified live**: rather than trust the standard `UIRefreshControl`
  target-action pattern on faith (this session's paging rewrite already
  turned up two non-obvious UIKit bugs invisible from reading the code),
  triggered it via `refreshControl.sendActions(for: .valueChanged)` — the
  exact same UIControl action-dispatch path a real drag uses, just without
  the manual drag — and confirmed via a temporary on-screen counter that
  `onRefresh` fired and `refresh()` (a real network round trip) completed,
  landing on a genuinely fresh card afterward.
- **Category-filter pill**: `StatsHeaderView`'s topic pill used the same
  neutral gray fill regardless of whether a filter was active, differing
  only in its text ("🎲" vs a bare count) — easy to miss. Gained a new
  `hasCategoryFilter: Bool` (computed in `FeedView` from
  `!viewModel.selectedCategorySlugs.isEmpty`) driving an accent-tinted
  fill + border when active, instead of only the label changing. The
  web's own version doesn't need this (its label is a real space-joined
  list of category icons, self-evidently "something is selected"), but
  this client's count-only label reads too easily as "just a button"
  without it. Verified live against the real signed-in account, which (via
  this session's earlier cross-device category-sync fix) had picked up 4
  categories selected from the user's own real usage on their phone
  between turns — confirms both the accent-pill styling and that the sync
  fix holds up under genuine live usage, not just the forced-state tests
  that originally verified it.
- All 27 `SparkletTests` pass throughout (unchanged — both are
  live-rendering/wiring changes with no new unit-testable pure logic).

**Ad slide redesigned to match a real card's shape, live-flagged by the
user after the paging rewrite fixed the top/bottom-bleed bug (2026-08-04)**
— "The sponsored card is still styled like the old things were. Is it
possible to have the ad appear like a normal card so it looks like a fact
for people to learn a bit cheeky like reddit does it." A deliberate
iOS-only departure from the web, not a port: `AdSlide.tsx` is a plain
centered "Sponsored" label with no card framing, and this project already
mirrors that (per the comment `AdSlideView.swift` had until now) — but
once every other slide went edge-to-edge with a category-tinted gradient
this session, the ad's boxed panel stood out as visibly different in a way
the web's own designer-parity reasoning didn't anticipate. Still an
honest, prominent "Sponsored" label at all times — that's an AdMob policy
line, not just a style choice — just dressed in the same chip → title →
body rhythm as `CardView`, with a bit of Reddit-promoted-post-style
self-aware humor instead of a plain uppercase "SPONSORED" tracking label.
- `AdSlideView.swift`: dropped the `Theme.panel` boxed background/border;
  chip now reads "🤑 Sponsored" tinted a fixed gold (`#fbbf24`, not tied to
  any real category — ads have none), the banner ad unit sits where a
  card's image would (same 16pt corner radius), followed by a genuine
  title/body pair ("Okay, this one's an ad" / "Someone paid for you to see
  this so the next few hundred facts stay free. Back to actual learning
  right after this.") instead of a blank centered label.
- `FeedView.currentCategoryColorHex` now returns that same gold hex for
  `.ad` (previously `nil`, meaning ads showed a flat, colorless backdrop)
  and `isEdgeToEdge` now includes `.ad` alongside every real card/
  interactive slide kind.
- **Verified live** (forced `visibleCardId` to the first ad slide, same
  technique used throughout this project): chip, gold gradient tint, title,
  and body all render correctly with no boxed panel. The actual banner
  creative still doesn't render in this sandbox — pre-existing, already
  documented under the "Native ads (AdMob) built" entry below (this
  sandbox's network egress doesn't reach Google's consent-info endpoint, so
  `canRequestAds` never resolves true here) — not a regression from this
  change, the same "fail silently" gate as before just correctly renders
  nothing where the creative would go. All 27 `SparkletTests` pass
  (unchanged — no new unit-testable logic, a live-rendering redesign like
  the other card-shape work this session).

**Feed paging rewritten from SwiftUI `ScrollView` to a UIKit-backed
`UICollectionView`, closing "Still open" #6 for good (2026-08-04)** — after
the SwiftUI-paging bottom-peek fix from earlier the same day caused a worse
regression (below), the user asked for the substantial rewrite this
project's own notes had already flagged as the real fix. Planned via
`EnterPlanMode` first (see the plan's Context section for the full
before/after reasoning) — chose a plain `UICollectionView` with a
`UICollectionViewFlowLayout` sized to the view's own `bounds` plus
`isPagingEnabled = true`, over `UIPageViewController`, specifically because
`UIPageViewController`'s relative-only dataSource and known gesture/
position-desync history would risk trading one flaky paging API for
another — the opposite of the goal. The core insight: with
`isPagingEnabled`, paging distance and cell size are the *same value by
construction* (both come from `bounds.size`), so the class of bug where
they silently drift apart (the root cause of both the bottom-peek and the
top-bleed regression) structurally cannot recur.
- New `FeedPagingView.swift` (`UIViewRepresentable` wrapping the
  `UICollectionView` + a `UICollectionViewDiffableDataSource<Int,
  FeedItem>`, since `FeedItem` was already `Identifiable & Hashable`) and
  `FeedPagingCell.swift` (a thin cell using `UIHostingConfiguration`,
  iOS 16+, to host each item kind's existing SwiftUI view unchanged — this
  app's first `UIViewRepresentable` beyond `AdSlideView`'s one-line banner
  wrapper). `FeedView.itemView(_:)` gained an explicit `isVisible: Bool`
  param (previously computed inline from `visibleCardId`) so the paging
  view can pass it through per-cell. Every other SwiftUI view in the
  feed — `CardView`, `QuizCardView`, `GuessCardView`,
  `MisconceptionCardView`, `ExplainCardView`, `AdSlideView`,
  `CheckinSlideView`/`InviteSlideView`/`GoalReachedSlideView` — is
  unchanged; none of them ever read `visibleCardId`/`ScrollViewProxy`
  directly, confirmed via research before starting.
- `FeedView`'s old `@State private var scrollProxy: ScrollViewProxy?` +
  `ScrollViewReader` became `@State private var pagingProxy:
  FeedPagingProxy?`, populated once via a callback from `FeedPagingView`'s
  `makeUIView` — the direct replacement for every old
  `scrollProxy?.scrollTo(id, anchor: .top)` call site
  (`advanceToNextItem`, the goal-reached re-snap, and the
  `load()`/`refresh()`/filter-apply/reconcile reseeds).
- **Two real bugs found and fixed only by testing this live**, both
  invisible from reading the code:
  1. Calling `onProxyReady` synchronously from inside `makeUIView` silently
     never updated the `@State var pagingProxy` it was supposed to set —
     `makeUIView` runs as part of SwiftUI's own view-update pass, and
     mutating `@State` synchronously during a view update is the classic
     "modifying state during view update, this will cause undefined
     behavior" trap. Confirmed by making the debug label read
     `pagingProxy` *live* from the view body rather than via a
     task-captured snapshot — it stayed `nil` indefinitely with the call
     inline, and immediately started reading `true` once deferred with
     `DispatchQueue.main.async`. The old `ScrollViewReader` equivalent
     (`.onAppear { scrollProxy = proxy }`) never hit this because
     `.onAppear` fires after the view has actually appeared, not during
     the render pass.
  2. Reconfiguring a cell to reflect a new `isVisible` value (needed for
     `CardView`'s one-shot depth-preference auto-apply, since
     `UIHostingConfiguration`'s content closure is evaluated once per
     `contentConfiguration` set, not continuously) via a raw
     `collectionView.reloadItems(at:)` crashed live with a real
     `SIGABRT`/`NSAssertionHandler` failure inside
     `-[UICollectionView reloadItemsAtIndexPaths:]` — twice, once called
     synchronously and again after deferring one run-loop tick. Root
     cause: mixing direct `UICollectionView` mutation calls with an
     attached `UICollectionViewDiffableDataSource` is unsupported: all
     updates have to go through the data source's own snapshot mechanism.
     Fixed by using `NSDiffableDataSourceSnapshot.reconfigureItems(_:)`
     (iOS 15+) instead, applied through the data source normally.
- **Verified live in the simulator**, the same forced-`visibleCardId`-jump
  technique used throughout this project (with a temporary on-screen debug
  label + a debug console-log pass — via `xcrun simctl launch --console`
  and `log stream`, though plain Swift `print()` turned out not to be
  reliably captured by either for this debug-dylib build; the on-screen
  label was what actually worked): a real "Guess" slide reached this way
  rendered correctly — centered content, category-tinted chip, no crash —
  with pixel-sampled confirmation of clean background at both the top and
  bottom edges, no bleed either direction on the exact case (a quiz/guess/
  misconception/explain slide) that showed both bugs before. All 27
  `SparkletTests` pass throughout (unaffected — pure data-layer,
  `FeedItemInterleaveTests` never touches the view layer).
- **Not yet verified: real swipe-gesture feel, momentum, and snap
  precision** — this sandbox has no Accessibility permission to script
  touch gestures, and that's precisely the dimension this rewrite changes.
  Installed to the user's connected iPhone for them to swipe through
  directly; genuinely confirmed only once they do.

**Reverted the bottom-peek fix — it caused a worse regression, caught live
by the user (2026-08-04)**: "When you scroll to a quiz card you can still
see the bottom buttons from the last card up the top of the screen behind
the battery." Reproduced via the same forced-`visibleCardId` debug
technique used throughout this project (tried both a raw write and
`scrollProxy.scrollTo`, same result either way): the PREVIOUS item's action
rail (share/report icons) rendered at the top of the screen, overlapping
the status bar, on a quiz slide reached after the previous day's
`.safeAreaInset(edge: .top)` + `.ignoresSafeArea(edges: .bottom)` header
restructuring (see below). Ran a controlled A/B test — same debug jump
technique, only the header structure changed: the plain
`VStack{header; ScrollView}` structure (this session's revert) never showed
the artifact; the `safeAreaInset`/`ignoresSafeArea` structure showed it on
every attempt. Reverted back to the plain `VStack` — the header sharing
layout space with the `ScrollView` is what keeps `.scrollTargetBehavior(
.paging)`'s page-height and each item's `.containerRelativeFrame(.vertical)`
height in agreement; decoupling them (to fix the smaller ~18pt bottom-peek
cosmetic issue) broke that agreement in a way that showed up as a real UI
element bleeding across page boundaries — a materially worse bug than the
one it fixed. The bottom peek is back and, per the existing "Still open" #6
entry below, is a known, accepted, lower-severity SwiftUI paging quirk (a
full fix needs a UIKit-backed page view, out of scope). All 27
`SparkletTests` pass (unchanged — layout-only revert, no logic change).

**Two more live-flagged fixes, same session (2026-08-03)**: "I don't like
the next card poking out. I also think the quiz cards and the rest of them
should be centered rather than [top] aligned."
- **Next-item peek at the bottom, fixed.** ~~Fixed~~ **Reverted 2026-08-04
  — see Status above.** The fix below caused a worse regression (the
  previous item's action rail bleeding into the top of the screen on a
  quiz slide); the peek is back until a fix is found that doesn't
  reintroduce that. Confirmed via screenshot +
  pixel sampling this was a real, consistent ~18pt sliver of the next
  item's category chip visible at the bottom of every page, not the rare
  post-programmatic-jump mis-snap "Still open" #6 already documents —
  this one showed up on a completely untouched, freshly-loaded feed.
  Root cause: `StatsHeaderView` was a sibling row above the `ScrollView`
  in a plain `VStack`, which shrank the `ScrollView`'s own bounds by the
  header's height; each page is sized via `.containerRelativeFrame(
  .vertical)` against those bounds, but the bottom safe-area inset was
  *also* separately eating into that same space, so the page ScrollView
  actually measured against was a little shorter than a true full screen
  — leaving the next item's top edge visible. Fixed in two steps, each
  verified live before moving to the next: (1) moved the header out of
  the `VStack` into a floating `.safeAreaInset(edge: .top)` on the
  `ScrollView` instead (mirrors `AppHeader.tsx`'s own `fixed inset-x-0
  top-0` floating-over-content behavior) — verified this alone did NOT
  fix the peek, ruling out "header eating layout space" as the sole
  cause; (2) added `.ignoresSafeArea(edges: .bottom)` to the `ScrollView`
  on top of that — tried plain `.ignoresSafeArea()` (all edges) first,
  which fixed the peek but regressed the header up underneath the status
  bar (confirmed live via screenshot), then narrowed it to `.bottom`
  only, which fixed the peek with the header still correctly positioned
  below the status bar (also confirmed live, plus a pixel-level bottom-
  edge scan showing flat background color all the way to the true
  bottom with no chip-color transition anywhere).
- **Quiz/guess/misconception/explain now vertically centered.** Checked
  the web: `QuizView.tsx`/`GuessView.tsx`/`MisconceptionView.tsx`/
  `ExplainView.tsx` all use `justify-center`, while `LearnCard.tsx` (the
  plain reading card) uses `justify-end` — these four interactive slide
  kinds were never supposed to be top-aligned like the plain card is.
  Changed all four views' `.frame(maxHeight: .infinity, alignment:
  .top)` to `.center` and removed the trailing `Spacer(minLength: 0)`
  each one had (which existed specifically to push content to the top
  under the old alignment — centering doesn't need it). `CardView`
  itself is deliberately unchanged — its top alignment is load-bearing
  for the `maxBodyLines`/"Read more" truncation math, and the user's
  phrasing ("quiz cards and the rest of them") was about the interactive
  slide kinds, not the plain reading card. Verified live (forced
  `visibleCardId` to the first quiz slide, the same technique used
  throughout this project): content now sits centered with balanced
  space above and below, instead of pinned to the top with a large empty
  gap underneath. All 27 `SparkletTests` pass (unchanged — both fixes are
  live-rendering layout fixes with no new unit-testable pure logic).

**Three parity fixes prompted by the user, same session (2026-08-03)**:
- **Category filter now syncs cross-device, closing a gap the user asked
  about directly** ("will changes to a user's category selection also be
  pulled and be consistent with the web app?"). Checked both sides:
  `Feed.tsx`'s mount effect treats `GET /api/interests` (the `UserInterest`
  table) as the durable cross-device source of truth, pulling it down and
  overriding `localStorage` if they differ, and POSTs on every change
  including clearing back to "Everything." iOS's `FeedViewModel` only ever
  read/wrote its own local `CategoryPreference` (`UserDefaults`) — it never
  fetched `GET /api/interests` at all, and its POST was gated on
  `!slugs.isEmpty`, so a clear never reached the server either. Fixed:
  `OnboardingAPI.fetchInterests` (new), a new
  `FeedViewModel.reconcileCategoryFilterWithServer()` mirroring the web's
  mount effect (called once at launch, after the local-storage-instant
  first paint, from `FeedView`'s launch `.task`), and
  `applyCategoryFilter` now POSTs unconditionally instead of only when
  non-empty. **Verified live against the real production account**, in
  three separate launches (the same forced-then-reverted technique used
  throughout this project — this time forcing `FeedViewModel.init`'s
  `selectedCategorySlugs` to `[]` to simulate a brand-new device with zero
  local state, rather than a UI state): pushed a real "Code" filter from
  iOS (confirmed via the topic pill going from 🎲 to a real "1" and the
  feed actually filtering to Code-only cards), then a separate launch
  starting from simulated zero local state correctly pulled "Code" back
  down from the server and re-filtered — proving the full round trip
  works both directions — then restored the account back to its original
  unfiltered state. All 27 `SparkletTests` pass.
- **`FeedSettingsView`'s Apply button now matches a same-day web change**
  the user flagged ("The show everything button has been updated... to
  apply changes rather than just resetting it"). Traced it to `sparklet`
  commit `8068cd8` ("Replace dynamic 'Show me everything' button with a
  static Apply + live feedback") — the web's confirm button used to carry
  a dynamic label ("Show me everything"/"Show N topics") that duplicated
  the meaning of the dedicated Random/Everything button above it; now a
  plain static "Apply" action plus a small "Applying: Everything"/
  "Applying: N topics" feedback line. Ported the same change to the
  toolbar confirmation button (static "Apply" replacing the old dynamic
  `applyLabel`) plus a matching `Text("Applying: \(applyingSummary)")` at
  the bottom of the sheet's content. Verified live (forced the sheet open
  via the same technique) — toolbar now reads a plain "Apply".
- **First-visit swipe hint ported**, closing a gap the user flagged
  directly ("We are also missing the swipe animation when you first open
  the app to explain what you are meant to do"). Mirrors `Feed.tsx`'s
  one-time "Start swiping to learn" hint: a `👆` that rises while
  twisting with a fading vertical trail behind it, looping until
  dismissed by the first real swipe, gated on the same `"sparklet.hinted"`
  key name the web uses for its own `localStorage` entry (not shared
  storage — same parity-only precedent as `DepthPreference`/
  `CategoryPreference`). New `SwipeHintOverlayView.swift` ports
  `globals.css`'s `swipe-hand`/`swipe-trail` keyframes (translateY+rotate+
  opacity, ~1.7s loop) onto a single shared `PhaseAnimator` — deliberately
  one animator driving both the hand and trail together rather than two
  independent ones, since two separate `PhaseAnimator`s would each run
  their own internal clock and drift out of sync with each other over
  time. Gated on `viewModel.items.count > 1` (mirrors the web's
  `cards.length > 1`) and shown/dismissed via `FeedView`'s existing
  `visibleCardId` — the closest signal this paging `ScrollView` exposes
  for "the user swiped" (settles on a new item), not truly identical to
  the web's `onScroll` (which fires on the very first scroll pixel, before
  settling) but functionally equivalent for a one-time hint. **Verified
  live in the simulator**, three separate runs: a true fresh install (bare
  `UserDefaults`, not just a forced `@State`) showed the hand mid-animation
  and the "Start swiping to learn" pill correctly; a second screenshot 1s
  later showed the hand faded out mid-loop, confirming the animation is
  actually progressing, not a static frame; a temporarily-added 2-second
  delayed simulated swipe (forcing `visibleCardId` to the next item,
  reverted after) confirmed the hint correctly disappears on "swipe" and —
  via one more relaunch with no debug code active — correctly does NOT
  reappear afterward, confirming the persisted dismissal. All 27
  `SparkletTests` pass (unchanged — no new unit-testable pure logic in
  this particular piece, a live-rendering animation fix same as the
  card-truncation fix earlier in this file).

**Card visual redesign to match the web app's look (2026-08-03)** — flagged
by the user: the app "feels and looks different from the main webapp," cards
had a flat boxed panel that filled the screen instead of the web's per-category
gradient backdrop.
- `CardView` (`Features/Feed/CardView.swift`) no longer draws a boxed
  `Theme.panel` background + `Theme.border` outline behind each card. Instead
  it draws `LearnCard.tsx`'s own backdrop — a diagonal
  `linear-gradient(160deg, categoryColor@15% 0%, background@45%, background@100%)`
  wash of the card's own category color, edge-to-edge, fading into the app's
  background — via a new `categoryGradient` computed property.
- The category chip (e.g. "🚀 Space") is now tinted by the category's own
  `colorHex` (20%-opacity background, full-color text), mirroring the web's
  `${colorHex}33` bg / `colorHex` text, instead of a generic gray pill.
  Applied consistently to `CardView`, `FullCardSheetView` (the "Read more"
  sheet), and `CardDetailView` (the related-card detail screen) — the latter
  intentionally keeps a flat (non-gradient) background, matching the web's
  own `/card/[id]` page, which also has no backdrop gradient, only the
  colored chip.
- `FeedView`'s `ForEach` no longer applies its outer horizontal/vertical
  padding to `.card` items specifically, so the gradient truly bleeds to the
  screen edges rather than stopping at an inset box — every other slide kind
  (quiz/guess/ad/checkin/etc.) keeps its existing boxed-panel padding
  unchanged, since the user's complaint was specifically about cards.
- No change to `maxBodyLines`/`isBodyTruncated`'s measurement math — both
  already derive from the card's own measured width/height via the existing
  `GeometryReader`, so they automatically picked up the ~32pt of extra width
  from dropping the outer padding without needing a formula change.
- **Verified live in the simulator** against the real signed-in account: a
  real "Code"-category card ("The 370-Million-Dollar Number Overflow")
  rendered with no visible panel/border, content flush to the screen edges,
  a teal-tinted category chip, and a pixel-sampled confirmation of the
  gradient itself — `(16, 24, 22)` near the card's top-left (a teal tint)
  versus the pure `(10, 10, 10)` background elsewhere, fading out toward the
  bottom/right as designed.
- **Follow-up, same day**: the user pointed out the gradient should also
  show behind the top nav bar (`StatsHeaderView`), and that the guess/quiz/
  misconception/explain slides still looked like boxed cards rather than
  the same cleaned-up look. Checked the web (`QuizView.tsx`/`GuessView.tsx`/
  `MisconceptionView.tsx`/`ExplainView.tsx`) — all four are the exact same
  `h-dvh w-full` full-bleed shape with their own per-category
  `linear-gradient` backdrop as `LearnCard.tsx`, none of them a boxed panel;
  `AppHeader.tsx` itself is `fixed inset-x-0 top-0` with no background of
  its own, floating over whichever slide's gradient is showing through.
  - Moved the gradient from being painted per-card (`CardView`'s own
    `.background`) to a single shared backdrop at the `FeedView` level —
    a new `feedBackdrop` computed from whichever item is currently visible
    (`currentCategoryColorHex`, switching over every category-bearing
    `FeedItem` case), painted as the bottom layer of a `ZStack` with
    `.ignoresSafeArea()`, with the header+scroll content stacked on top of
    it instead of a sibling with its own opaque `Theme.background`. Since
    this is a paging feed with only one item ever visible at a time, one
    global layer keyed off `visibleCardId` is equivalent to a per-item
    background, except it also reaches the area behind the header, which a
    background scoped to an individual item's own frame structurally could
    not.
  - `QuizCardView`/`GuessCardView`/`MisconceptionCardView`/
    `ExplainCardView` all dropped their own `Theme.panel` boxed background
    + border (now redundant with the shared backdrop) and had their
    category/quiz chips recolored to the category's own `colorHex`, mirroring
    the web exactly (a `Review` slot keeps a fixed violet badge regardless
    of category, matching `QuizView.tsx`'s own branch). Their answer-result
    panels (the "✅ Nailed it" / reveal boxes) gained an explicit
    `Theme.panel.opacity(0.9)` background, mirroring the web's own
    `rounded-xl bg-neutral-900/90 p-4` reveal box — otherwise that text
    would've floated directly on the gradient with no visual separation
    now that the outer panel is gone.
  - `FeedView`'s `ForEach` now treats every category-bearing item kind
    (card/quiz/reviewQuiz/guess/misconception/explain) as edge-to-edge (no
    outer padding), via a new `isEdgeToEdge(_:)` helper — `.ad`/`.checkin`/
    `.invite`/`.goalReached` (no per-category color to show) keep the boxed
    panel treatment unchanged, since those weren't part of what was flagged.
  - **Verified live**: a full-opacity debug pass on the gradient (reverted
    after) confirmed the backdrop paints correctly across the entire screen
    including behind the status bar/header, ruling out a structural bug
    before trusting the intended subtle 15%-opacity version (which is hard
    to distinguish from compression artifacts in a screenshot at that
    opacity). Separately, temporarily force-jumping `visibleCardId` to the
    first `.guess` item (same forced-then-reverted technique used
    throughout this project) confirmed a real guess card ("How many toes do
    many of the famous cats at Ernest Hemingway's Key West home have?")
    renders with no boxed panel, a category-tinted "🎭 Guess" chip, and the
    gradient visible behind the header — then reverted the debug jump and
    rebuilt clean.

**Real app icon added, and five bugs/gaps fixed from live user feedback
(2026-08-01)**:
- **App icon**: the project had no `AppIcon` configured at all (no
  `.xcassets`, no `ASSETCATALOG_COMPILER_APPICON_NAME`) — shipped with the
  blank Xcode placeholder. Fixed with the real Sparklet brand mark (the
  violet sparkle already used for the web's PWA icons, `sparklet` repo's
  `public/icon-512.png`), upscaled to 1024×1024 and stripped of its alpha
  channel (required for the single-size App Store icon). Verified live:
  the real icon renders correctly, masked with rounded corners, on the
  simulator home screen.
- **Explain-it-back "I don't know" showed no information** — the backend's
  `feedback` string for a skip is deliberately generic ("No worries —
  here's a reminder..."; see `src/app/api/explain/[cardId]/answer/
  route.ts`), and the web pairs it with the card's own body text in a
  separate UI state; `ExplainCardView` was showing only the generic
  `feedback` string alone. Fixed by tracking whether the current result
  came from a skip (`wasSkipped`) and showing `prompt.body` in that case,
  matching `ExplainView.tsx`'s "revealed" state.
- **"Read more" truncated cards well before the page was actually full**,
  leaving large dead gaps of blank space below it — `maxBodyLines` was a
  flat guess (6 lines with an image, 10 without) rather than a real
  measurement. Replaced with a dynamic calculation: `CardView` now
  measures its own real height (extending the existing `cardWidth`
  GeometryReader to also capture `cardHeight`), then computes exactly how
  many body lines fit after the chip/image/title/"Read more"-reserve/
  source have taken their real (UIKit-measured, not guessed) share.
  Verified live: short-titled/imageless cards that used to truncate now
  render in full; a forced very-long body still truncates cleanly with no
  overflow past the panel edge.
- **No way to filter the feed by topic** — `GET /api/feed`'s `categories`
  param and `FeedAPI.fetchFeed(categorySlugs:)` already existed
  client-side with zero UI to drive them. New `FeedSettingsView` (mirrors
  `CategorySheet.tsx`'s combined "Your feed" sheet: topic multi-select +
  reading depth + daily goal, all three in one place like the web bundles
  them) reachable from a new topic-filter pill in `StatsHeaderView`
  (leftmost in the row, mirroring the web's own placement — shortened to
  an emoji/count rather than the web's space-joined category icons, since
  a spelled-out label wrapped the XP label onto two lines once the header
  had 6 elements instead of 5, confirmed live). New `CategoryPreference`
  (mirrors `sparklet.categories`) and `FeedViewModel.applyCategoryFilter`
  (persists the filter, full-reset reload, best-effort re-syncs
  `POST /api/interests`). `DailyCardGoal` and `DepthPreference` — both
  already had backing logic from earlier passes but no UI to change them
  — are now actually adjustable through this same sheet. Verified live
  end-to-end: selecting "Space" and applying genuinely filtered the real
  production feed to only Space-category cards; reading depth correctly
  shows Deep/Extra Deep as locked for a non-premium account; the daily
  goal chips correctly highlight the active value.
- **Scroll glitch after programmatic feed navigation**: tapping "Keep
  going anyway"/"Maybe later" on the checkin/invite/goalReached slides
  (and, separately, the automatic insertion of a `.goalReached` slide
  while already sitting on the triggering card) could leave the next page
  mis-snapped — image/category chip cut off at the top, next item peeking
  in at the bottom. Investigated extensively (7 different mitigations
  tried: default/no animation, `.scrollPosition(id:)` anchor variants,
  `ScrollViewReader.scrollTo`, sequential pre-settling, a corrective
  re-snap, `.defaultScrollAnchor(.top)`) — confirmed via a debug harness
  that this reproduces even for a plain quiz→card jump with no recap
  slide involved at all, meaning it's a general SwiftUI limitation with
  programmatic `.scrollPosition(id:)` writes under
  `.scrollTargetBehavior(.paging)`, not something specific to the new
  slide kinds — the same underlying issue as the rare manual-swipe-reversal
  glitch noted below (#6), now confirmed far more general and easily
  reproducible than that note assumed. **Not fixed** — a full fix likely
  means replacing the paging `ScrollView` with a UIKit-backed page view,
  out of scope for this pass. The best available mitigation (a plain
  `visibleCardId` write, no animation, `.defaultScrollAnchor(.top)`) is
  in place; it still navigates to the right item, just occasionally
  mis-snapped, matching #6's existing "should self-correct" character.

**Remaining feed slide kinds built (checkin/invite/goalReached),
2026-08-01** — the last of `Feed.tsx`'s non-card slide kinds this client
didn't have, closing the "Not scoped into this pass" note in the ads
entry below. All three are client-side-only interleave slots, same shape
as `.ad` — no server model, computed fresh in `FeedViewModel.buildItems`
every rebuild.
- **A real bug in `countsAsCard` found and fixed along the way**: iOS's
  `StatsHeaderViewModel.apply` had a `countsAsCard` flag that excluded
  quiz/guess/misconception/explain answers from bumping the local
  `cardsToday` count — but the backend's actual `getCardsToday` (`sparklet`
  repo, `src/lib/xp.ts`) counts every `XpEvent` row in the window
  regardless of source ("Any new XP-awarding action implicitly becomes one
  more 'card' toward that goal"). The flag was based on a misreading of
  that invariant, not an intentional distinction — confirmed by reading
  `xp.ts` directly rather than trusting the existing code comment, since
  `goalReached` genuinely depends on `cardsToday` being accurate to fire
  at the right moment. Removed the flag entirely (`apply` now always
  counts an award, and returns whether that call crossed the goal) rather
  than keep dead config every call site had to pass correctly.
- `DailyCardGoal` (`Features/Feed/DailyCardGoal.swift`) mirrors
  `CategorySheet.tsx`'s `sparklet.dailyGoal`/`DEFAULT_DAILY_CARD_GOAL` and
  `Feed.tsx`'s `sparklet.goalHit` date guard. The web lets a user adjust
  the goal via a settings sheet this client doesn't have — out of scope
  here, so `current` always reads the same default (10) for now.
- `FeedViewModel` gained session-recap state (`sessionViews`,
  `sessionTopicCount`, mirroring `Feed.tsx`'s `sessionViewsRef`/
  `sessionCategories`) plus `markSessionView`/`addSessionCategory`/
  `markGoalReached`. `markSessionView` fires unconditional of the 4.5s
  read-dwell gate `trackView` enforces — mirrors the web's `markViewed`,
  a deliberately different (looser) signal than "the server counted this
  as read."
- `buildItems` gained `showInviteCard`/`goalReachedAfter` params:
  `checkin` fires unconditionally every 15 cards; `invite` once at card
  12, gated by an every-other-session `UserDefaults` counter
  (`sparklet.inviteSessionCount`, resolved once in `FeedViewModel.init`);
  `goalReached` at the cards-array position snapshotted the instant the
  goal was crossed (`markGoalReached`), same "insert at the position
  sessionViews happened to be at" approximation the web itself uses.
  5 new interleave tests (`FeedItemInterleaveTests`) plus 3 for
  `DailyCardGoal`'s pure UserDefaults logic — 27 total, up from 19.
- New `RecapSlideViews.swift` (`CheckinSlideView`/`InviteSlideView`/
  `GoalReachedSlideView`) — styled as the same boxed panel every other
  feed slide uses (`AdSlideView`'s own precedent), not the web's plain
  edge-to-edge section. The web's `ConfettiBurst` celebration polish
  (`Celebration.tsx`) is still deliberately not ported, unchanged from
  the original scoping note.
- **Verified live against real production data** — not by scrolling
  15+ cards deep (no tap automation in this sandbox), but by temporarily
  lowering the interleave thresholds (`checkinEvery`/`inviteAfterCards`
  to 3/2, forcing `showInviteCard = true`, seeding `goalReachedAfter = 4`)
  so all three slides landed inside the very first small batch, then
  separately seeding `visibleCardId`'s initial value to
  `items.first { case .invite = $0 ... }` (and the `.checkin`/
  `.goalReached` equivalents) across three separate builds — the same
  temporarily-hardcoded-then-reverted technique used throughout this
  project, just searching by case instead of guessing an index (a first
  attempt hardcoded index `2`, which landed on a plain card instead — the
  real feed's reviewQuizzes/guesses/misconceptions shift indices in ways
  a hand-computed guess doesn't account for; searching by item kind
  sidesteps that entirely). All three slides rendered correctly against
  the real signed-in account: invite showed the 🎁 copy with a working
  `ShareLink`, checkin showed "You've learned 0 things across 0 topics"
  (correctly 0 — jumping straight to the slide skipped ever viewing a
  real card this launch, so nothing had been counted yet), and
  goalReached showed the account's real `cardsToday` (7) against the
  real default goal (10). All 6 threshold/gate overrides fully reverted
  afterward; confirmed clean with one more build showing normal first-item
  feed behavior. All 27 `SparkletTests` pass.

**Depth-preference memory built, closing "Still open" #11 (2026-08-01)** —
ports `LearnCard.tsx`'s remembered-depth-switch behavior: a manual
SIMPLE/DEEP/EXTRA_DEEP tap is also a preference, auto-applied to future
cards as they scroll into view, until reset back to Standard. Pure
client-side port, no backend change (reuses the existing
`POST /api/cards/[id]/depth`).
- `DepthPreference` (`Features/Feed/DepthPreference.swift`) wraps
  `UserDefaults` under the same `"sparklet.depth"` key name the web uses
  for its `localStorage` entry (the two stores aren't shared — same name
  purely for parity/debuggability). `get()` returns `nil` for "never set,"
  which callers treat identically to an explicit `.standard` — both mean
  "don't auto-apply," mirroring the web's `pref !== "SIMPLE" && ... →
  return` early-out.
- `CardView.chooseDepth` (the manual-tap path) now writes the preference
  before applying it; the actual apply logic was split out into a new
  `applyDepth`, which the auto-apply path calls directly so it doesn't
  re-write the preference on every card — mirrors the web's
  `chooseDepth`(writes + applies) vs. `setDepth`(applies only) split
  exactly.
- The trigger is a new `isVisible: Bool` param `CardView` now takes from
  `FeedView` (`item.id == visibleCardId`, the same source of truth
  `FeedView`'s own read-tracking already uses) — **not** a plain
  `.onAppear`, because SwiftUI's `LazyVStack` keeps a couple of
  off-screen cards alive in a prefetch buffer; auto-applying depth for
  those would silently trigger real card-variant generation for cards the
  user never actually saw, the same "claiming something that isn't true"
  integrity issue `FeedView`'s own read-tracking comment already flags
  for view-dwell. A `.task(id: isVisible)` + one-shot `@State` guard
  mirrors the web's `IntersectionObserver(threshold: 0.6)` firing once
  then `disconnect()`-ing, rather than re-firing every time a card
  scrolls back into view.
- The auto-apply gate reuses `CardView`'s existing `isLocked(_:)` premium
  check unchanged (not a second, possibly-drifting copy of the same
  condition) — mirrors the web's own note that a lapsed subscriber's
  saved DEEP/EXTRA_DEEP preference must not silently 402-loop on every
  card in their feed.
- New `DepthPreferenceTests` (3 cases: never-set → nil, set-then-get
  round-trips, resettable back to `.standard`) — genuinely unit-testable
  pure logic, unlike the `CardView` layout-only fixes above, which had no
  testable surface.
- **Verified live against real production data**, without forcing any
  view state: seeded `DepthPreference.set(...)` once at app launch (a
  temporary, reverted-after line in `SparkletApp.init`), then let the
  *real* `isVisible` wiring do the rest — no hardcoded `@State`, since
  this feature's whole point is reacting to a real card becoming visible.
  First tried `.deep`: correctly did **not** auto-apply (rail stayed on
  the 📖 Standard icon) because the signed-in test account isn't a
  premium subscriber — confirms the reused `isLocked` gate works exactly
  like the already-verified manual switch. Re-tested with `.simple`
  (unlocked for everyone): the rail settled on the ✨ icon and the
  card's title/body swapped to a real simplified variant ("Your teeth are
  the only body parts that cannot heal themselves" → "Teeth Cannot Fix
  Themselves") with zero taps — confirming the full pipeline
  (read-preference → gate-check → fetch-or-cache → display-swap →
  icon-update) end-to-end. Reinstalled the app afterward to clear the
  seeded `UserDefaults` value before finishing (a plain code revert alone
  doesn't undo state a previous run already wrote to the device) —
  confirmed clean by relaunching and seeing a real card render with no
  depth auto-applied and the Bearer-token session still intact (Keychain
  survives app reinstall, `UserDefaults` doesn't). All 19 `SparkletTests`
  pass (3 new).

**Card-detail screen built, closing "Still open" #10 (2026-08-01)** — the
🧭 related-cards `Menu` in `CardView` was informational-only (titles/icons,
no link) because no card-detail screen existed in iOS to link to. Two
pieces:
- **Backend** (`sparklet` repo): new `GET /api/cards/[id]`
  (`src/app/api/cards/[id]/route.ts`, committed `9a9ee46`, deployed) — the
  web has no equivalent JSON route for a single card (`/card/[id]/
  page.tsx` queries Prisma directly since it renders HTML server-side), so
  this is new surface, not a port. Returns the same `FeedCard` shape
  `GET /api/feed` already produces (reusing its `related` derivation via
  `getRelatedCards`) specifically so the iOS client could decode the
  response straight into its existing `FeedCard` model rather than adding
  a second one. 401s when signed out — the iOS client is always
  authenticated by the time it can reach this screen, same reasoning as
  Invite's own no-login-redirect-gate note above. `npx tsc --noEmit` and
  `npm run lint` clean; smoke-tested against a local dev server before
  pushing (a pre-existing, unrelated local-DB migration drift —
  `User.tzOffsetMinutes` missing — blocked a full authenticated round trip
  against the *local* server specifically; fixing that drift and forging a
  session row directly were both out of scope/correctly declined by the
  session's own safety tooling, so this route's auth wiring was instead
  confirmed via its 401-when-signed-out path, which is the exact same
  `auth()` pattern already proven live in production by the existing
  `vote`/`save`/`comments` routes it sits next to).
- **iOS**: new `CardDetailView.swift` — fetches the single card via a new
  `CardActionsAPI.fetchCard`, then renders the full untruncated card (no
  `maxBodyLines`/"Read more" truncation — unlike the feed's `CardView`,
  this screen has no fixed one-page height budget to protect) plus its own
  vote/depth-switch/comments/save/share/report row and a real "Connects
  to" list. Presented as a `.sheet` from `CardView`'s 🧭 menu, matching
  every other secondary screen in this app (Comments/Report/Notifications/
  etc. are all sheets, not `NavigationStack` pushes); a related card
  tapped *from within* this screen opens another `CardDetailView` sheet
  the same way, chaining to arbitrary depth via a locally scoped
  `Identifiable` route. The action-rail state/logic (vote/save/depth/
  comments/report) is deliberately duplicated from `CardView` rather than
  extracted into a shared component — see the comment at the top of
  `CardDetailView.swift` for why (the two layouts differ enough that a
  shared component would need nearly as much layout-specific plumbing as
  it'd save, for exactly two call sites).
- **Verified live against real production data** (not the dev server —
  see the backend note above): forced `CardView`'s related-menu sheet open
  via the same temporarily-hardcoded-`@State` technique used throughout
  this project, screenshotted, then reverted. **First attempt showed a
  real-looking but ultimately harness-induced bug**: setting the forced
  `@State` at `init` time (rather than after a delay) opened the sheet
  before the surrounding feed's layout had settled, and the rendered
  screenshot showed every line of text and the action-row icons clipped
  hard against the left screen edge with no margin — looked exactly like
  a genuine layout bug. Re-tested with the same forced state instead set
  after a 2-second delay in a `.task` (matching how a real menu tap would
  actually fire, always well after initial layout) and the glitch
  completely disappeared — proving it was an artifact of presenting a
  sheet synchronously at the view hierarchy's very first layout pass, not
  a `CardDetailView` bug, and not something a real user tapping the menu
  could ever trigger. Once confirmed, two different real cards rendered
  correctly end-to-end this way: a text/image card ("This Beetle Uses
  Infrared Sensors to Hunt Forest Fires") and a video-thumbnail card ("How
  British Intelligence Used a Corpse to Trick Hitler"), both showing the
  correct image, full untruncated body, working vote/depth/comments/save/
  share/report row, and a real "Connects to" related-card link at the
  bottom. All 16 `SparkletTests` still pass (unchanged — no new
  unit-testable pure logic here, same as the `CardView` truncation fix
  above).

**Invite Universal Links: AASA file published, closing "Still open" #7
(2026-08-01)** — the last missing piece, per the `DEVELOPMENT_TEAM` entry
below: `sparkletapp.com/.well-known/apple-app-site-association` now exists
and is live in production. Built as a Next.js Route Handler
(`sparklet` repo, `src/app/.well-known/apple-app-site-association/
route.ts`, committed and pushed `67940c1`, deployed via Coolify) rather
than a static file in `public/` — this Next.js version's own bundled docs
(`node_modules/next/dist/docs/.../backend-for-frontend.md`) list
`.well-known` as a supported Route Handler segment, and a Route Handler
guarantees the `Content-Type: application/json` response Apple's CDN
expects regardless of static-file-serving defaults. `appID` is
`"K4JYC7UP3A.com.sparklet.ios"` (the Team ID set below + this app's bundle
ID); `paths` is scoped to `["/invite/*"]` only — every other route (feed,
profile, terms, etc.) should keep opening in Safari, unchanged from
today. Apple's own docs wouldn't render through this session's fetch
tool, so the exact schema (`applinks.details[].appID`/`.paths`, `apps: []`
at the top level) was cross-checked against several real, currently-live
AASA files on GitHub (`bryceco/GoMap`, `meganz/webclient`, etc. — found via
`gh search code`) rather than guessed from training data alone. **Verified
against real production**: `curl https://sparkletapp.com/.well-known/
apple-app-site-association` returns `200`, `content-type: application/
json`, and the exact expected body — confirmed only after polling through
~9 attempts (~2 minutes) for the Coolify deploy to actually roll out, not
immediately after the push landed. `npx tsc --noEmit` and `npm run lint`
both clean in the `sparklet` repo; also smoke-tested against a local
`npm run dev` server before pushing. **Not verified — needs a real
device**, unchanged from what "Still open" #7 already flagged: the
simulator can't validate a genuine AASA fetch against Apple's actual CDN
(`app-site-association.cdn-apple.com`), which is the one remaining step
before a tapped `sparkletapp.com/invite/<id>` link is confirmed to
actually open the app instead of Safari on a live device.

**Fixed: `CardView` clipped unusually long cards instead of scrolling within
their page (2026-07-30)** — closes "Still open" #3. A nested `ScrollView`
was tried previously and reverted (it fights `.scrollTargetBehavior(.paging)`
for the drag gesture); this instead caps the body to `maxBodyLines` (6 with
an image, 10 without — a photo eats into the one-page height budget) and
shows a "Read more" button, but only when that limit actually cut something
off. Detecting that turned out to be the hard part:
- **First attempt (wrong, caught by live testing, not by review): a pure
  SwiftUI height-comparison trick** — two hidden `Text` copies (one
  `.fixedSize`, one `.lineLimit`-constrained) behind the visible text via
  `.background()`, comparing their `GeometryReader`-reported heights via
  `PreferenceKey`s. This looked reasonable and built cleanly, but
  `.background()` sizes its content to fit the host view, so the
  "unconstrained natural height" copy never actually got to report its
  true size — `isBodyTruncated` was always false. Screenshotting the real
  signed-in app (see below) showed the tell: a real card's body visibly
  ended in a truncated "…" with no "Read more" button below it, and a
  large unexplained blank gap where the hidden measurers sat.
- **Fixed by dropping SwiftUI layout measurement entirely**: `CardView`
  now measures its own on-screen width once via a `GeometryReader` in
  `.background()` (this one just reads the host's own resolved size —
  no `fixedSize` fight — so it's reliable), then computes truncation with
  plain UIKit math (`NSString.boundingRect` against `UIFont.preferredFont
  (forTextStyle: .body)`, compared to `maxBodyLines * font.lineHeight`).
  Deterministic, no SwiftUI background/fixedSize ambiguity to get wrong.
- The untruncated escape hatch is a `.sheet` (`FullCardSheetView`) showing
  the full card in a plain, non-paging `ScrollView` — safe because a sheet
  sits above the feed in its own gesture space, unlike a scroll nested
  directly inside the paging container.
- **Verified live twice against the real production account** (both times
  by temporarily hardcoding a `@State` default and reverting, same
  technique used throughout this project): the first pass showed the bug
  above (truncated text, no button, stray gap) on a real card about
  Nozick/Chamberlain; after the fix, a real card ("Snails Have Thousands
  of Microscopic Teeth") correctly showed a "Read more" button exactly
  where the body was cut off, and tapping it open (forced via `@State`)
  correctly rendered `FullCardSheetView` with the complete, untruncated
  text of a different real card. All 16 `SparkletTests` still pass
  (unchanged — this fix had no unit-testable pure-logic surface, it's a
  live-rendering layout fix, so live screenshotting was the only way to
  actually catch the first attempt's bug rather than just asserting it
  away in a way that would've been consistent with the broken version too).

**Fixed: feed dead-ended after ~10-15 swipes instead of scrolling
indefinitely (2026-07-29)** — flagged by the user ("I want it to keep
loading cards in so you can scroll for hours if you want to"). Root cause:
`FeedAPI`/`FeedResponse` already modeled the backend's `allowRepeats`
param and `exhausted` flag (`sparklet/src/lib/feed.ts`), but
`FeedViewModel` never used either — once an account ran out of genuinely
unseen/due cards, the server just returned an empty batch and the feed
silently stopped growing.
- `FeedViewModel` now tracks `exhausted`; once a pagination call reports it
  with an empty batch, the very next call (and every one after) passes
  `allowRepeats: true`, recirculating previously-seen cards — mirrors the
  web's own fallback (`Feed.tsx`'s "Review cards I've seen" button) except
  automatic rather than requiring a tap, since an endless feed is this
  app's whole product shape, unlike the web's fixed-deck-then-CTA pattern.
- **A second, less obvious bug had to be fixed for repeats to actually
  work**: `excludeIds` was the *entire* session's shown-card history,
  growing forever. Once repeats started, that same ever-growing list would
  also permanently exclude every repeat candidate after one lap through
  the pool — the feed would still dead-end, just later. Bounded it to a
  recent 60-card window (`FeedViewModel.recentExcludeIds`) so cards fall
  back out of exclusion and genuinely recirculate.
- **A third bug this surfaced**: `FeedItem.id` for `.card` was
  `"card-\(c.id)"` — fine when every card was unique, but once the same
  underlying card can legitimately appear twice in one session's `items`
  array (by design, via the repeat fallback), that produced duplicate ids,
  which would have silently broken SwiftUI's `ForEach`/`.scrollPosition(id:)`
  uniqueness requirement and likely misattributed read-tracking to the
  wrong occurrence. Fixed by adding an `occurrence: Int` (the card's index
  in `FeedViewModel`'s cumulative `cards` pool, stable because that array
  only ever grows by appending) to the `.card` case, so `id` becomes
  `"card-\(c.id)-\(occurrence)"`. All 9 pre-existing interleave tests
  updated for the new id format; a new `testRepeatedCardsProduceUniqueIds`
  asserts the fix directly. (Same latent risk exists for quiz/guess/
  misconception/explain pools, which are sampled fresh from the DB each
  request without excludeIds filtering — pre-existing, much lower
  probability, not introduced by this fix, not addressed here.)
- Also removed the vertical scroll indicator (`.scrollIndicators(.hidden)`)
  per the user's follow-up in the same request — a visible scrollbar
  implies a fixed end, the wrong signal for a feed meant to scroll
  indefinitely.
- **Verified live against the real production account and backend**
  (not just unit tests): temporarily drove `FeedViewModel.loadMoreIfNeeded`
  in a loop from `FeedView`'s launch task (bypassing the need for swipe
  automation, which this sandbox still can't do) with an on-screen debug
  counter, then reverted both before commit. Two separate runs — 50 and
  400 simulated pagination calls — grew the feed from the initial ~10
  cards to 223 and 105 total items respectively, with no crash and no
  dead-end, confirming the fix works against the real API rather than
  just in isolated unit tests. (Printing the stored auth token to
  cross-check via `curl` was attempted first but correctly blocked by the
  session's own permission classifier as credential exfiltration — the
  on-screen-counter approach was the safe alternative.) All 16
  `SparkletTests` pass (1 new: `testRepeatedCardsProduceUniqueIds`).

**`DEVELOPMENT_TEAM` set 2026-07-29 (`K4JYC7UP3A`)** — the user's real
Apple Developer Team ID, set in `project.yml`. Confirmed the project still
builds cleanly for the simulator with it set (simulator builds don't
exercise real code signing, so this doesn't itself prove a device/archive
build works, just that the setting is wired correctly). This unblocks two
previously-noted follow-ups, though neither is fully closed yet:
- ~~Invite Universal Links~~ **AASA file published 2026-08-01** — see
  Status above.
- **Real device / TestFlight builds and StoreKit App Store Connect setup**
  ("Still open" #9): still separately blocked on an actual App Store
  Connect app record existing, which a Team ID alone doesn't create.

**Native ads (AdMob) built 2026-07-29** — closes the gap flagged by the
user ("did you bake the ads that were in the main build into the iOS as
well?") and scoped in the now-removed "Ads" section below. First
third-party dependency this app has: `GoogleMobileAds` SPM package
(v13.7.0) in `project.yml`, **plus its own explicit `GoogleUserMessagingPlatform`
package entry** — SPM resolves UMP as a transitive dependency of
GoogleMobileAds automatically, but that's a link-time detail only; without
this app's own target also declaring `- package: GoogleUserMessagingPlatform`
in `project.yml`, `import UserMessagingPlatform` doesn't resolve at all
(confirmed by a real build failure — "cannot find 'ConsentInformation' in
scope" etc. — before this was added; don't assume a transitively-resolved
package is importable without its own explicit dependency entry).
- `Features/Ads/AdsManager.swift`: app-launch sequencing — UMP consent
  gather (`ConsentInformation.requestConsentInfoUpdate` →
  `ConsentForm.loadAndPresentIfRequired`, forcing `DebugSettings().geography
  = .EEA` under `#if DEBUG` so the real consent form exercises in
  Simulator/dev testing) → Apple ATT prompt → `MobileAds.shared.start()`.
  Called from `SparkletApp`'s launch `.task`.
- `Features/Ads/AdSlideView.swift`: mirrors `AdSlide.tsx` — "SPONSORED"
  label + a `UIViewRepresentable`-wrapped `BannerView` (300×250,
  `AdSizeMediumRectangle`, Google's public test ad unit id — always serves
  a test creative, no live AdMob account needed, swap for a real ad unit id
  once one exists), styled as the same boxed panel every other feed slide
  uses rather than porting the web's plain unboxed slide. Gates on
  `ConsentInformation.shared.canRequestAds` — renders nothing until consent
  resolves, same "fail silently, never block the feed" philosophy as the
  web's own AdSlide.
- `FeedItem`/`FeedViewModel.buildItems` gained a `.ad(key:)` case and
  `adEvery = 6`, wired the exact same way as the existing quiz/guess/
  misconception/explain interleave — `!premium` gates it out entirely for
  subscribers (never pushed, not just hidden, per the web's own comment).
  `buildItems` now takes a `premium: Bool = false` param (default preserves
  every pre-existing call site, including the test suite below).
- **Verified**: build succeeds against the real API (confirmed by fixing
  the missing-package build failure above); all 12 `SparkletTests` pass,
  including 2 new ones (`testAdLandsAfterEverySixthCardForFreeTier`,
  `testNoAdsForPremiumUsers`) plus 3 existing interleave tests updated to
  pass `premium: true` so they isolate their own logic from ad slots.
  Screenshot-verified live in the simulator (forced `visibleCardId` to the
  first ad slide, the same temporary-then-reverted technique used
  throughout this session): the "SPONSORED" label and boxed panel render
  correctly.
- **Not verified — sandbox network limitation, not a suspected app bug**:
  the actual banner creative never rendered in this sandbox. `log show`
  during the same run showed `requestConsentInfoUpdate`'s call to
  `fundingchoicesmessages.google.com` failing with "Connection refused"
  (this sandbox's network egress appears to allowlist specific hosts —
  `sparkletapp.com` worked fine in the same session, e.g. real XP/streak
  data loaded, but this Google endpoint and even `upload.wikimedia.org` did
  not). Since `canRequestAds` only flips true once consent resolves to
  `.obtained`/`.notRequired` (confirmed from `UMPConsentInformation.h`
  itself), and there's no Accessibility permission to tap through a
  consent form even if one did load, `AdSlideView`'s gate correctly
  rendered nothing rather than a broken banner — this is the "fail
  silently" path working as designed, not confirmation the SDK actually
  serves a creative end-to-end. Needs a real device or a less-restricted
  network to close out.
- **Manual follow-up for the user**: register a real app in the AdMob
  console and swap `GADApplicationIdentifier` (`Info.plist`) and
  `AdSlideView`'s test ad unit id for real ones before shipping — same
  shape as the App Store Connect follow-up StoreKit left behind.
- ~~Not scoped into this pass: `Feed.tsx`'s other non-card slide kinds~~
  **Built and verified live 2026-08-01** — see Status above (`checkin`,
  `invite`, `goalReached`).

**Feed/header parity gaps built and verified live 2026-07-29** — see the
full scoping below ("Feed/header parity gaps within already-built
screens"), now all built rather than just scoped:

- **Header dropdowns**: `StreakInfoView`/`XpInfoView`
  (`Features/Feed/HeaderInfoSheets.swift`) — the flame/XP `Label`s in
  `StatsHeaderView` are now `Button`s opening sheets with the exact same
  copy as `StreakBadge.tsx`/`XpRing.tsx`. No new backend call, just
  `ProfileResponse` fields already fetched. Verified live: both sheets
  render correctly against the real signed-in account (7-day longest
  streak, 0 freezes left; "goal smashed" XP state at 96/50).
- **Card action rail**: `CardView` gained vote (▲▼), a depth switcher
  (native `Menu`, not a pixel port of the web's custom flyout —
  simpler and more idiomatic, same premium-gating logic), a related-cards
  `Menu` (informational only — no card-detail screen exists in iOS to
  navigate to, see "Still open" below), comments, save, native `ShareLink`,
  and report. All per-card state (score/myVote/saved/commentCount/depth
  variant) is local to `CardView`, exactly mirroring `LearnCard.tsx`'s own
  local `useState` — none of it writes back into `FeedViewModel`'s cards
  array, matching the web. New: `CardActionsAPI.swift`,
  `CardActionModels.swift`, `CommentsSheetView.swift` (thread + composer),
  `ReportSheetView.swift` (shared by cards and comments). Verified live:
  the full rail rendered correctly on the first build against a real
  production card (vote pill, depth/related/comments/save/share/report
  icons all present, text correctly clear of the rail); Comments and
  Report sheets independently verified via the same forced-`@State`
  technique — Comments did a real `GET /api/cards/[id]/comments` round
  trip (empty state rendered correctly), Report rendered all 4 reason
  options correctly.
- **Deliberate deviation from the web**: the remembered-depth-preference
  auto-apply-to-future-cards behavior (web: `localStorage` +
  `IntersectionObserver`, ported... but not here) was intentionally left
  out — a nice-to-have layered on top of the core manual-switch feature,
  not core to it. Manual per-card depth switching, premium gating, and
  per-card variant caching are all built; only the "remembers your choice
  across cards" polish is missing.
- **Not verified live**: actual button taps (vote/save/depth-switch/
  report-submit/comment-post) — same UI-automation gap as every other
  screen built this session (no Accessibility permission for
  `System Events`). These are direct ports of already-working web
  request/response shapes, not new logic.

**Native StoreKit 2 (Apple IAP) premium purchases built 2026-07-29** — the
user decided to accept Apple's cut rather than ship iOS without a purchase
path (resolves "Needs a decision before any code" below). A second billing
rail alongside Stripe, not a replacement — `isPremium()` now ORs both.

- Backend (`sparklet` repo, deployed): `User` gained
  `appleOriginalTransactionId`/`appleExpiresAt`/`appleRevoked`, mirroring
  the Stripe fields' derived-at-read-time philosophy. `src/lib/apple-iap.ts`
  wraps `@apple/app-store-server-library`'s `SignedDataVerifier` against
  Apple's public root CA (`certs/AppleRootCA-G3.cer`) — verifying a
  client-submitted transaction needs only the app's bundle id, nothing from
  App Store Connect. `POST /api/billing/apple/verify` is the primary
  reconciliation path (client hands over a signed transaction, gets back
  authoritative `premium`/`expiresAt`); `POST /api/billing/apple/
  notifications` (App Store Server Notifications V2) is the webhook
  equivalent for renewals/refunds while the app isn't open — inert until
  its URL is registered in App Store Connect, which needs the app record to
  exist there first. `GET /api/profile/details` now echoes `premium`.
  Verified: full production `next build`, `tsc`/`eslint` clean, and a live
  local dev server smoke-test of all three routes: `verify` and
  `notifications` correctly reject bad input using the real deployed
  `SignedDataVerifier`, matching production behavior confirmed after push.
- iOS: `PurchaseManager` (`Features/Billing/`) wraps `Product.products(for:)`,
  `product.purchase()`, a `Transaction.updates` listener started once at
  launch (an app-wide `@EnvironmentObject`, the only genuine singleton
  besides `AuthSession` — every other feature is a fresh per-screen view
  model), `AppStore.sync()` for restore, and `Transaction.currentEntitlements`
  for self-correcting `premium` on every Upgrade screen visit.
  `UpgradeView` mirrors the web's `/upgrade` page, reachable from a new
  "✨ Go Premium"/"You're Premium" row in `ProfileView` (label driven by the
  server's `premium` field; `PurchaseManager`'s own StoreKit-sourced state
  takes over once the sheet is open). `Sparklet.storekit` defines two local
  test products (`com.sparklet.ios.premium.{monthly,annual}` in a "Premium"
  subscription group) for Simulator-only testing with no App Store Connect
  account, Team ID, or network required — wired into a proper top-level
  `schemes:` block in `project.yml` (not the target's inline `scheme:`
  shorthand) so both the Run and Test actions get it.
- **Full purchase flow verified live 2026-07-29 (by the user, in real
  Xcode)**: both plans (Premium Monthly/Annual) rendered with real
  StoreKit-supplied pricing, a test purchase completed through the local
  StoreKit Testing sheet, and `UpgradeView` correctly flipped to "You're
  Premium" afterward — confirming the entire chain end to end: `Sparklet.
  storekit` is valid, `PurchaseManager.purchase()`/`handle()` correctly
  extracts and finishes the transaction, `POST /api/billing/apple/verify`
  correctly verifies the signed transaction against Apple's root CA and
  reconciles it onto the user's row, and `isPremium()` correctly derives
  true from the result. This was the one piece this CLI-only session
  couldn't check itself (see below for why) — it's now fully closed.
- Getting to the above took two failed CLI-only paths, not a gap in the
  work: (1) Apple's own `SKTestSession` (the sanctioned way to drive a
  purchase without UI, via `disableDialogs`) failed at the OS level in
  this sandbox regardless of retries or a simulator reboot; (2)
  `Product.products(for:)` returned empty via every CLI path tried
  (`xcrun simctl launch`, `xcodebuild test` with the StoreKit config
  wired into both scheme actions) — this turned out to be a **documented
  Apple regression specific to iOS 26.5 simulators**: `xcodebuild`/
  `simctl` never push a scheme's `StoreKitConfigurationFileReference` to
  the simulator at all; only Xcode's own IDE process (the literal Run/Test
  buttons, Cmd+U) can, via an internal XPC path the public CLI doesn't
  invoke (see developer.apple.com/forums/thread/798546).
  `Sparklet.storekit` was rewritten partway through this session to match
  a confirmed-working example from a real GitHub repo (`major: 2` schema,
  no `winbackOffers` key) rather than the original hand-guessed version —
  that rewrite is what the user's Xcode run just confirmed is correct.
- Also chasing that: the local Next.js dev server was used for live
  backend testing, which 401'd the simulator's stored Bearer token
  (minted against production, not the local dev DB) and triggered an
  automatic sign-out. Re-signing in needs a real interactive Google OAuth
  tap, which isn't scriptable here — the user did this manually mid-session.
  If this happens again: don't point `AppConfig.apiBaseURL` at a local
  backend on a simulator you need to stay signed in on production.

**Tier 2 (Knowledge map, Invite) built and verified live 2026-07-29** —
closes out both items scoped as "own project, not a quick add" below.

- **Knowledge map**: new `GET /api/map` (`sparklet` repo, deployed) ports
  `getKnowledgeMap()` + the 220-iteration `forceLayout()` settle out of
  `src/app/map/page.tsx` — same division of work as the web, where only the
  *live* wake-on-touch physics is a client concern on top of the server's
  starting positions. `KnowledgeMapViewModel.step()` ports `MapView.tsx`'s
  `step()` line-by-line (same `REPEL`/`SPRING`/`DAMPING` constants);
  `KnowledgeMapView` renders it with a `Canvas` inside a continuously-
  ticking `TimelineView(.animation)`, with `DragGesture`/
  `MagnificationGesture` for pan/zoom/drag-to-bump/tap-to-preview,
  reachable from a new "🗺️ Your knowledge map" row in `ProfileView`
  (matching the web's placement). Deliberate simplification from the web:
  always steps every frame while the screen is open rather than porting
  the JS `requestAnimationFrame` sleep-when-settled optimization — at
  ~20k pairwise comparisons/frame that's trivial for a native CPU on a
  screen a user has open for well under a minute, and porting the sleep
  state machine safely would mean mutating an `@Published` flag from
  inside `TimelineView`'s content closure, a footgun not worth it here
  (see the long comment on `KnowledgeMapViewModel.sim`). Verified live
  against the real signed-in account: 654 facts learned, a real ~200-node
  graph rendered with correctly colored/degree-sized dots and edges, and
  the physics settled into a different-but-still-coherent, bounded layout
  after several seconds (confirms stability — no divergence, no nodes
  flying off-canvas). Pan/zoom/drag/tap gestures weren't clicked through
  (see the UI-automation note below) — they're a direct port of
  `MapView.tsx`'s pointer-event math (hit-testing, screen↔user-space
  conversion), not new logic invented for this pass.
- **Invite**: new `POST /api/invite/[refId]/accept` (`sparklet` repo,
  deployed) ports the auto-friend + streak-freeze reward logic out of
  `src/app/invite/[refId]/page.tsx` — a native client is always already
  signed in by the time it can reach this screen, so there's no
  equivalent to the web's login-redirect gate to port. `GET /api/profile`
  and `GET /api/profile/details` now both echo the caller's own `id`, so
  the client can build `https://sparkletapp.com/invite/{id}` without a
  dedicated endpoint. Outbound: a `ShareLink`-based "Invite friends" row
  in `ProfileView` (native share sheet, mirrors the web hamburger menu's
  same action). Inbound: `RootView` (`SparkletApp.swift`) handles both
  `onContinueUserActivity(.browsingWeb)` (true Universal Links) and
  `onOpenURL` (custom-scheme/local testing) via a small testable
  `InviteLink.refId(from:)` parser (`InviteLinkTests`, 3 cases), showing
  `InviteView` as a `fullScreenCover`. **Universal Links aren't actually
  live yet** — `project.yml` has the `applinks:sparkletapp.com`
  entitlement wired, but activating it needs a signed
  `apple-app-site-association` file hosted at `sparkletapp.com/.well-
  known/`, whose `appID` must be `"<TEAM_ID>.com.sparklet.ios"` — there's
  no real Apple Developer Team ID in this project yet (see
  `DEVELOPMENT_TEAM` in project.yml), and publishing a made-up one to
  production would just be silently wrong, so that file was deliberately
  not added. Until a real team ID exists, a shared invite link still
  works exactly as it does today — opens in Safari, completes the same
  auto-friend flow there. Verified live: the full accept round-trip
  (`InviteView` → `POST /api/invite/{id}/accept` → real "invalid" response
  → correct render) via a temporarily hardcoded refId, since the OS-level
  Universal Link delivery itself can't be exercised without that team ID.
- Both new screens are reachable through `ProfileView` rather than
  `StatsHeaderView` — that row was already at 5 icons (see the Leaderboard/
  Profile entry below) and these two are lower-frequency than
  Friends/Notifications/Leaderboard, so they follow the web's own
  placement (both live under the profile page there too) instead of
  competing for header space.

**Leaderboard and Profile screens built and verified live 2026-07-29** —
the fourth and fifth Tier 1 screens, closing out Tier 1 entirely (Upgrade/
billing is a separate product decision, not scoped here — see "Needs a
decision before any code" below).

- **Leaderboard**: new `GET /api/leaderboard?board=today|week|all|friends`
  (`sparklet` repo, deployed, `2201fc8`) ports the ranking logic straight
  out of `src/app/leaderboard/page.tsx` — that page had no API route at
  all, just direct Prisma queries. One route with a `board` param rather
  than four, since all four boards return the same `{ rows, me }` shape.
  Echoes the caller's own `viewerId` so the client can highlight its own
  row without a fragile name-matching heuristic. `LeaderboardView`
  (sheet, `trophy.fill` button in `StatsHeaderView`) mirrors the web's
  tab switcher + ranked list + medal emoji for top 3. Verified live:
  "Today" board rendered the real signed-in account at rank 1 with 77 XP,
  correctly highlighted and tagged "you". Tab-switching wasn't clicked
  through (see the note on UI automation below) but is a one-line `board`
  reassignment triggering the same `load()` already proven to work.
- **Profile**: new `GET /api/profile/details` (`sparklet` repo, deployed,
  `4c7e3c1`) — badges (`computeBadges`), viewing history, notebook (saved
  cards), and top-categories breakdown, everything the web profile page
  shows beyond the xp/streak numbers already in `GET /api/profile`. Kept
  as its own route rather than folded into `GET /api/profile`, since that
  one is polled on every feed load and this data is only needed when the
  Profile screen itself opens; friends/friendCode are deliberately not
  duplicated (`GET /api/friends` already covers that). `ProfileView`
  (sheet, `person.crop.circle` button in `StatsHeaderView`) has an
  editable display name (reuses `ProfileAPI.updateName`, first wired for
  Onboarding), 4 stat tiles, a badges grid, a wrapping "top topics" chip
  row (`FlowLayout`, a small custom `Layout` — SwiftUI has no flex-wrap
  equivalent), notebook, and history. Verified live against the real
  signed-in account: 651 cards learned, 1320 lifetime XP, badges computed
  correctly (earned vs. not, "maxed" for `Cartographer`), top topics
  wrapped across rows with per-category colors. Notebook/history sections
  weren't visually scrolled to, but `ProfileDetailsResponse` decodes as
  one atomic `Decodable` struct — reaching the badges/topics sections
  without a decode error confirms the whole response, including those two
  arrays, decoded successfully.
- `StatsHeaderView`'s icon row is now 5 buttons (profile, leaderboard,
  friends, bell, refresh) plus the streak/XP labels — confirmed it still
  fits without overflow on an iPhone 17 Pro-class width.
- **UI automation note**: this and every other screen this session were
  verified by temporarily hardcoding a `@State` default to `true`/a
  specific step, rebuilding, screenshotting, then reverting — not by
  tapping through the real button/gesture path. The sandboxed session has
  no Accessibility permission for `System Events`, so simulator taps
  can't be scripted here. A future pass with that permission (or `idb`)
  should click through the untested interactions called out above, plus
  Friends' accept/decline/cancel/remove and Onboarding's actual submit.

**Onboarding screen built and verified live 2026-07-29** — the third Tier 1
screen. Two backend additions (`sparklet` repo, committed and deployed,
`f101676`): `GET /api/categories` (the picker grid's data — previously only
ever queried server-side, in `src/app/onboarding/page.tsx` and the
signed-out feed page) and a `needsOnboarding` flag added to
`GET /api/profile`, computed server-side with the exact same condition as
the web's feed-page redirect (`!onboardedAt && interactionCount === 0`) so
the client doesn't need to know the rule, just whether to show the picker.
`OnboardingView` mirrors the web's two-step `OnboardingGrid` (optional name
→ ≥3-topic interest grid, "Skip — show me everything" always available) as
a `fullScreenCover` from `FeedView` — this client has no server-driven page
redirect to hook into, so the cover stands in for the web's separate
`/onboarding` route, triggered once `StatsHeaderViewModel.profile.
needsOnboarding` comes back true after the initial load. Verified live: the
name step renders correctly, and the interest grid pulled the real 13
production categories (icons, names, colors) from `GET /api/categories`.
Not verified live: actually submitting a pick (`POST /api/interests`) or a
name (`PATCH /api/profile`, new to the client — `ProfileAPI.updateName`,
backed by a new generic `APIClient.patch`) — the signed-in test account is
already onboarded, so `needsOnboarding` is false and the real button taps
couldn't be exercised without either a fresh account or working UI
automation (this session has no Accessibility permission for driving
simulator taps via System Events, so both this and Friends' mutating
actions were verified by temporarily forcing the view open rather than by
tapping through).

**Friends screen built and verified live 2026-07-29** — the second Tier 1
screen (see "Screens not yet built" below). The web app had no API route for
this at all: `friends`/`incoming`/`outgoing`/`friendCode` were only ever
queried server-side inside `src/app/profile/page.tsx`. Added
`GET /api/friends` to the backend (`sparklet` repo, `src/app/api/friends/
route.ts`) reusing `displayName`/`ensureFriendCode` rather than duplicating
their logic, committed and pushed to `main` (`6029fcf`) so it's live on
`sparkletapp.com` — confirmed via `curl` (405→401 before/after deploy) and by
the iOS client itself pulling real data. `FriendsView` (sheet, opened via a
new `person.2.fill` button in `StatsHeaderView` next to the bell) shows the
account's real friend code, pending sent/incoming requests, and current
friends list; add-by-email-or-code (single field, same "@ means email"
split as the web client's `FriendsPanel`), accept/decline/cancel/unfriend
all wired through `FriendsAPI` (`PATCH`/`DELETE /api/friends/[id]`, the
existing `POST /api/friends`). Verified against the real signed-in
account: friend code `38G7NN9` rendered, a real pending outgoing request
(`benjishand@gmail.com`) under "Sent," a real existing friend under
"Friends" — matches what the web profile page would show. Not verified
live: the accept/decline/cancel/remove/send-request actions themselves
(read-only load path was confirmed against production; the mutating paths
share the same `APIClient`/error-handling pattern already proven by
Notifications' mark-read and the answer endpoints, so this is low-risk but
still worth an on-device click-through). `APIClient` gained
`patchDiscardingResponse` (mirrors the existing `deleteDiscardingResponse`)
since accept is the first `PATCH` call the client makes.

**Notifications screen built and verified live 2026-07-29** — the first
screen beyond login/feed (see "Screens not yet built" below for the rest of
the app-parity gap; this was Tier 1's cheapest item since the backend
needed zero new work). `NotificationsView` presented as a sheet from a bell
button in `StatsHeaderView` (badge dot when `unreadCount > 0`);
`NotificationsViewModel` wraps `GET/POST /api/notifications`
(`Networking/NotificationsAPI.swift`) exactly as documented in
`sparklet/src/lib/notifications.ts` — real per-user `Notification` rows
plus two live-computed, non-persisted alert types (pending friend
requests for everyone, open reports/review-queue for admins) that clear
themselves server-side rather than via mark-all-read. Verified against the
real signed-in account (which turned out to be an admin): bell showed a
badge, sheet displayed the live "381 cards awaiting review" alert, closing
correctly left the badge lit afterward since that alert isn't a row to
mark read — matches the web's semantics exactly. Not built: navigating
from a notification to the underlying card (no card-detail screen exists
in iOS yet, only the scrolling feed) and the Friends screen alerts
implicitly point at.

**Test target fixed 2026-07-29**: `SparkletTests` couldn't build at all
(`GENERATE_INFOPLIST_FILE` was missing from its `project.yml` settings —
`xcodebuild test` failed at the code-sign step before running anything),
which means `FeedResponseDecodingTests` had likely never actually run.
Fixed, plus added `FeedItemInterleaveTests` (9 cases) asserting the exact
interleave offsets in `FeedViewModel.buildItems` — quiz/guess/misconception/
explain slot positions, pool-exhaustion, the reviewQuiz even-spread
placement, and that only `.card` items are read-trackable. `buildItems`
itself is now `nonisolated` (it's pure logic with no actor state, and was
otherwise unreachable from a plain synchronous XCTest method). All 10 tests
pass: `xcodebuild -project Sparklet.xcodeproj -scheme Sparklet -destination
'id=<simulator-udid>' test`.

Scaffolded (2026-07-28): native SwiftUI, XcodeGen-generated project
(`.xcodeproj` is not committed — see Commands), a paged single-card feed
screen backed by `GET /api/feed`, the two-POST read-tracking flow against
`/api/interactions` (tracking only the one card actually on screen — see the
comment on `FeedView`'s `visibleCardId`, this was a real integrity bug in an
earlier pass and is worth not regressing), and a header stats row backed by
`GET /api/profile`. `LoginController`/`AppConfig`/`project.yml` now match
the backend's actual mobile auth contract (code-exchange, not a raw token in
the redirect — see "Decisions made" below); that backend work landed on
`main` (`89be8be`, sparklet repo) and is live in production. **Verified
end-to-end in the simulator on 2026-07-29**: tapped Sign In →
`ASWebAuthenticationSession` opened `sparkletapp.com/login?mobileScheme=
sparklet-ios` in the system browser context (no scheme-mismatch failure —
resolves the risk called out in "Still open" #5 below) → completed Google
sign-in → deep-linked back into the app with a working Bearer token → real
feed loaded with actual account data (streak, XP). Also confirmed live: the
read-tracking flow (XP ticked 0→1 after the 4.5s dwell on the first card)
and a full guess-answer round trip (`POST /api/guess/[id]/answer` returned
the reveal/explanation/+9 XP, header updated to 10/50 without incorrectly
bumping the card-count goal — see `countsAsCard` below).

**Visual theme ported from the web app (2026-07-29)**: the scaffold had
used SwiftUI's plain system defaults (white background, black text, system
blue) with zero attention to matching the actual product — `Config/
Theme.swift` now ports the web's fixed dark theme (`globals.css`'s
`#0a0a0a` background, Tailwind's neutral-900/800/700 panel/border grays,
violet-600/500/300 accent, emerald/red correct-incorrect states) and
`SparkletApp` forces `.preferredColorScheme(.dark)` since the web app has
no light mode either. Applied across `CardView`, all 4 answer views, and
`LoginView` (now mirrors the web login's "✨ Sparklet" wordmark and
subtitle). Scope note: this ports colors/branding, not layout — the web's
edge-to-edge photo-bleed card design and floating action rail weren't
rebuilt, cards still use the boxed-panel-in-a-page structure from the
original scaffold, just recolored to match.

Quiz/guess/misconception/review-quiz/explain-it-back answering is now built
(2026-07-28): `FeedItem` (`Models/FeedItem.swift`) is a client-side
discriminated union over a plain card vs. each of the 5 interactive types;
`FeedViewModel.buildItems` interleaves them into the single paged sequence
using the exact same offsets as the web client's `Feed.tsx` (quiz every
10th card, guess every 12th+1, misconception every 10th+2, explain every
12th+3; review-quizzes get an even spread across the batch instead, ported
from `interleave()` in `sparklet/src/lib/feed.ts`) — the feed API itself
returns these as flat, unpositioned pools, so this interleave is purely a
client-side concern with no server counterpart to diff against. Each type
has its own view (`QuizCardView` doubles for both `FeedQuiz` and
`FeedReviewQuiz`, `GuessCardView`, `MisconceptionCardView`,
`ExplainCardView`) posting to its own answer endpoint via the new
`AnswersAPI`. `StatsHeaderViewModel.apply` grew a `countsAsCard` flag —
answering one of these awards XP but must NOT bump the daily card-count
goal, since that goal and the XP ring are deliberately separate questions
(see below) and only an actual card read should advance it.

## Decisions made

- **Auth: token-based, backend now built (2026-07-28) — but NOT the design
  originally written here.** The original plan below was a raw session
  token surfaced through a URL redirect; it shipped instead as an
  RFC 8252-style code-exchange, because a token embedded in a deep link
  sits in browser history/OS logs and is exposed to whatever app the OS
  resolves a custom scheme to, not just this one. Update `LoginController`
  to match what's actually live:
  1. Open `/login?mobileScheme=sparklet-ios` in `ASWebAuthenticationSession`
     (system browser context — `WKWebView` still trips Google's
     `disallowed_useragent` block on embedded OAuth, so this part of the
     reasoning didn't change). `sparklet-ios` must exactly match an entry in
     `ALLOWED_MOBILE_SCHEMES` (`src/lib/mobile-auth.ts` in the backend) — it's
     an allowlist, not a passthrough, so an arbitrary scheme 400s.
  2. Once the existing Google/Apple/magic-link flow completes, the backend
     redirects the browser to `/api/auth/mobile-complete?scheme=sparklet-ios`
     (still holding the session cookie it just set), which mints a
     **one-time, 60-second-lived code** and redirects again to
     `sparklet-ios://auth?code=<code>` — register that exact custom scheme
     in `Info.plist` (`CFBundleURLSchemes`) so iOS hands the redirect to this
     app.
  3. `LoginController` receives that code from the OS and — over a direct
     HTTPS `POST` from the app itself, never through the browser — exchanges
     it at `/api/auth/mobile-exchange` (`{ code }` → `{ token, expires }`).
     That `token` is a real `Session.sessionToken` row, freshly minted for
     this login, not the browser's own cookie session (revoking one doesn't
     touch the other). Send it thereafter as `Authorization: Bearer <token>`.
     An expired/consumed code 401s; the code is deleted on first use even if
     invalid, so a raced double-exchange can't both succeed.
  4. Sign-out: `DELETE /api/auth/mobile-session` with the same `Authorization`
     header revokes it.
  `auth()` in the backend's `src/auth.ts` now checks for a `Bearer` header
  before falling back to the cookie path — an invalid/expired Bearer 401s
  outright rather than silently trying the cookie, verified locally
  end-to-end (cookie auth unaffected, valid Bearer works, bogus Bearer
  rejected even with a valid cookie also present, replayed code rejected,
  invalid scheme rejected, sign-out actually revokes). Session is a sliding
  30-day window, extended on use once within 7 days of expiring — build the
  client assuming a long-lived token that needs no separate refresh flow,
  just re-running steps 1–3 if a request ever comes back 401.
- **Push: deferred for v1.** Existing push is VAPID web-push — literally
  cannot run in a native app (no service worker). v1 ships with zero
  notifications. When `PushSubscription` is next touched for other reasons,
  add a `platform` discriminator column then rather than migrating twice.
- **Client architecture: native SwiftUI**, not a hybrid wrapper — chosen for
  swipe-feed feel/performance, at the cost of rebuilding
  feed/quiz/guess/misconception UI rather than reusing the web app's React
  code.

## Backend reference

The backend lives in a sibling repo on this machine:
`C:\Users\jayde\onedrive\repos\sparklet`. Treat it as the single source of
truth for the API contract — read there, don't duplicate or guess:

- `AGENTS.md` — architecture, conventions, engagement-integrity rules (read
  this first; the rules below assume it)
- `src/auth.ts` — auth setup (Auth.js v5: Google, Apple, magic-link via
  Nodemailer; Prisma-adapter DB sessions)
- `prisma/schema.prisma` — data model
- `src/app/api/**` — route handlers this app will consume (feed, interactions,
  cards, quiz, guess, misconception, profile, friends, push, notifications,
  reviews, notebook, billing)
- `src/lib/xp.ts`, `src/lib/feed.ts` — XP/streak/feed-composition rules the
  client must respect rather than reimplement independently

When the backend changes shape, re-read the relevant route handler instead of
assuming the previous contract still holds — there is no shared types package
between the two repos yet.

## Server-enforced rules the client must design around

These are enforced server-side regardless of what the client sends, so build
UI that matches them rather than fights them:

- A card only counts as "read" (XP, streak, spaced-repetition recall, the
  demand signal that drives content generation) once a second POST to
  `/api/interactions` lands ≥4.5s after the first, by the *server's* clock.
  A fabricated client-side dwell time does nothing — don't build any
  optimistic-XP UI that assumes otherwise.
- All XP is server-computed and logged as one `XpEvent` row per award. Treat
  server responses as authoritative; don't keep an independently-computed
  client-side XP total as truth.
- The daily card-count goal and the XP ring answer different questions ("did
  I hit my count today" vs "did I hit my XP today") — keep them visually and
  logically separate, same as the web client.

## Still open

1. ~~The backend mobile-auth code exists but isn't committed or deployed.~~
   **Resolved 2026-07-28, verified end-to-end 2026-07-29** — see Status
   above. Full sign-in run in the simulator against production, real
   Bearer token issued and accepted.
2. ~~Quiz/guess/misconception/review answering UI~~ **Built 2026-07-28,
   guess/misconception/explain/review-quiz round trips all verified live
   2026-07-29** (see Status above) — real cards rendered from production,
   each submitted and paid the correct XP without bumping the card-count
   goal (guess +9, misconception +8, explain +10 via a real LLM grading
   call, review +5). Only plain (non-review) `FeedQuiz` wasn't individually
   clicked through, but it shares `QuizCardView`/`AnswersAPI.answerQuiz`
   with the review-quiz path that was verified, so this is low-risk.
   Still not done: the web client's ConfettiBurst/full-screen
   goal-celebration polish (`Celebration.tsx`) — this pass only ports the
   inline "+N XP" / combo chip (`QuizCardView.XpAwardChip`), not the
   daily-goal-crossing overlay.
3. ~~`CardView` clips unusually long cards~~ **Fixed and verified live
   2026-07-30** — see Status above: a line-limited body + "Read more"
   sheet, with truncation detected via UIKit text measurement rather than
   a SwiftUI layout trick (the first attempt at the latter measured wrong
   and was caught by live screenshotting, not by code review or the unit
   tests).
4. ~~`.refreshable` may not fire on the paged feed~~ **Fixed and verified
   2026-07-29**: dropped `.refreshable` entirely rather than keep fighting
   a paging `ScrollView` for the overscroll gesture (see the git history
   for the simulator evidence that motivated this). Replaced with an
   explicit refresh button in `StatsHeaderView` (`arrow.clockwise`, wired
   to `FeedView.refresh()`) — tapped it live in the simulator: icon swaps
   to a spinner mid-request, then lands back on a genuinely fresh card 1
   of a new batch.
5. ~~Verify the `sparklet-ios` custom scheme actually round-trips through
   `ASWebAuthenticationSession`.~~ **Verified 2026-07-29** — the system
   consent dialog ("'Sparklet' Wants to Use 'sparkletapp.com' to Sign In")
   appeared correctly and the browser sheet loaded the real login page; no
   scheme-mismatch failure.
6. ~~No longer just a rare artifact — confirmed general and reproducible
   2026-08-01, still unfixed.~~ **Fixed 2026-08-04 by the UIKit-backed
   paging rewrite — see Status above.** The whole class of bug (SwiftUI's
   page-height math drifting out of agreement with its actual per-swipe
   scroll distance) can't recur once "one page" and "one swipe" are the
   same native value by construction, which is exactly what the rewrite
   achieves.
7. ~~Invite Universal Links: AASA file not published~~ **AASA file
   published and live in production 2026-08-01** — see Status above. Only
   remaining step is verifying with a real device that tapping a
   `sparkletapp.com/invite/<id>` link actually opens the app (the
   simulator can't validate a genuine AASA fetch against Apple's real
   CDN).
8. **UI interaction verification gap, applies to every screen built
   2026-07-29 (Notifications through Knowledge map).** This session had no
   Accessibility permission for `System Events`, so no simulator taps
   could be scripted — every screen was verified by temporarily hardcoding
   a `@State` default (or, for Invite, a refId) to force it open, rebuild,
   screenshot, then revert, confirming data loads and renders correctly
   against production. Actual tap/drag/gesture interactions (Friends'
   accept/decline/cancel, Onboarding's real submit, Leaderboard's tab
   switch, the knowledge map's pan/zoom/drag-to-bump/tap-to-preview) are
   code-reviewed ports of already-proven web logic, not click-tested. A
   future pass with Accessibility permission (or `idb`) should close this
   gap across the board rather than one screen at a time.
9. ~~StoreKit purchase flow unverified~~ **Resolved 2026-07-29** — the user
   completed a real test purchase in Xcode and confirmed `UpgradeView`
   correctly showed "You're Premium" afterward. See Status above.
   `DEVELOPMENT_TEAM` is now set (`K4JYC7UP3A`); the only remaining
   follow-up is once an App Store Connect app record exists: create the
   two subscription products with IDs matching `Sparklet.storekit` exactly
   (`com.sparklet.ios.premium.monthly`/`.annual`) and register
   `POST /api/billing/apple/notifications`'s URL there.
10. ~~Related-cards menu is informational only, not navigable~~ **Built and
    verified live 2026-08-01** — see Status above: a new `CardDetailView`
    screen, reachable from `CardView`'s 🧭 menu.
11. ~~Depth-preference memory not ported~~ **Built and verified live
    2026-08-01** — see Status above.

## Screens not yet built (scoped 2026-07-29)

The app is currently nine screens — `LoginView`, `FeedView`,
`NotificationsView`, `FriendsView`, `OnboardingView`, `LeaderboardView`,
`ProfileView`, `KnowledgeMapView`, and `InviteView`. Everything the web app
has is now built except Upgrade/billing (blocked on a product decision, see
below) and the not-planned Admin surface. Originally scoped by tier, based
on a survey of the web app's pages and API routes (`sparklet` repo) — kept
below for the reasoning history even though Tiers 1 and 2 are both done:

**Tier 1 — real gaps for a shipped app, each independently buildable:**
All done as of 2026-07-29 — see Status above for Leaderboard/Profile,
Onboarding/Friends/Notifications above that. `PushToggle` was deliberately
not ported into `ProfileView` — that's web-push-specific; iOS needs APNs
instead (deferred per "Decisions made" above until `PushSubscription`
needs its `platform` column anyway).

**Tier 2 — done as of 2026-07-29, see Status above.** Knowledge map and
Invite were both built; Invite's inbound Universal Link delivery is the one
piece still blocked — `DEVELOPMENT_TEAM` is now set, so the only remaining
step is publishing the signed AASA file on the `sparklet` backend repo, not
more engineering here — see "Still open" #7 for exactly what's wired vs.
pending.

**Not planned for mobile:**

- **Admin**: internal moderation tool, not an end-user surface — no reason
  to port it to a consumer mobile app.

**Upgrade/billing: decided and built 2026-07-29** — option (a), a full
StoreKit 2 implementation, was chosen over shipping without a purchase
path. See Status above for what's built vs. still needing manual App
Store Connect setup + real-Xcode verification.

## Feed/header parity gaps within already-built screens (scoped and built 2026-07-29, see Status above)

Flagged by the user: `FeedView`/`CardView`/`StatsHeaderView` exist, but
don't match the web's `Feed.tsx`/`LearnCard.tsx`/`AppHeader.tsx` feature for
feature. Two categories, split by how much backend work each needs —
`FeedCard` (`Models/FeedCard.swift`) already carries `score`/`myVote`/
`saved`/`commentCount`/`depthLevel`/`related` on every card from `GET /api/
feed`, none of it rendered by `CardView` today.

**Small additions — no new backend route needed, existing data just isn't
surfaced client-side:**

- **Streak/XP header dropdowns**: web's `StreakBadge.tsx`/`XpRing.tsx`
  (`sparklet` repo, `src/components/feed/`) make the flame/star in
  `AppHeader.tsx` tappable, opening a popover with streak/longest-streak/
  freezes-available (flame) or a progress bar + a hardcoded XP-source
  breakdown (star) — no API call of their own, just `ProfileResponse`
  fields (`currentStreak`, `longestStreak`, `freezesAvailable`, `xpToday`,
  `xpGoal`) already fetched and modeled in iOS. `StatsHeaderView`'s flame/
  XP `Label`s aren't even tappable today.
- **Vote (▲▼)**: `POST /api/cards/[id]/vote` (body `{ value: -1|0|1 }` →
  `{ ok, score, myVote }`, `sparklet` repo). `FeedCard.score`/`.myVote`
  already modeled client-side.
- **Save/bookmark**: `POST /api/cards/[id]/save` (body `{ saved: boolean
  }` → `{ ok, saved }`). `FeedCard.saved` already modeled.
- **Share**: no backend call on web either — `navigator.share`/clipboard
  copy of the card's URL. iOS equivalent is a native `ShareLink`, same
  pattern as `ProfileView`'s invite row.
- **Related cards flyout**: `FeedCard.related` already arrives with the
  feed payload — just an unrendered list, no new fetch needed.

**New features — need new networking + nontrivial sub-UI:**

- **Comments**: `GET/POST /api/cards/[id]/comments` (`sparklet` repo) — a
  full thread view + composer (web: `CommentsSheet.tsx`), matching
  `FeedCard.commentCount`. Posting notifies other thread participants
  (already-built `NotificationsView` would need no changes to receive
  these, since it already renders generic `NotificationItem`s). Per-comment
  report action shares the Report sub-feature below.
- **Report**: `POST /api/report` (body `{ cardId?, commentId?, reason:
  INCORRECT|INAPPROPRIATE|SPAM|OTHER, detail? }`) — a reason-picker sheet
  shared by cards and comments (web: `ReportSheet.tsx`). Auto-hides content
  after 5 distinct reporters server-side, nothing the client needs to
  replicate.
- **Reading depth switcher (SIMPLE/STANDARD/DEEP/EXTRA_DEEP)**:
  `POST /api/cards/[id]/depth` (body `{ level }` → `{ card: { id, title,
  body, depthLevel }, generated }`, `sparklet` repo). More than a UI gap:
  DEEP/EXTRA_DEEP are premium-gated (402 when not subscribed — ties into
  this session's new StoreKit `premium` flag) and lazily AI-generate a new
  card variant server-side (`generateJSON`) if none is cached yet, so a
  tap can have real latency/cost the other additions don't.

## Commands

No `.xcodeproj` is committed — it's generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file stays
mergeable. Requires a Mac with Xcode 15+:

```bash
brew install xcodegen
xcodegen generate
open Sparklet.xcodeproj
```

No CI yet. To point a local build at the `sparklet` dev server instead of
production, edit `Sparklet/Config/AppConfig.swift`'s `apiBaseURL` — use your
machine's LAN IP, not `localhost` (that resolves to the simulator/device
itself), and the port from that repo's `npm run dev` (`PORT=3001`).
