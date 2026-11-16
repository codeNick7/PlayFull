# 90s-Style Broadcast Lower-Third Local Video Player — Technical Spec

**Version:** 0.1
**Status:** Draft
**Owner:** TBD

---

## 1. Overview

A desktop application that plays local video files from disk and, at the start
of each video, displays an animated "now playing" overlay (artist, track/album,
optional year/label) in the bottom-left corner — modeled on classic 90s
music-television on-air bugs.

The project is split into two phases so a working end-to-end player exists
early, before investing in custom overlay rendering:

- **Phase 1 — Marquee:** libvlc + built-in marquee filter. Fastest path to a
  functioning player. Native text overlay, no custom rendering.
- **Phase 2 — Native libvlc + custom overlay:** libvlc for decode/playback and
  metadata parsing, but the overlay is hand-rendered (HTML/CSS or native view)
  for full control over typography, animation easing, and layout — matching
  the retro broadcast aesthetic rather than VLC's native OSD look.

Both phases share the same metadata pipeline and playback engine choice
(libvlc), so Phase 2 is additive, not a rewrite.

---

## 2. Goals / non-goals

**Goals**
- Play common video containers/codecs from local disk (mp4, mkv, mov, avi at minimum).
- On load of each video, show artist / track / album (+ optional year) bottom-right.
- Overlay appears on load, holds a few seconds, fades out; does not require user interaction.
- Reliable metadata resolution across embedded tags, filename convention, and sidecar files, in that priority order.
- Basic transport: play/pause, seek, next/previous in a folder or playlist.

**Non-goals (v1)**
- Streaming/network sources.
- DRM'd content.
- Full metadata *editing* UI (write-back to tags) — read-only for v1.
- Multi-overlay themes/skinning system — one retro broadcast theme, hardcoded, for v1.

---

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│                 Application shell             │
│   (Electron/Tauri, or native Qt/Swift/Win32)  │
│                                               │
│  ┌───────────────┐      ┌──────────────────┐ │
│  │  Overlay layer │      │  Transport UI     │ │
│  │  (Phase 2:      │     │  (play/pause/seek)│ │
│  │  custom render) │      └──────────────────┘ │
│  └───────┬───────┘                             │
│          │ metadata lookup                      │
│  ┌───────▼───────────────────────────────────┐ │
│  │           Metadata resolver                 │ │
│  │  1. libvlc embedded tags                     │ │
│  │  2. sidecar .json/.nfo                       │ │
│  │  3. filename convention parse                │ │
│  └───────┬───────────────────────────────────┘ │
│          │                                       │
│  ┌───────▼───────────────────────────────────┐ │
│  │              libvlc (embedded)               │ │
│  │  - decode / demux / render                   │ │
│  │  - Phase 1: native marquee filter             │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Shared components across both phases**
- libvlc as the playback engine (decode, seek, AV sync, hardware accel).
- Metadata resolver module (format-agnostic; used identically in both phases).
- Video file library scanner (folder → list of playable items).

**What changes between phases**
- Phase 1: overlay = libvlc marquee filter calls.
- Phase 2: overlay = a rendering surface (HTML/CSS layer, or native view) composited on top of the video output, driven by the same metadata + timing events, swapping out only the marquee calls.

---

## 4. Metadata pipeline

### 4.1 Resolution order (first hit wins per field)
1. **Embedded container tags** — via `libvlc_media_get_meta()`
   (`libvlc_meta_Artist`, `libvlc_meta_Album`, `libvlc_meta_Title`,
   `libvlc_meta_Date`, `libvlc_meta_Genre`).
2. **Sidecar file** — `<video-filename>.json` in the same directory:
   ```json
   {
     "artist": "Artist Name",
     "track": "Track Title",
     "album": "Album Name",
     "year": 1998
   }
   ```
3. **Filename convention parse** — fallback pattern:
   `Artist - Track.ext` or `Artist - Album - Track.ext`.
4. **Unknown** — fields not resolved by any method are omitted from the overlay (no "Unknown Artist" placeholder clutter).

### 4.2 Data model
```ts
interface TrackMetadata {
  artist?: string;
  track?: string;
  album?: string;
  year?: number;
  source: "embedded" | "sidecar" | "filename" | "none";
}
```

### 4.3 Library index (optional, recommended for folders with many files)
SQLite table caching resolved metadata per file path + mtime, so re-scans are
incremental. Not required for Phase 1 if testing against a small folder, but
worth building early since both phases need it.

```sql
CREATE TABLE library (
  path TEXT PRIMARY KEY,
  mtime INTEGER,
  artist TEXT,
  track TEXT,
  album TEXT,
  year INTEGER,
  source TEXT
);
```

---

## 5. Phase 1 — Marquee

### 5.1 Scope
- Embed libvlc in the chosen shell (Electron via `node-vlc`/`libvlc` bindings,
  or native via `libvlc` C API directly).
- On `libvlc_MediaPlayerPositionChanged`/`file loaded` event, resolve metadata
  via the pipeline in §4, format as a single string, and call the marquee API.

### 5.2 API surface used
```c
libvlc_video_set_marquee_string(mp, libvlc_marquee_Text, formatted_text);
libvlc_video_set_marquee_int(mp, libvlc_marquee_Position, libvlc_position_BottomRight);
libvlc_video_set_marquee_int(mp, libvlc_marquee_Opacity, 200);      // 0-255
libvlc_video_set_marquee_int(mp, libvlc_marquee_Timeout, 4000);     // ms; 0 = persistent
libvlc_video_set_marquee_int(mp, libvlc_marquee_Enable, 1);
```

