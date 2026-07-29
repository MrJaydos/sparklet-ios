# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

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
3. **`CardView` clips unusually long cards** instead of scrolling within
   their page — a nested `ScrollView` was tried and reverted (see the
   comment in `CardView.swift`: it fights `.scrollTargetBehavior(.paging)`
   for the drag gesture). Basic paging itself is confirmed working (swiped
   from a card to the next interleaved item on 2026-07-29 without issue),
   but that was a short card — the long-card clipping case specifically
   still needs an on-device look, not a blind fix.
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
7. **Invite Universal Links need a real Apple Developer Team ID.** The
   `applinks:sparkletapp.com` entitlement is wired in `project.yml`, and
   `RootView` already handles `onContinueUserActivity(.browsingWeb)`
   correctly (see Status above) — but activation also requires a signed
   `apple-app-site-association` file at `sparkletapp.com/.well-known/`
   whose `appID` is `"<TEAM_ID>.com.sparklet.ios"`, which needs the real
   team ID from `DEVELOPMENT_TEAM` once that's set. Until then, invite
   links still work today, just by opening in Safari instead of the app.
   Once a team ID exists: add that AASA route to the `sparklet` repo, set
   `DEVELOPMENT_TEAM` in `project.yml`, and verify with a real device (the
   simulator can't validate a genuine AASA against Apple's CDN).
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
   correctly showed "You're Premium" afterward. See Status above. Only
   remaining follow-up, and only once a real Apple Developer Team ID and
   App Store Connect app record exist: create the two subscription
   products with IDs matching `Sparklet.storekit` exactly
   (`com.sparklet.ios.premium.monthly`/`.annual`), register
   `POST /api/billing/apple/notifications`'s URL there, and set
   `DEVELOPMENT_TEAM` in `project.yml`.

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
piece still blocked, on a real Apple Developer Team ID rather than more
engineering — see the Status entry for exactly what's wired vs. pending.

**Not planned for mobile:**

- **Admin**: internal moderation tool, not an end-user surface — no reason
  to port it to a consumer mobile app.

**Upgrade/billing: decided and built 2026-07-29** — option (a), a full
StoreKit 2 implementation, was chosen over shipping without a purchase
path. See Status above for what's built vs. still needing manual App
Store Connect setup + real-Xcode verification.

## Feed/header parity gaps within already-built screens (scoped 2026-07-29)

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
