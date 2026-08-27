# ZoneBox

ZoneBox is a native macOS menu-bar utility for FancyZones-style window layouts: draw zones, then snap windows with Shift-drag or the keyboard.

This repository is **proprietary** (All Rights Reserved). It is **not** a fork of MacsyZones and must not incorporate GPL-licensed source.

## Requirements

- macOS 14.0 or later
- Xcode 15+ (local development)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project after file-tree changes (`brew install xcodegen`)

## Build

```sh
./scripts/bootstrap.sh   # xcodegen generate
open ZoneBox.xcodeproj
```

Or from the command line:

```sh
make project
make test
```

`make test` runs `ZoneBoxTests` against the `ZoneBoxCore` static library (no app host) and fails if any file under `ZoneBox/` imports SwiftUI.

## Human checkpoint (PR 1)

1. Open `ZoneBox.xcodeproj` and Run.
2. A status extra appears in the menu bar (`rectangle.split.3x1`).
3. **Settings…** opens a titled window in front (the app temporarily becomes a regular app, then returns to accessory on close).
4. **Snap Enabled** toggles with a checkmark.
5. **Quit ZoneBox** exits.

Window snapping, the layout editor, and Accessibility onboarding land in later PRs. After Accessibility is added: enable ZoneBox in System Settings → Privacy & Security → Accessibility, then **quit and reopen** the app if snapping still does nothing.

## Identifiers

| | |
| --- | --- |
| Display name | ZoneBox |
| Bundle ID | `com.fancyzone.app` |
| Minimum OS | macOS 14.0 |
| Distribution | Developer ID + notarization (not Mac App Store) |

## Design

See [docs/design.md](docs/design.md).
