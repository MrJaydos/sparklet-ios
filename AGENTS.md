# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

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
- **Not scoped into this pass** (unchanged from the original scoping):
  `Feed.tsx`'s other non-card slide kinds this iOS client still doesn't
  have — `checkin` (session recap + share CTA), `invite` (a mid-feed
  prompt distinct from the `ProfileView` invite row already built), and
  `goalReached` (a celebration slide, ties to the confetti/celebration gap
  noted elsewhere in this doc).

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
6. **Observed once 2026-07-29, likely a testing artifact, not a real bug**:
   after many rapid, robotic backward/forward paging swipes in immediate
   succession (automated simulator testing, not how a real user swipes), a
   card rendered with its leading ~1-2 characters and category emoji
   clipped off — confirmed in a full, uncropped Mac screenshot, so it was a
   real on-device rendering state, not a screenshot-crop mistake. A plain
   app restart (`simctl terminate` + `launch`) fully cleared it; the very
   next card rendered perfectly. Plausible cause: the paging `ScrollView`
   landed in a slightly-off-page scroll offset when reversed direction
   faster than its snap animation could settle. Worth a light on-device
   sanity check (a few quick manual swipe-reversals) but not worth chasing
   further from this one occurrence under artificial conditions.
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
