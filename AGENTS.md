# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

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

## Screens not yet built (scoped 2026-07-29)

The app is currently four screens — `LoginView`, `FeedView`,
`NotificationsView`, and `FriendsView`. Everything else the web app has is
missing. Scoped by tier, based on a survey of the web app's pages and API
routes (`sparklet` repo):

**Tier 1 — real gaps for a shipped app, each independently buildable:**

- ~~**Notifications**~~ **Built and verified live 2026-07-29** — see Status
  above.
- ~~**Friends**~~ **Built and verified live 2026-07-29** — see Status above.
- **Onboarding**: `POST /api/interests` is client-ready. Needs one small
  new endpoint (or reuse of the feed's category list) for the interest
  picker's category grid — everything else is a simple multi-select.
- **Leaderboard**: no API route exists yet — the web page does the
  today/7-day/all-time/friends ranking via direct Prisma queries
  (`src/app/leaderboard/page.tsx`). Needs a new route, e.g.
  `GET /api/leaderboard?board=today|week|all|friends` — keep the rank
  computation server-side, don't reimplement it in Swift. UI itself is a
  simple tab switcher + ranked list.
- **Profile**: `GET/PATCH /api/profile` exists but is thin (xp/streak/name
  only) — the web page's history, saved cards/notebook, badges
  (`src/lib/badges.ts`), category breakdown, and due-reviews count are all
  server-side-only right now and need new routes. UI itself is simple
  (header, stat tiles, scrollable lists). Don't port `PushToggle` — that's
  web-push-specific; iOS needs APNs instead (deferred per "Decisions made"
  above until `PushSubscription` needs its `platform` column anyway).

**Tier 2 — real feature, deliberately not next:**

- **Knowledge map**: not a simple screen — `MapView.tsx` (461 lines) is a
  live force-directed graph with drag physics (spring/repel/damping that
  "wakes" on touch), pan/zoom, tap-to-preview, degree-based node sizing.
  This is a custom-rendered physics engine, not a chart — likely a
  SwiftUI Canvas or UIKit gesture-driven view. Also has no backing API
  route yet (`getKnowledgeMap()` + `forceLayout()` are page-local). Scope
  as its own project when it comes up, not a quick add.
- **Invite**: web's `/invite/[refId]` is a full page (resolve referrer,
  auto-create friendship, grant a streak-freeze bonus, login-gate via
  redirect) with no API route — logic lives in the page component. iOS
  can't render that mid-flow; needs a new `POST /api/invite/[refId]/accept`
  endpoint, a native share sheet for the outbound side, and Universal
  Links/associated-domains configuration for the inbound side. The
  UI itself is trivial; the deep-link infra is the actual work.

**Not planned for mobile:**

- **Admin**: internal moderation tool, not an end-user surface — no reason
  to port it to a consumer mobile app.

**Needs a decision before any code, not just scoping:**

- **Upgrade/billing**: `POST /api/billing/{checkout,portal}` return
  Stripe-hosted URLs — this is the web flow, and it is **not** just
  "another API to call" for iOS. Apple's App Store Review Guideline 3.1.1
  requires digital subscriptions unlocking in-app content to go through
  StoreKit/In-App Purchase; linking out to Stripe checkout for this from a
  native app risks rejection. Real options are (a) a full parallel
  StoreKit 2 subscription implementation with server-side receipt
  validation reconciled against the existing Stripe `premium` flag, or
  (b) ship iOS without an in-app purchase path (read-only "already premium
  via web" messaging). This is a product/business call, not an engineering
  one — don't build a screen here without that decision first.

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