### 5.3 Text formatting rules
- Single line, format: `ARTIST — TRACK` (album/year omitted from marquee to
  keep it readable — marquee has no multi-line/style control).
- If artist unresolved: show track only. If nothing resolved: no overlay call.

### 5.4 Behavior spec
| Event | Behavior |
|---|---|
| New video loaded | Resolve metadata → set marquee text → enable → timeout starts |
| Seek within same video | Overlay does not re-trigger |
| User pauses | Overlay state unaffected (already faded per its own timeout) |
| Next/previous track | Overlay re-triggers per "new video loaded" rule |

### 5.5 Acceptance criteria
- [ ] Player loads and plays mp4/mkv/mov/avi from disk.
- [ ] Overlay appears bottom-right within 1 video frame of playback start.
- [ ] Overlay auto-hides after configured timeout (default 4s).
- [ ] Metadata resolution correctly prioritizes embedded → sidecar → filename.
- [ ] No overlay shown when zero metadata fields resolve.

### 5.6 Known limitations (accepted for this phase)
- No fade in/out easing — marquee timeout is a hard cutoff, not an animation.
- No custom font/weight — respects VLC's OSD rendering (usually a system default font).
- Single-line only — no album/year secondary line.

---

## 6. Phase 2 — Native libvlc + custom overlay

### 6.1 Scope
Replace the marquee filter with a hand-rendered overlay layer composited over
the video surface, while keeping libvlc for decode + metadata resolution
unchanged from Phase 1.

### 6.2 Rendering approach by shell
| Shell | Overlay technique |
|---|---|
| Electron/Tauri | Transparent HTML/CSS `<div>` absolutely positioned over the `<video>`/render `<canvas>`, animated with CSS transitions/keyframes |
| Qt | `QGraphicsScene` overlay item or QML `Rectangle` layered above `VLCVideoItem`/`QVideoWidget`, animated with `QPropertyAnimation` |
| Native macOS | `NSView`/`CALayer` overlay above the video-rendering `NSView`, animated with Core Animation |
| Native Windows | Layered child window or Direct2D overlay above the libvlc render surface |

### 6.3 Overlay visual spec (Broadcast-style lower third)
- **Position:** bottom-left, ~44px margin from edges.
- **Content, two lines:**
  - Line 1 (bold, larger): Artist
  - Line 2 (regular, smaller, muted): Track — Album (Year)
- **Animation timeline:**
  - `0ms`: video starts, overlay begins fade/slide-in (translateY + opacity, ~400ms ease-out)
  - `400ms–4000ms`: held fully visible
  - `4000ms–4500ms`: fade-out (opacity only, ~500ms ease-in)
- **Typography:** custom font (condensed sans, broadcast feel), configurable via theme file.
- **Re-trigger rule:** same as Phase 1 §5.4 — only on new video load, not on seek/pause.

### 6.4 Event bridge
libvlc playback events (`file loaded`, `time changed`) are forwarded from the
libvlc binding layer to the overlay renderer via the shell's IPC (Electron:
main→renderer IPC; Qt: signals/slots; native: delegate/callback).

```ts
// Example event contract (shell-agnostic)
type PlaybackEvent =
  | { type: "loaded"; metadata: TrackMetadata }
  | { type: "timeUpdate"; positionMs: number }
  | { type: "ended" };
```

### 6.5 Theming (stretch goal for Phase 2)
Overlay style externalized to a small config (JSON/CSS) so position, timing,
and typography can be adjusted without code changes — sets up future
multi-theme support if desired later, without being in v1 scope.

### 6.6 Acceptance criteria
- [ ] Overlay renders with fade-in/hold/fade-out per §6.3 timeline.
- [ ] Overlay typography matches the defined theme (custom font, sizes, colors).
- [ ] No visible tearing/flicker where overlay meets video surface during animation.
- [ ] Overlay layer does not block mouse interaction with transport controls beneath it.
- [ ] Metadata pipeline unchanged and reused from Phase 1 without modification.

---

## 7. Platform/tech decisions to confirm before starting

| Decision | Options | Notes |
|---|---|---|
| Shell | Electron / Tauri / native Qt / native per-OS | Electron+node bindings = fastest Phase 1; native = better Phase 2 animation performance, more upfront work |
| libvlc binding | `node-vlc`, direct C API via native module, Qt's `libvlcpp` | Depends on shell choice |
| Codec coverage | Rely on libvlc's bundled decoders vs system codecs | libvlc bundles most common codecs; verify HEVC/AV1 support if needed |
| Sidecar format | JSON vs NFO (Kodi-style XML) | JSON recommended — simpler to parse/maintain |

---

## 8. Milestones

1. **M0 — Playback spike:** libvlc embedded in chosen shell, plays a file, basic transport works. *(validates architecture choice before any overlay work)*
2. **M1 — Metadata pipeline:** resolver implemented and tested against embedded/sidecar/filename cases.
3. **M2 — Phase 1 complete:** marquee overlay wired to metadata + load events, acceptance criteria in §5.5 pass.
4. **M3 — Phase 2 overlay prototype:** custom overlay renders with correct positioning/timing, no animation polish yet.
5. **M4 — Phase 2 complete:** animation/typography finalized, acceptance criteria in §6.6 pass.

---

## 9. Open questions

- Target platform(s) for v1 — single OS or cross-platform from the start?
- Expected library size — dozens of files (filename parsing sufficient) or thousands (library index/SQLite becomes necessary earlier)?
- Any licensing constraint on shipping libvlc (LGPL) — closed-source distribution needs dynamic linking, not static.
