# Feed, fullscreen, Home artwork and automatic PiP follow-up

This follows the user's physical-device observations on 2.7.0 (17). The previous
simulator orientation check passed while fullscreen on the phone still showed
library tabs and a small landscape player. That check was insufficient.

## Original PineDrama evidence

The original IPA remains read-only at the previously recorded SHA-256
`54b4775cf67cd6a5799d877ae8cd40eba4121848feb891cf4a41a224c19ada44`.
Static Objective-C metadata exposes `PineDramaInnerFeedPreloadService`,
`TTKPineDramaInnerFeedVideoPreloadManager`, and `TTKPineDramaPreloadVideoRecord`
(the latter has `isPreloadSuccess`, `preloadedSizeBytes`, and `urlKey`).
The attached disassembly contains the actual calls to `awemePreloaderClass`,
`preloaderWithBizScene:` and `preloadVideoWithModel:` at file offsets
`0x80a0e98`, `0x80a0ee8`, `0x80a0fbc`. The original also exposes separate tab
model caching and first-frame/pre-render methods. These establish a media
preload path beyond recommendation metadata; they do not prove a particular
cache size or device latency, and the original IPA was not executed here.

## Changes under verification

- Home removes the separate dark gradient attached to the top toolbar. The hero
  retains its continuous legibility gradient.
- Heroes prefer supplied banner artwork. Only the visible anime hero requests
  detail metadata, with its existing cookies/domain handling. The image loader
  retains the sharper decoded image for that hero and never fabricates CDN URLs.
- Native vertical UIScrollView paging contains both the video and footer
  controls, replacing a gesture that changed pages only after finger release.
- At most one next recommendation resolves, decodes its first frame paused and
  muted, with 3 seconds/12 MiB demux limits. Promotion reuses that decoder.
  Warming cannot acquire viewing history, the idle timer, audio-session ownership
  or PiP. Leaving, backgrounding, a memory warning, or 45 seconds discards it.
- Landscape recommendations open a native fullscreen UIViewController with its
  own orientation policy and controls. Tabs, library controls and playlist footer
  stay outside the presentation. Portrait recommendations have no rotate button.
  Physical-screen A/B checks distinguish two faults: app-element captures can
  crop forced-landscape coordinates, and reparenting the old live Metal surface
  still fails the physical-screen pixel check. A fresh surface passes that check.
  The session therefore replaces the native player at the saved episode/time on
  portrait/landscape changes, relinquishing the previous player before installing
  its successor. A stream less than 45 seconds old is reused only in memory; older
  streams resolve again. The original stream timestamp survives replacements.
- PiP creates its AVKit content source and enqueues an actual mpv decoded frame
  during foreground playback. The async snapshot requires mpv `screenshot-sw=yes`,
  so it uses software conversion of a decoded frame and avoids a GPU screenshot
  (which reinitializes the renderer and crashed Metal simulator readback).
  Ordinary playback keeps GPU output. Resign-active
  prepares small software frames; actual background entry requests PiP using the
  prepared content source. Manual PiP uses the same path. Debug-only events record
  readiness, background requests and real AVKit delegate success/failure.

## Required evidence

The release must pass the complete provider/store checks, actual native UI
checks, and MKV/PiP output/seek/pause/GPU restoration checks. Fullscreen UI checks
must include its video surface dimensions and covered tab bar. Feed checks must
observe next-media requests before the swipe and no second delayed resolution.
Pixel checks capture XCUIScreen (the physical display), alongside the application
snapshot and native layer/renderer dimensions. App-element captures alone can
misrepresent forced-landscape window coordinates. System PiP delegate success
is separate from software-frame success. No physical
iPhone is connected to this execution environment; that limit must remain
explicit even if simulator system PiP succeeds.
