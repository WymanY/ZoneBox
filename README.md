# ZoneBox

ZoneBox is a native macOS menu-bar utility for FancyZones-style window layouts: draw zones, then snap windows with Shift-drag or the keyboard.

This repository is **proprietary** (All Rights Reserved). It is **not** a fork of MacsyZones and must not incorporate GPL-licensed source.

## Requirements

- macOS 14.0 or later
- Xcode 16+ (local development; GitHub CI uses macos-15)
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

## Use it

1. Open `ZoneBox.xcodeproj` and Run the **ZoneBox** scheme. The first launch opens a **Welcome Tour** that explains where ZoneBox lives, lets you pick a starting layout, and walks through Accessibility if it is not granted yet. The app is signed with a stable Apple Development identity, so the Accessibility grant survives rebuilds.
2. If you skip the tour or later revoke Accessibility, ZoneBox shows a **step-by-step Accessibility guide** (orange warning icon in the menu bar). Click **Open Accessibility Settings**, turn on the **ZoneBox** switch, then return. If the switch is on but snapping still fails, use **Quit & Relaunch**. Reopen the tour anytime from the menu-bar menu (**Welcome Tour…**) or **Settings → General**.
3. Menu extra (`rectangle.split.3x1`, near the clock):
   - **Preview Zones** — flash the current layout
   - **Open Layout Editor** — pick Columns/Rows/2×2 or draw zones, then Save
   - **Layouts** — switch the layout for the display under the mouse
   - **Welcome Tour…** — replay the first-launch walkthrough
   - **Settings…** — Shift-drag, gutter, hotkeys notes
4. Snap a window: drag it by the title bar, hold **Shift** (or right-click while dragging), drop on a numbered zone. Dragging inside the window content does not show the zone overlay. While the overlay is visible, press **1…9** to snap to that zone.
5. After two or more neighboring grid zones each contain one snapped window, a divider handle appears in the seam. Drag it to resize those windows together; the new ratio is saved to the current layout.
6. Keyboard defaults: **Control+Option+1…9** snaps the focused window; **Control+Option+Z** opens the editor; **Control+Option+U** unsnaps; **Control+Option+/** opens the keyboard shortcuts panel; **Command+,** opens Settings. Rebind these in **Settings → Keyboard**.

## Identifiers

| | |
| --- | --- |
| Display name | ZoneBox |
| Bundle ID | `com.fancyzone.app` |
| Minimum OS | macOS 14.0 |
| Distribution | Developer ID + notarization (not Mac App Store) |

## Design

See [docs/design.md](docs/design.md) and [docs/runtime-divider-design.md](docs/runtime-divider-design.md).
