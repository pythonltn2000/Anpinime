# Source 2 startup — 2026-11-02

Read REPAIR_REPORT_V3, V5, V6 and source2-analysis before changing the source-2
transport. The latest baseline CI `41370007452` has decoded Wakanda gateway media,
but its `15.641` media time is the screenshot threshold after a black intro;
it is **not** a wall-clock startup measurement. Core was 403 in that earlier run,
Free1 segments were 404, and anime required browser verification.

## Exact user sample

The user's slow sample is **Người Nhện: Khởi Đầu Mới**. An original Core search
returned exactly one row, ID **17997**, titled
`Người Nhện: Khởi Đầu Mới (2026) Spider-Man: Brand New Day`.
The localized title before the provider's year/original-title suffix matches
exactly. The exact detail endpoint returned HTTP 200 and five original servers:

| Server ID | Original server label summary |
| --- | --- |
| 34793 | 1080P H.264 MKV 9GB |
| 34795 | VIE.AI 1080P H.264 MKV 10GB |
| 34794 | 2160P H.265 DV/HDR MKV 26GB |
| 34798 | VIE.AI 2160P H.265 DV/HDR MKV 27GB |
| 34860 | 2160P IMAX BCORE HDR MKV 86GB |

Only the original lowest-size **34793** and higher **34794** were exchanged at
the authenticated, directory-announced gateway and decoded. No other movie,
server, provider, account session or premium entitlement was substituted.
The API's `file_type` and media MIME say MP4; actual 2-KiB prefixes establish MKV.

| Observed property | 34793, lowest original | 34794, higher original |
| --- | --- | --- |
| Actual declared bytes | 9,795,894,395 | 27,162,895,108 |
| Decoded video | H.264, 1920×800 | HEVC, 3832×1600 |
| Container bitrate | 9,007 kbit/s | 24,975 kbit/s |
| First decoded frame, wall time | 1.596 s | 1.390 s |
| Decoded output | 480 frames / 20.020 s | 480 frames / 20.020 s |
| Total decode process time | 2.280 s | 5.575 s |
| Tail/Cues bytes | 11,230 | 10,975 |
| Tail request time | 0.392 s | 0.635 s |
| Total upstream bytes read | 12,790,750 | 15,280,863 |

Both exited 0. Linux FFmpeg used a loopback observation adapter that forwarded
Range and the original `oxoo` User-Agent to the exact gateway media URL through
the mandatory inherited proxy. Output went to a null sink; no movie bytes were
saved. Each process had a 50-second deadline, 64-MiB network budget, 2-MB probe,
3-second analysis bound and 20-second decoded-output limit. Requests and their
byte counts are recorded in the safe JSON evidence, without signed URLs.

These observations do not show a large Cues scan: each tail read was about 11 KB.
The higher stream advertises about 2.8 times the bitrate and took about 2.4 times
the CPU decode time for these first 20 seconds. That is consistent with a larger
bandwidth/decode requirement, but does not establish the cause of the user's
sustained phone lag. These are early-stream Linux measurements, not iPhone or
whole-film playback results. Shared mpv cache, seeking and probe defaults stay
unchanged; `cache-secs=20` is readahead capacity, not proof of a 20-second gate.

## Targeted change

The provider previously refreshed the directory again at every Core resolve,
even immediately after opening a detail page had authenticated that directory.
It now reuses a successful directory announcement for **120 seconds** within that
source-2 provider. Failed or unauthenticated refreshes do not extend the TTL;
explicit invalidation clears it. A valid partial directory retains older fields,
so this is a directory TTL, not a claim that every CDN field was freshly supplied.
Exact Core detail, chosen server/handle, gateway exchange and media validation
remain fresh on every resolve.

One bounded 2-KiB GET now validates media bytes directly. It replaces serial
HEAD→GET on HEAD-rejected/unknown responses, preserves 200/206 behavior, cancels
Range-ignored large bodies at the existing prefix bound, rejects authentication,
HTML/JSON and empty-body responses, and hands the actual validated final redirect
URL to the player. The observed live sample's HEAD already returned 200, so its
media probe count is **one before and one after**; no two-to-one claim is made for
that path. Sources 1/3, the HLS relay and shared mpv defaults were not changed.

