# Native short feed and player presentation — 2026-11-03

The original PineDrama IPA remains unchanged (SHA-256
`54b4775cf67cd6a5799d877ae8cd40eba4121848feb891cf4a41a224c19ada44`).
The original Phim4K IPA also remains unchanged (SHA-256
`5dceeaf338222cd8c9dacb5f15426382a7d11ebbcb0d04a28fb1b8b9d6158ea0`).
Neither original application was executed.

## Native contract

PineDrama DramaCore arm64 image-relative offsets:

- Request route selector `0x2bea640` includes `/tiktok/md/mini_drama/feed/v1/`.
- `TTKFeedShortDramaDataController.bizParams`, `0x10ef6a58`, sets
  `need_load_skylight`, millisecond `first_enter_tab_time`, `drama_request_type`,
  actual `drama_current_items` and `item_count_in_session`.
- Request protobuf descriptor `0x5522948`, table `0x237ec780`: count field 1,
  request type field 7, actual item IDs field 9. The native response descriptor
  `0x11ab17b0` maps status field 1, has-more field 3 and awemes field 4.
- Aweme field 317 is paid-content metadata: collection ID 1, episode number 3,
  collection title 13, categories 26, cover 27, mini-drama JSON 31. The latter
  supplies `video_total_nums`. Video dimensions come from Aweme field 7.

Bounded public observations used two feed GETs and one selected-video/panel pair,
12-second request timeouts and a 2 MiB response cap. No account/session/cookie was
used. Page one returned three video recommendations, including landscape video;
continuation returned twelve rows with nine new video IDs. Selected episode 1
matched the exact collection/video/sequence identity in the independent video
response and the contiguous 89-entry episode panel.

`native-feed-observations.json` contains only safe IDs/counts/hashes. Raw bodies,
expiring media URLs and the original binaries remain outside the repository.
These API observations are not a claim of iOS playback.

## Settings and PiP

The original Phim4K Dart image settings builder at image-relative `0x251dec`
uses object-pool `0x3b698` for six groups: audio, subtitles, display, speed,
general and information. Its selected/unselected tab builder is `0x261274`.
AnPinime now presents these groups as a compact horizontal strip with a
scrolling options area; actual audio/subtitle choices remain native player IDs.

PiP uses AVSampleBufferDisplayLayer and the existing mpv decoder/audio session.
Only PiP switches to a small software render surface; ordinary playback keeps
its prior Metal output/default options. The render API runs on its own queue.
On restore the GPU output must take ownership **before** freeing the libmpv
render context: freeing a context still in use requests asynchronous video
teardown in mpv. The first native attempt failed this transition and was not
accepted as a successful playback result.

The native test requires visible software frames, pause, seek, continued time
and restored GPU playback. Actual automatic system PiP on a physical iPhone
must be reported separately from this test.

`source-preservation.json` compares shared parsing, movie transports, relays and
the normal mpv option map against the repair baseline. UI and PiP presentation
changes are explicitly within the current request.
