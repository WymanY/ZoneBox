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

## Snap diagnostics

Drag diagnostics are saved locally across restarts, without starting a live log capture:

- Debug: `~/Library/Application Support/com.fancyzone.app.debug/Logs/snap.jsonl`
- Release: `~/Library/Application Support/com.fancyzone.app/Logs/snap.jsonl`

Each JSON line includes a timestamp, app-run ID, drag-session ID, and technical event fields. Target changes, the displayed preview, mouse-up selection, and requested/returned window frames can be correlated within one drag. No window titles, document contents, screenshots, or credentials are recorded or uploaded.

Writes run off the main thread. The current file and four rotated files (`snap.1.jsonl` through `snap.4.jsonl`) retain up to 10 MiB total; older entries are replaced as the files fill. When reporting an intermittent snap failure, note the approximate time and the intended versus actual pane. Keep the rotated files too, since the relevant drag may have crossed a rotation.

## Identifiers

| | |
| --- | --- |
| Display name | ZoneBox |
| Bundle ID | `com.fancyzone.app` |
| Minimum OS | macOS 14.0 |
| Distribution | Developer ID + notarization (not Mac App Store) |

## License

Snapping, layouts, numbered hotkeys, and divider handles stay free. ZoneBox Pro is a US$14.99 lifetime license (US$9.99 for the first 30 days) sold through [Creem](https://www.creem.io): workspaces, hover pin, and Quick Snapper. One key activates 2 Macs. New installs include a 14-day Pro trial. Buy from the [product site](https://zonebox-site.vercel.app/buy), then activate in **Settings -> License**.

See [docs/license.md](docs/license.md).

## Design

See [docs/design.md](docs/design.md) and [docs/runtime-divider-design.md](docs/runtime-divider-design.md).
