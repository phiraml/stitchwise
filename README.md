# Stitchwise

A row, repeat and time counter for knitters and crocheters, with offline PDF pattern
annotation. One purchase, no subscription, no account, no cloud.

## Why

The two apps this is aimed at draw the same two complaints: they cost too much for what
they do, and they lose your work. LoopCraft's App Store reviews include patterns
disappearing outright, and content vanishing once a trial ends.

So the product decisions are narrow and deliberate:

| Complaint | What this does about it |
|---|---|
| "My pattern disappeared" | Every save is an atomic `rename(2)` over an fsynced temp file, with a one-generation backup and automatic recovery. The UI *tells you* when it recovered. |
| "It lost my count" | Every counter change is recorded with its previous value. Undo is exact, 250 deep, and survives relaunch. |
| "Everything vanished after the trial" | Paying unlocks *creating* new things. Nothing you have already made is ever locked or deleted. Pinned by a test. |
| "Subscription for a row counter" | One non-consumable purchase. Entitlement is read locally, so it works fully offline. |
| "Basic buggy features" | The domain layer is 54 tests run on every commit, on Linux, in seconds. |

## Layout

```
Sources/StitchCore/       Platform-agnostic domain layer — builds and tests on Linux/Windows
Tests/StitchCoreTests/    54 tests, no simulator required
App/Stitchwise/           SwiftUI app (iOS 17+) — needs macOS to build
App/StitchwiseUITests/    XCUITest journey; screenshots + element trees per step
project.yml               XcodeGen manifest; the .xcodeproj is generated, not committed
.github/workflows/ios.yml Linux core tests + macOS build/UI matrix
```

`StitchCore` deliberately imports nothing but `Foundation`. That is what lets the entire
counter engine, persistence layer, gauge maths and entitlement rules be developed and
tested on a machine with no Xcode.

## Developing without a Mac

```bash
swift build && swift test          # the whole domain layer, ~0.05s
```

The SwiftUI layer is built and exercised by CI on `macos-26`, which generates the Xcode
project with XcodeGen, runs the UI journey across iPhone and iPad, and uploads screenshots
plus the element tree for every step. macOS runners are free and unmetered on public repos.

```bash
gh run watch
gh run download <id> -n "ui-artifacts-iPhone 17" -D ./ci-out
```

## Status

Verified in CI (run 30190164327, all green):

- `StitchCore` — 54 tests on Swift 6.3 (Linux container).
- App builds for iOS Simulator and the UI journey passes on **iPhone 17** and **iPad (A16)**:
  create a project, count ten rows, assert the counter reads 11, undo three times, assert 8,
  relaunch and assert the count survived.

Known gaps:

- **iPad layout is poor.** It passes, but the counter is lost in dead space and the Undo
  control stretches the full width. Needs a size-class-aware layout.
- `PurchaseManager` compiles but no purchase has been exercised — that needs a StoreKit
  configuration file or a sandbox account.
- PDF annotation is untested end to end; the domain layer is covered but no PDF has been
  imported and highlighted in a real run.

## Domain notes

**Linked counters.** A row counter with `cycleLength: 12` linked to a repeat counter
advances the repeat every twelfth row. `wrapBehavior` picks whether the row resets to 1
(`.reset`, what most patterns mean) or keeps climbing as a global count (`.continuous`).
Cascades are depth-limited, so a counter accidentally linked to itself terminates.

**Annotations** are stored as fractions of the page, never points, so a highlighter bar
lands in the same place at any zoom, on any device, after any relaunch. The PDF itself is
never modified.

## Licence

Not yet chosen.
