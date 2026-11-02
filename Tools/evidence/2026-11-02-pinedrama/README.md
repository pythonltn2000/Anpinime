# PineDrama evidence — 2026-11-02

These are sanitized observations from the user-supplied PineDrama 46.6.0 IPA and bounded requests to its original API. The original app was not executed. No binary, raw API payload, signed cover/video URL, account session or cookie is included.

| File | What it establishes |
| --- | --- |
| [artifact-identity.json](artifact-identity.json) | Original IPA and executable size/SHA-256, bundle/version/build |
| [core-image-identity.json](core-image-identity.json) | DramaCore SHA-256, arm64 image layout, `cryptid=0` |
| [verified-request-contract.json](verified-request-contract.json) | Exact successful common parameters, synthetic test profile, native catalog/panel/selected-sequence requests and bounds |
| [catalog-summary.json](catalog-summary.json) | 12 real series returned; `has_more=true` and empty cursor do not prove a complete service catalog |
| [episode-panel-summary.json](episode-panel-summary.json) | Selected series’ 40 actual IDs, contiguous ordinals/sequences and observed access markers |
| [complete-series-resolution-summary.json](complete-series-resolution-summary.json) | Four response windows resolve all 40 matching identities with media addresses; includes counts/flags/hashes, no addresses |
| [sample-decode-checks.json](sample-decode-checks.json) | Episodes 1, 2, 40 each decode 90 HEVC frames, 540×960, 3 seconds, exit 0, null output |
| [manifest.json](manifest.json) | SHA-256 and size of the sanitized JSON files |

The selected series is **7676620083434656784**, “Thần Ẩm Thực Ở Ngục Tù Cổ Đại”. Catalog, episode-panel and video-resolution metadata are separate checks. The video endpoint returns protobuf and up to ten rows, so the selected episode must match paid-video ID, aweme ID, collection and sequence. A complete panel must not be replaced by that video window.

To reproduce the API checks, use the exact native request contract with fresh responses, preserve full decimal IDs, and follow [the decoder field map](../../pinedrama-analysis.md#protobuf-decoder-and-identity-checks). Use sequential bounded metadata reads (12-second timeout, at most 2 MiB each). The four-window metadata check uses sequence starts 1, 11, 21, 31. Stop on access/error/identity mismatch; do not substitute a different episode. Server responses and signed addresses can expire, so hashes identify the observed response rather than promise identical future bytes.

AnPinime’s implementation is [PineDramaProvider.swift](../../../AnyAnime/AIDrama/PineDramaProvider.swift). Its independent [provider tests](../../../Tests/AIDramaProviderTests.swift) cover exact Int64 IDs, complete playlists, contradictory identities, previews, token requirements, JSON/protobuf and isolated request handling. The [UI fixture harness](../../../Tests/ai-drama-smoke.sh) and [optional live UI harness](../../../Tests/ai-drama-live-smoke.sh) record iOS playback separately. This evidence directory does not itself assert that those UI runs passed.

Only episodes 1, 2 and 40 were sampled by the headless decoder. No full-series decode or physical-iPhone verification was performed. Empty purchase/encryption fields remain absent observations, not modified authorization. The all-40 resolution sweep did not download the whole series.
