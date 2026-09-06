# Contributing to PeekBar

Thanks for helping. Bug reports, feature ideas and pull requests are all welcome.

## Reporting a bug

Open an issue using the **Bug report** template. The most useful reports include:

- macOS version and chip (for example "macOS 15.6, M1 Pro").
- Whether the display has a notch, and whether an external display was attached.
- Which other menu bar tools were running (Ice, Hidden Bar, Bartender, Stats).
- Steps to reproduce and, if possible, a screenshot of the menu bar.

## Proposing a feature

Open an issue using the **Feature request** template. Describe the problem you're
trying to solve first; the solution can be discussed in the thread.

## Development setup

```bash
git clone https://github.com/nabeeltahirdeveloper/peekbar.git
cd peekbar
swift test                 # unit tests for PeekBarCore
Scripts/build_app.sh       # universal build -> dist/PeekBar.app
Scripts/smoke_test.sh      # launches the app with --debug-bridge and exercises it
```

Xcode 15 or later. Opening `Package.swift` in Xcode works for editing and debugging.

## Code layout

- `Sources/PeekBarCore` holds pure, testable logic: zones, collapse geometry,
  identity matching, metric math, alert rules, layout. No AppKit imports.
- `Sources/PeekBar` holds the app: status items, popup panel, capture,
  Accessibility, metrics engine, SwiftUI views.
- `Tests/PeekBarCoreTests` covers the core library. New policy or math belongs in
  `PeekBarCore` with a test.

## Pull requests

- Keep a PR to one change. Small PRs get reviewed faster.
- `swift test` must pass; CI runs it on every push.
- Match the existing style (4-space indent, no trailing whitespace, `// MARK:` sections).
- Update `CHANGELOG.md` under **Unreleased** for user-visible changes.
- If you touch signing, packaging or permissions, say how you tested it on a clean Mac.

## Releasing (maintainers)

```bash
git tag v0.2.0 && git push origin v0.2.0
```

CI builds a universal DMG and publishes a GitHub Release; the website picks it up
automatically. Move the `Unreleased` entries in `CHANGELOG.md` under the new version first.

## License

By contributing you agree that your contributions are licensed under the MIT License.
