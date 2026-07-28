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
`GET /api/profile`. `LoginController`/`AppConfig`/`project.yml` now match
the backend's actual mobile auth contract (code-exchange, not a raw token in
the redirect — see "Decisions made" below), which exists and was verified
locally in the `sparklet` repo as of 2026-07-28 — but is **uncommitted and
undeployed** there, so sign-in won't complete against production until that
lands. Not yet built: quiz/guess/misconception/review answering.

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

1. **The backend mobile-auth code exists but isn't committed or deployed.**
   As of 2026-07-28 it's uncommitted working-tree state in the `sparklet`
   repo (`src/auth.ts`, `src/app/login/page.tsx`, `src/lib/mobile-auth.ts`,
   `src/app/api/auth/mobile-{complete,exchange,session}/`), verified locally
   but not on `main` and not on the deployed app. Committing/pushing that is
   a separate, confirmed step in that repo (a shipped production app
   deployed off pushes to `main`) — don't assume it's live just because it's
   written.
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
5. **Verify the `sparklet-ios` custom scheme actually round-trips through
   `ASWebAuthenticationSession`.** The hyphen is valid per RFC 3986 and
   modern iOS accepts it, but this is the one point where a scheme mismatch
   fails silently as an immediate `.canceledLogin` with no useful error. If
   that happens on first run, the fix is changing `ALLOWED_MOBILE_SCHEMES`
   in the backend (e.g. to `sparkletios`) and `AppConfig.authCallbackScheme`
   + `project.yml`'s `CFBundleURLSchemes` to match — not something to
   pre-emptively "fix" here without seeing it fail.

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
