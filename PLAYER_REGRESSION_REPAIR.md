# Player regression repair — 2.9.1 (20)

This repair addresses the severe anime/PiP regression reported against the 2.9.0
candidate. Repository: `letunam2k/anpinime`, branch `feature/ai-drama`, draft PR #1.
The previous candidate is not evidence that these issues are fixed.

## Confirmed causes and changes

- Anime fallback could promote an intercepted manifest based on duration, hide
  the working WebView and install mpv without a recovery callback. Manifest
  inference is removed. Website-decoded blob/playlist hints stay in WebKit.
  Actual decoded HTTP sources can be attempted, with decoder failure/no-frame
  timeout returning to the same document, position and pause intent. A failed
  handoff cannot loop through rotating URLs. Verification polling resumes.
- 2.9 manually requested PiP on `willResignActive` and visibility changes.
  These also occur during Control Center, system overlays and presentation.
  Inactivity now only arms native PiP. The fallback request occurs on actual
  background; AVKit can perform its own eligible automatic transition.
- AI treated temporary inactivity as teardown and could pause the decoder before
  PiP started. It now preserves the current owner/intent during inactivity,
  reconciles actual background after native notification handlers, and retains
  active/pending PiP independently of inline surface attachment.
- PiP content source, layer and delegate remain alive until AVKit finishes
  stopping. GPU restore precedes render-context freeing. Late callbacks are
  generation guarded; automatic starts, timeouts and EOF cannot create duplicate
  sessions. Shutdown silences the decoder and releases its VO before destruction.
  WebKit DOM isolation/layout stops while its system presentation owns the video.

Provider/catalog/parser/transport files protected for movie sources 1/3 remain
unchanged. Standard mpv buffering options and source-2 signing/transport remain
unchanged. This is a playback/lifecycle repair, not a catalog or UI redesign.

## Required verification

- Existing JavaScript regressions plus blob-decoder preservation, pause intent,
  WebKit PiP single ownership and no visibility-triggered PiP.
- New mandatory native anime failure fixture: a real decoded WebKit video,
  native HTTP 403, same document restored, advancing decoded web video and no
  website reload. Old stranded-native behavior must fail this test.
- Existing MKV two-audio/two-subtitle native playback and software PiP
  pause/seek/GPU restoration.
- New always-run transient inactive UI case: unchanged player identity,
  GPU output, playing/pause intent, no PiP activation or pending request.
- Actual Home PiP case: two cycles, AVKit didStart/didStop counters, one owner,
  GPU and geometry restored. Unsupported Simulator system PiP is explicitly
  skipped, never counted as physical-device proof.

Local Swift syntax parse, seven JavaScript groups, Python compilation, shell
syntax and diff checks pass. Native iOS checks are pending at the initial commit
of this report. Only the run for the published revision can establish its result.
Fresh anime behind browser verification and real iPhone PiP window behavior must
remain explicitly unverified until observed.

## Harness corrections

The delayed episode response is explicitly gated until the next episode request,
so XCTest/AX scheduling cannot invalidate the cancellation scenario. Clip startup
keeps its five-second bound and measures in-app promotion to playing instead of
host swipe automation time. Fixture selection scrolls to the exact card; live
episode drawer tapping waits for hittability without increasing its timeout.
