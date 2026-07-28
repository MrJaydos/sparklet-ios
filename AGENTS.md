# Sparklet iOS

Native iOS client for Sparklet — a TikTok-style vertical learning feed (short
fact-checked cards with real sources, quizzes, guess-before-reveal challenges,
XP/streaks/leaderboard, spaced repetition). The backend is a separate,
already-shipped Next.js/Prisma/Postgres app; this repo is the iOS client only.

## Status

No code yet. Architecture (auth flow, native vs. hybrid, push strategy) is
still being decided — see "Open decisions" below before scaffolding an Xcode
project. Resolve those first, then replace this section and the Commands
section with the real thing.

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

## Open decisions (resolve before scaffolding further)

1. **Auth.** The backend session is cookie-based (Auth.js, Prisma-adapter DB
   sessions) — there is no token/API-key auth path for native clients today.
   Either:
   - (a) drive login through `ASWebAuthenticationSession`/`WKWebView` against
     the existing `/login` flow (Google, Apple, magic-link all already work
     there) and carry the resulting session cookie in `URLSession`'s shared
     cookie storage, or
   - (b) add a token-based auth path to the backend for mobile clients.

   Decide and replace this bullet with the chosen approach once settled.

2. **Push.** Backend push is VAPID web-push (`PushSubscription` model,
   `src/lib/push.ts`), not APNs. Native push notifications need a separate
   APNs integration (certificates/keys, a new subscription model or a
   platform field on the existing one, and native-specific send logic) —
   decide whether that's in scope for v1 or a fast-follow.

3. **Client architecture.** Native SwiftUI vs. a hybrid (Capacitor/React
   Native) wrapping the existing web app. Current lean is native SwiftUI for
   feed feel/performance (swipe-driven vertical feed, haptics, animation
   quality) — confirm before scaffolding, since it commits to rebuilding the
   feed/quiz/guess/misconception UI natively rather than reusing web code.

## Commands

No build yet — Xcode project not scaffolded. Once it exists, replace this
section with the real scheme name and `xcodebuild` invocation (for local
builds and any CI), plus how to point a local build at the backend (local
Next.js dev server vs. sparkletapp.com).
