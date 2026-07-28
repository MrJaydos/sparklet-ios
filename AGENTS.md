# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

Scaffolded (2026-07-28): native SwiftUI, XcodeGen-generated project
(`.xcodeproj` is not committed — see Commands), a paged single-card feed
screen backed by `GET /api/feed`, the two-POST read-tracking flow against
`/api/interactions` (tracking only the one card actually on screen — see the
comment on `FeedView`'s `visibleCardId`, this was a real integrity bug in an
earlier pass and is worth not regressing), and a header stats row backed by
`GET /api/profile`. Not yet built: quiz/guess/misconception/review
answering, and — the one open blocker — the backend token-auth endpoint (see
"Auth" below). `LoginController` drives the real web `/login` flow today but
has nothing to receive a token from yet, so sign-in doesn't actually
complete end to end.

## Decisions made

- **Auth: token-based (backend change required, not yet built).** Session
  cookies can't cross into a native app — `ASWebAuthenticationSession`
  never exposes the cookie jar, and `WKWebView` (which can read cookies)
  triggers Google's `disallowed_useragent` block on embedded OAuth. Instead:
  `LoginController` opens `/login?client=ios&callback=sparklet` in
  `ASWebAuthenticationSession` (system browser context, so Google's OAuth
  isn't blocked); once the existing Google/Apple/magic-link flow completes,
  the backend must redirect to `sparklet://auth?token=<sessionToken>`
  instead of `/feed`. The token is just the existing `Session.sessionToken`
  row (`prisma/schema.prisma` in the backend repo) surfaced to a redirect
  instead of a cookie — no new auth strategy needed there, just a new
  callback path and an `auth()` fallback that accepts
  `Authorization: Bearer <token>` by looking up that same table. ~23 route
  handlers in the backend call `auth()` directly today (grepped
  `from "@/auth"` under `src/app/api`), so that fallback needs to sit
  behind the existing `auth()` export, not require touching every call site.
  **This backend change hasn't been made yet** — confirm with the user
  before implementing it in the `sparklet` repo, since that's a shipped
  production app deployed off pushes to `main`.
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

1. **The backend token-auth endpoint** described under "Decisions made"
   above doesn't exist yet — it's a change to the `sparklet` repo (a shipped
   production app), so implement it there as a separate, confirmed step
   rather than assuming it's covered by this repo's scaffolding.
2. **Quiz/guess/misconception/review answering UI** — the feed payload
   already returns `quizzes`/`reviewQuizzes`/`guesses`/`misconceptions`/
   `explainPrompts` (see `Models/FeedCard.swift`), but nothing renders or
   answers them yet.
3. **`CardView` clips unusually long cards** instead of scrolling within
   their page — a nested `ScrollView` was tried and reverted (see the
   comment in `CardView.swift`: it fights `.scrollTargetBehavior(.paging)`
   for the drag gesture, unverifiable without a device). Needs an on-device
   look, not a blind fix.
4. **`.refreshable` may not fire on the paged feed** — pull-to-refresh needs
   top overscroll, which a paging `ScrollView` may consume instead. Verify
   on device; if it doesn't trigger, that's a missing affordance to design
   around, not a bug to patch blindly.

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
