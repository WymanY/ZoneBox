# ZoneBox live runtime ownership

This is the current construction drawing for live window interaction. docs/design.md is a historical MVP decision log, not the runtime spec.

## Who owns window writes

AppRuntime is the composition root. It owns:

- WindowMutationEngine: exclusive RuntimeMode plus the serial mutation queue
- live services (SnapEngine, DividerController, PinCenter, PinHoverMonitor, WorkspaceCenter, DragMonitor, HotkeyCenter) through narrow host protocols

Those services no longer take a concrete AppRuntime back-reference. They ask the host for mode, catalog, overlay, settings, and mutation. UI controllers such as Settings/Editor/menu bar still talk to AppRuntime because they are not live window writers.

Live modes are exclusive:

| Mode | Owner | May capture pointer | May write AX |
| --- | --- | --- | --- |
| idle | nobody | yes | yes |
| snapping | SnapEngine / Quick Snapper | yes | yes |
| dividing | DividerController | no | yes |
| pinningFollow | PinCenter while a pin is being dragged | no | raise only |
| organizing | WorkspaceCenter / organize | no | yes |
| editing | layout editor | no | no |

Divider, pin hover, pin follow/raise, workspace census, organize, and the editor all consult this gate. Reading isEditorOpen, isOrganizingWindows, or engine.isSessionActive is not the ownership model.

All AX frame writes and pin raises go through one WindowMutationQueue:

- one writer at a time
- session id + generation
- later generation for the same session wins
- cancel drops queued and in-flight writes
- timeout aborts a stalled writer so mouse-up can still land the latest frame

Divider's local drain loop is now a client of that global queue, not a second write owner.

## TCC boundary

Live mutation requires Accessibility. Pin mirroring also requires Screen Recording. Both are fail-closed:

- no Accessibility: no snap, divider drag, organize, workspace apply, or pin raise
- no Screen Recording: no pin mirror; the original window is unchanged

A successful private window-level call is not part of this architecture and is not a proof of always on top.

## Explicit non-guarantees

- Stage Manager and system Split View are not owned, restored, or synchronized.
- Spaces are not a first-class layout key. Display identity is.
- Pin is not a private window-level always-on-top implementation.

## Pin, as it actually works

Pin is a ScreenCaptureKit mirror plus a best-effort Accessibility raise of the source window.

- the mirror is click-through (ignoresMouseEvents = true)
- clicks, scrolling, and typing go to the original window
- Screen Recording is required
- raise is best-effort and can lose to full-screen apps, Stage Manager, and system tiling

Do not treat a green test suite or a successful CGS level write as proof that a foreign window is truly frontmost.

## Tests

Core tests can fail the execution contract without a TEST_HOST:

- RuntimeOwnershipTests: mode exclusion, latest-generation apply, divider mouse-up final frame, cancel
- SnapSessionReducerTests: the old SnapEngineTests file, which never tested SnapEngine

AppKit overlay visibility, ScreenCaptureKit mirrors, and real mouse-up on a foreign window remain manual.
