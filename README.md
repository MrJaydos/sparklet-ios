# Sparklet iOS

Native SwiftUI client for Sparklet. See `AGENTS.md` for architecture and the
backend contract this app depends on.

## Building

This project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` rather than committing an `.xcodeproj` — keeps the project
file mergeable and out of source control.

Requires a Mac with Xcode 15+.

```bash
brew install xcodegen
xcodegen generate
open Sparklet.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes (new files added
under `Sparklet/` are picked up automatically — no need to re-run just for
that, since XcodeGen globs the source folder each time it runs).

## Pointing at a local backend

`Sparklet/Config/AppConfig.swift` hardcodes `apiBaseURL`. To test against a
local `sparklet` dev server instead of production, point it at your machine's
LAN IP (not `localhost` — that resolves to the simulator/device itself) and
the port from that repo's `npm run dev` (`PORT=3001`), e.g.
`http://192.168.1.23:3001`.

## Status

See `AGENTS.md` for the full status and what's still open. Feed, read
tracking, header stats, sign-in, and quiz/guess/misconception/review/
explain answering are all built and verified end-to-end against
production as of 2026-07-29 (real sign-in, real feed data, a real guess
answered for XP).
