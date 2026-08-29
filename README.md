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

1. Open `ZoneBox.xcodeproj` and Run the **ZoneBox** scheme. The app is signed with a stable Apple Development identity, so the Accessibility grant survives rebuilds — grant it once and ordinary Xcode Run/debug works for snapping too.
2. If snapping is unavailable, ZoneBox shows a **step-by-step Accessibility guide** (orange warning icon in the menu bar). Click **Open Accessibility Settings**, turn on the **ZoneBox** switch that matches the path in the guide, then return. If the switch is on but snapping still fails, use **Quit & Relaunch**.
3. Menu extra (`rectangle.split.3x1`, near the clock):
   - **Organize Windows** — auto-pick a temporary layout from the window count on the display under the pointer without changing saved layouts. Windows that keep their position but refuse a smaller size are moved into the larger primary area. Windows that refuse both size and position stay put as obstacles, and the rest of the layout fills the largest remaining rectangle. A HUD then offers Restore Layout and, when the app is known, Ignore App.
   - **Preview Zones** — flash the current layout
   - **Open Layout Editor** — pick Columns/Rows/2×2 or draw zones, then Save
   - **Layouts** — switch the layout for the display under the mouse
   - **Settings…** — Shift-drag, gutter, hotkeys notes
4. Snap a window: drag it by the title bar, hold **Shift** (or right-click while dragging), drop on a numbered zone. Dragging inside the window content does not show the zone overlay. While the overlay is visible, press **1…9** to snap to that zone.
5. Keyboard: **Control+Option+O** organizes windows on the focused display; **Control+Option+1…9** snaps the focused window; **Control+Option+Z** opens the editor; **Control+Option+U** unsnaps; **Control+Option+/** opens the keyboard shortcuts panel.

## Identifiers

| | |
| --- | --- |
| Display name | ZoneBox |
| Bundle ID | `com.fancyzone.app` |
| Minimum OS | macOS 14.0 |
| Distribution | Developer ID + notarization (not Mac App Store) |

## Design

See [docs/design.md](docs/design.md).
