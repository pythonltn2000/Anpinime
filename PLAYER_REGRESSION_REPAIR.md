# Player regression repair — 2.9.1 (20)

**Final automated verification passed.**
[Run 41842672583](https://github.com/letunam2k/anpinime/actions/runs/41842672583),
application revision `477b0c31ecfa7a2ba6396b93b88f41bc45312557`, passed both native
and AI jobs plus the publication gate. The
[published unsigned IPA](https://github.com/letunam2k/anpinime/actions/runs/41842672583/artifacts/13332345272)
was downloaded, digest checked, inspected as 2.9.1 (20), and confirmed byte-identical
to the tested candidate. Application subtree: `fab1073297653919baba71e5c4534c4acd6a0a3e`.
Later evidence/report updates do not change application or test sources.

Eight XCTest cases ran: seven passed, zero failed, one explicitly skipped because
AVKit system PiP is unsupported on Simulator. Both fresh PineDrama live tests
passed. Native anime failure recovery, MKV software PiP pause/seek/GPU restore,
HLS relay and three exact Core live servers also passed. Physical iPhone PiP and
fresh AnimeVietsub access remain unverified; Free1 segments still returned 404.
The sections below retain the investigation history and its earlier pending states.

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

## iOS evidence at b208461

[Run 41798383187](https://github.com/letunam2k/anpinime/actions/runs/41798383187)
passed the native build/playback job. The generated anime fixture produced
advancing decoded video. The native-failure case received an actual HTTP 403,
restored the same retained WebKit video, advanced to 7.74 seconds and cleared
loading. Server counters confirm one document load and that the nested ad frame
was exercised without taking playback ownership. MKV software PiP produced
11 visible frames and passed pause/seek/GPU restoration.

The AI job passed actual five/ten-file prefetch, shorts/swipe/fullscreen, player
inactivity and movie artwork/title hit checks. Book episode-drawer taps missed
the empty center of the glass pill; the label now defines its entire hit shape.
The library-choice check reached the real Movie library and timed out while
waiting for its tabs. This check includes live Movie network I/O; the evidence
does not identify a production navigation bug. It remains a required rerun,
with its existing assertions and time limit retained.
The release gate correctly withheld the verified IPA while these checks failed.

Fresh Core MKV decoded exact selected servers: Wakanda 31937, Spider-Man 34793
and 34794. This does not establish universal startup improvement. Anime live was
blocked by browser verification before episode playback. Free1's manifest was
HTTP 200 but its first segments were HTTP 404, with no decoded-playback success.
Automatic PiP telemetry only shows a prepared frame, not an AVKit didStart;
unsupported Simulator system PiP was explicitly skipped.

The follow-up also retains WebKit's automatic-PiP preference before a delayed
video exists. JavaScript tests exercise both enabled and disabled preferences
and require that configuring either never forces a PiP start.

## Follow-up at 2aa3e39

[Run 41802881152](https://github.com/letunam2k/anpinime/actions/runs/41802881152)
again passed the complete native job, including actual native failure followed
by advancing WebKit video with loading cleared. The 40-episode book-player
fixture now passes the complete drawer, final episode, history and lifecycle
checks. The glass-button hit-area repair is verified on iOS.

Library selection again stalled after Movie was tapped. Independently of the
unproven runtime trigger, RootView had a definite cancellation cleanup gap:
its task could return after cancellation with a touch-blocking animated overlay
still installed. Disappearance now cancels the task and clears that overlay.
No provider or production transport change is used to mask this check.

Live book telemetry shows the swipe remained on episode 1, with the same player
and advancing HEVC video (34.3 to 36.9 seconds); it never selected episode 2.
The harness now distinguishes gesture selection from decoding and permits one
additional real swipe only if the original episode remains selected. Exact
episode identity, decoded dimensions and advancing video remain required.
The live shorts catalog supplied a 148-episode series. Its group selection uses
a real horizontal pan along the visible group controls instead of the scroll
view's potentially empty center. This is bounded navigation through the actual
drawer, not a direct state or provider shortcut.

The release gate remains closed until the follow-up full suite passes. Fresh
anime live and physical-device PiP retain the verification limits above.

## Hidden verification browser and accessibility

The catalog timeout's system spindump provides a more specific lead than a
network timeout. During the 4.99-second sample, the app main thread was idle
(0.005 seconds total CPU). Testmanagerd was waiting for an accessibility window
snapshot. A WebContent worker was loading its accessibility bundle under I/O
throttling; WebContent viewport setup was also delayed. This does not prove the
exact IPC target, and does not establish a provider or MainActor deadlock.

RootView attached the anime verification WebKit view to Movie as well. Movie
providers never use WebsiteSession, so this unnecessary attachment is removed.
The hidden anime browser now sets native `accessibilityElementsHidden` and
disables native interaction in addition to SwiftUI's accessibility modifier.
The visible challenge resets those properties. Host updates are guarded against
the current interaction state so an outgoing host cannot overwrite the new one.
Provider/network behavior and the ability to complete a visible anime challenge
are preserved. The next CI must establish the navigation result; the change is
not presented as proof of fresh AnimeVietsub playback.

## Navigation verified at 300e1f1; live test budget

[Run 41808275769](https://github.com/letunam2k/anpinime/actions/runs/41808275769)
passed the full native job and all six UI cases (five passed, one explicit
unsupported-system-PiP skip). Movie/Anime/AI switching now passed, together with
the complete episode drawer, shorts/fullscreen, transient inactivity and movie
result hit testing. The hidden-browser change has native navigation evidence.

The live book check decoded its exact first and second episodes and selected
the independently verified final episode 56. Host accessibility queries took
longer in this run: the last-episode tap occurred at 104 seconds, while the entire
live test's deadline was 108 seconds. Its normal 25-second decode check therefore
received only about four seconds. The job's separate 25-minute ceiling then
canceled the second live case before completion. No verified IPA was released.

Only harness/CI budgets change in the follow-up: the live case has a 180-second
overall budget, XCTest has 195 seconds with a 200-second runner ceiling, and the
whole AI job has 40 minutes for compilation, fixture and both live cases. The
per-video decode and advancement bounds, exact identity, dimensions and single
owner checks remain unchanged. Application sources are identical to 300e1f1.

## Final result

The revised overall budget allowed both live cases to finish, with their original
25-second combined decoded-video/advancement checks retained. The catalog series
test passed in 96.5 seconds and the short-feed complete-playlist test in 68.6 seconds.
The fixture suite passed navigation among all three libraries, a complete 40-episode
drawer and history, native shorts/fullscreen, transient inactivity without PiP or
owner replacement, and exact movie artwork/title selection.

Native failure recovery advanced the retained WebKit video to 7.255 seconds with
loading cleared and no reload after failure. The MKV test produced ten visible
software PiP frames and restored pause/seek/GPU state. These are controlled and
Simulator results, not proof of an iPhone system PiP window. Fresh anime remained
behind website verification; Free1 failed with 22 HTTP 404 segment observations.
Their missing success artifacts remain failures despite optional-step status.

Final artifact identity and publication requirements are recorded in
[release-artifact.json](Tools/evidence/2026-11-04-player-regression/release-artifact.json).
The nine protected provider/parser/transport files remain byte-identical to
`a785d35868e5fb7b7f67e5ca04b5be3d005f4d3a`; ordinary mpv options are unchanged.

## Harness corrections

The delayed episode response is explicitly gated until the next episode request,
so XCTest/AX scheduling cannot invalidate the cancellation scenario. Clip startup
keeps its five-second bound and measures in-app promotion to playing instead of
host swipe automation time. Fixture selection scrolls to the exact card; live
episode drawer tapping waits for hittability without increasing its timeout.
