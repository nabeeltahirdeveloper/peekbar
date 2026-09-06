# Changelog

All notable changes to PeekBar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned
- Notarized, Developer ID signed builds (removes the right-click ▸ Open step).
- Homebrew cask.
- Opt-in in-app update check against GitHub Releases.

## [0.1.0] - 2026-09-06

First public release.

### Added
- Notch-safe popup under the menu bar showing hidden extras with their real icons; click opens the extra's genuine menu via Accessibility, right-click is forwarded.
- Pinned, Pocket and Vault zones; ⌘-drag past the divider to hide, drag a tile onto the bar to pin, Arrange mode (⌥⌘A) with a HUD.
- Two reveal modes: popup below the bar (default) or slide-into-bar, Hidden Bar style.
- Search, keyboard navigation, "New" badges, Known-incompatible list, layout export/import as JSON.
- System monitoring: CPU, Memory, Disk, Network, Battery, GPU, Sensors, Bluetooth and Clock modules with dashboard cards, detail pages and top processes.
- Menu bar widgets: mini, line chart, bar chart, ring, tachometer, label, speed, battery, memory bar, state dot; right-click to restyle, ⌘-drag to reorder.
- Threshold alerts delivered as macOS notifications with hysteresis and repeat limiting.
- Seven-step first-run walkthrough with live permission status.
- Demand-driven sampling: nothing is read while no card, widget or alert needs it.
- Universal (Apple Silicon + Intel) builds, macOS 12 Monterey through macOS 26.

[Unreleased]: https://github.com/nabeeltahirdeveloper/peekbar/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nabeeltahirdeveloper/peekbar/releases/tag/v0.1.0
