# Toolbar / Volume / Fullscreen Improvements — 2026-09-28

## Requests
1. Hide mouse cursor when the transport toolbar auto-hides; restore it when the toolbar reappears.
2. Default volume should be 75% (currently 50%).
3. Show a small indicator on the toolbar for the active Dialogue Boost / Dialogue Max EQ preset (optional, do if feasible).
4. Move the transport toolbar from the top of the window to the bottom.
5. Add full-screen support (menu item + toolbar button), with keyboard shortcut.

## Files touched
- `Lower3rd-MacOS/Lower3rd/ContentView.swift` — main state + layout changes.

## TODO
- [x] Write this plan file.
- [x] `PlayerState.volume` default 50 -> 75.
- [x] Cursor auto-hide/show tied to `isControlsVisible` via `NSCursor.setHiddenUntilMouseMoves` / hide-unhide pairing.
- [x] Add small dialogue-boost/-max indicator icon near the EQ button in `audioAndSubtitleControls`.
- [x] Reposition transport bar to bottom: flip VStack/Spacer order, flip slide offset direction, move "pull tab" sensor region to bottom edge, flip chevron direction (up instead of down).
- [x] Add full-screen toggle: `NSWindow.toggleFullScreen`, wire to a toolbar button + `Menu`/`.keyboardShortcut("f", modifiers: [.command])`, also handle `.commands` app-level menu item under View.
- [x] Build check via `xcodebuild build` — BUILD SUCCEEDED.