A single ordered live-request harness for **17997/34793** measured the existing
resolve sequence at **4 requests / 1.769 s**, and the revised sequence at
**3 requests / 1.540 s**. Each fetched the exact Core detail and live gateway;
the revised sequence reused the directory authenticated seconds earlier and read
actual MKV bytes. The removed directory call took 0.128 s. This is a small observed
improvement in one network pair; cache/warm-up variance and Python transport mean
it is not a stable speedup estimate or native iOS startup timing.

## Native measurement and regression coverage

DEBUG diagnostics now retain monotonic elapsed time, resolve stages, first
observed file-loaded and first advancing video with decoded dimensions. The latter
milestones survive later player-state coalescing; their observation resolution is
approximately 250 ms. Screenshot media-time thresholds remain separate.

The existing provider regression now asserts one media GET and three requests
for fresh detail→gateway→media when a supplied configuration bypasses bootstrap.
It also checks authenticated-directory reuse, explicit invalidation, failed
authentication not renewing success, empty media rejection and unchanged exact
server/credential boundaries. The Range suite retains ignored-Range 200
cancellation and now checks the final followed URL.

Local: range virtual-origin fixture PASS, shell syntax PASS and diff check PASS.
Swift provider/Range tests and iOS playback require CI: this Linux executor has
no `swiftc`. No workflow was dispatched by this investigation.

For the exact user sample, preserving the default Wakanda smoke:

```sh
ANPINIME_CORE_ID=17997 ANPINIME_SERVER_ID=34793 \
ANPINIME_RESULT_SUFFIX=spiderman-34793 ANPINIME_MIN_PLAYBACK_SECONDS=20 \
bash Tests/phim4k-live-smoke.sh vip
```

Use server `34794` and suffix `spiderman-34794` for a separate higher-stream
artifact. DEBUG app arguments are `--phim4k-core-id`, `--phim4k-server-id` and
`--phim4k-result`. IDs and result names are validated, and the wrapper asserts the
selected exact IDs, decoded dimensions/codec, first-video elapsed time and
requested media time. JSON, diagnostics and PNG filenames include the suffix.

Safe evidence: [2026-11-02-source2-startup](evidence/2026-11-02-source2-startup/).
Private Core responses, returned media URLs, original IPA/decompilation and raw
network diagnostics remain outside the repository.


## Decoded black intro, separate from network startup

A final optional pass examined the first 20 seconds of the same exact original
servers using FFmpeg `blackdetect` plus `signalstats`, with null output. Server
**34793** starts with a black interval **0.000–10.177 seconds**; server **34794**
starts with **0.000–10.093 seconds**. These ends are the first threshold-defined
nonblack media timestamps, not network-wait or first-decoded-frame wall times.
Both first analyzed frames were 100% black. The criterion classified a frame as
black when at least **98% of pixels** fell below a normalized **10% luma** threshold;
logged black intervals had a minimum duration of 0.1 seconds. Faint image content
below that criterion can precede the reported nonblack timestamp.

Each exact server received only one pass, capped at 20 seconds of output,
64 MiB upstream bytes and a 50-second process deadline. Both exited 0 with
480 output frames / 20.020 seconds, reading 15,608,798 and 15,608,543 upstream
bytes respectively. No movie frames or files were saved; inherited remote proxy
settings were preserved. The additional image-analysis filter wall times are
not playback-performance measurements.

This establishes about ten seconds of decoded black content in these two
encodes. It can contribute to apparent delay after decoding begins, but does not
measure the user's network wait or explain sustained phone lag. The optional
passes reused the original media URLs resolved earlier; they did not fetch fresh
Core metadata or exchange the gateway again. Current iOS CI's fresh Core request
for 17997 returned 403 before media, while its separate Wakanda metadata replay
observed first decoded video at 3.691 seconds; those outcomes remain separate.
No automatic intro skipping or app change was added for this finding.

Safe evidence: [black-intro.json](evidence/2026-11-02-source2-startup/black-intro.json).
