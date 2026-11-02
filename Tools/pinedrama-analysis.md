# PineDrama 46.6.0: verified catalog, complete playlist and video transport

The supplied IPA establishes a usable native contract for the independent **Phim AI** tab. Bounded requests returned 12 real Vietnamese series, the selected series’ complete **40-entry episode panel**, and **40 matching video identities with server-issued media addresses**. FFmpeg decoded three-second samples from episodes **1, 2 and 40**. This is stronger than a successful build or an MP4 prefix check; it does not establish playback of every episode from beginning to end.

The original app was not installed, executed or modified. This analysis does not change source 1/3. Permanent, sanitized evidence is in [evidence/2026-11-02-pinedrama](evidence/2026-11-02-pinedrama/README.md). iOS UI and physical-device playback results must be recorded separately from these API and headless decoder results.

## Artifact and address convention

| Artifact | Preserved identity |
| --- | --- |
| Original IPA | 370,630,215 bytes; SHA-256 `54b4775cf67cd6a5799d877ae8cd40eba4121848feb891cf4a41a224c19ada44` |
| Bundle | `com.ss.iphone.ttmd.video`, version 46.6.0, build 466003 |
| Main executable `Drama` | 90,960 bytes; SHA-256 `202299f8b3d887e7fd8f367911a5718dc8fe140440d1a918d1df2488978ca0d0` |
| `DramaCore.framework/DramaCore` | 627,688,272 bytes; SHA-256 `f48e895f646d6537828bdf650b7d1b653921741f6a2d62977de12369f069375d` |

`DramaCore` is a thin arm64 Mach-O with slice offset 0 and `__TEXT` VM base 0. `LC_ENCRYPTION_INFO_64` declares `cryptoff=32768`, `cryptsize=517668864`, **`cryptid=0`**: the supplied image is statically readable. Code/metadata addresses below are image-relative virtual addresses; in the cited segments they equal file offsets. They are not runtime addresses. Encoded chained-rebase pointers were resolved before use. No FairPlay decryption was performed.

## Working request flow

All three requests use HTTPS on **`api-va.tiktokv.com`**, the exact `API_HOST` in the original `Info.plist`. The same plist supplies app ID **845221**, name **`tiktok_drama`**, bundle **`com.ss.iphone.ttmd.video`** and channel **`App Store`**. The successful public common parameters and synthetic test-device profile are preserved in [verified-request-contract.json](evidence/2026-11-02-pinedrama/verified-request-contract.json). Production AnPinime derives the OS/device/timezone values from its runtime.

No install ID, device ID, client DID, account session, copied cookie, purchase-state change or guessed signature was used. Initial requests with only `aid` / `app_name` returned an empty success envelope. Adding the original version/build, bundle/channel and platform/language fields returned the actual catalog. An HTTP 200 or `status_code=0` alone is therefore not sufficient.

### 1. Native discover catalog

```text
GET /tiktok/md/mini_drama_center/v1/
scene=1
category_id=
cursor=
count=12
is_mixed_column_page=0
```

The response was HTTP 200 JSON, **18,161 bytes**, `status_code=0`, with **12 real Vietnamese series** under top-level `collections`. Native response mapping `0x8070ce8` maps `collections`, `safe_collections`, `has_more`, `cursor` directly, with no `data` wrapper. Preserve the decimal `collection_id_str` / Int64 identity without conversion through floating point.

Native builders `0x8077238` / `0x807771c` and preload `0x808d174` establish the request fields. Wrapper `0x114587e0` invokes `AWENetworkService.getWithURLString:params:modelClass:completion:`, proving GET. Overview model map `0x806f334` supplies `collection_id`, `title`, `cover`, `num_videos`, `full_video_ids`, `video_list`, and limited-free/trailer information. The overview’s summary rows are not playable aweme objects.

The observed response had **`has_more=true` but an empty cursor**. AnPinime must not fabricate a next cursor or label these 12 rows the complete service catalog. The full-playlist requirement below is verified for the selected series, independently of catalog pagination.

### 2. Complete selected-series episode panel

```text
GET /tiktok/md/collection/episode_panel/v1/
collection_id=7676620083434656784
```

Selected series: **“Thần Ẩm Thực Ở Ngục Tù Cổ Đại”**, catalog `num_videos=40`. The panel returned HTTP 200 JSON, **4,241 bytes**, `status_code=0`, with **40 unique actual episode IDs and numbers/sequences 1–40**. All entries had `is_intro=false` and `is_limited_free=true`; `is_paid` / `has_purchased` were absent. Missing purchase fields are not invented purchase authorization.

The native request `0x71a3990` uses app-difference endpoint type 8 and a numeric `collection_id`. Panel map `0x71a5678` supplies top-level `episode_list`, `short_cut_num`, `creator_uid`, `free_banner_text`; episode map `0x71a4edc` supplies `num`, `video_id`, `is_paid`, `has_purchased`, `is_limited_free`, `is_intro`, `seq_id`. The returned **`short_cut_num=24` is not the total episode count** and must not truncate the playlist.

AnPinime accepts a complete panel only when unique IDs, unique contiguous numbers, sequences and the declared total agree. It keeps every returned episode, rather than deriving a playlist from the current feed page or synthesizing ordinal-based IDs.

### 3. Resolve the selected episode using the native forward-paging contract

```text
GET /tiktok/md/collection/video/v1/
collection_id=7676620083434656784
query_type=seq_id
current_seq_id=<selected actual episode number>
count=10
direction=1
root_scene=2
query_scene=mini_drama_container
enter_from=series_discover
drama_request_type=load_more
need_collection_detail=0
is_trailer_paginated=0
iap_country_code=
request_source=
```

This exact request returns **`application/x-protobuf`**, not JSON. The request is still GET. Successful sequence checks included **1, 2 and 40**; four windows starting at **1, 11, 21 and 31** returned **10 rows each**, covering all 40 panel identities. The final window had `hasNext=false`.

Every row’s paid-video ID, aweme ID, paid-content video ID, collection ID and episode number agreed with the actual panel entry. Every row contained three media addresses, was marked limited-free, had no partial-preview / show-preview flag and required no media token. The encrypted marker was absent; no encrypted marker or purchase state was overwritten. [complete-series-resolution-summary.json](evidence/2026-11-02-pinedrama/complete-series-resolution-summary.json) preserves all 40 identities, flag observations and response hashes without media URLs.

Resolve the chosen identity explicitly. Never use the first returned row as a fallback, because the API returns a window of up to ten episodes. The app requests fresh signed addresses when an episode is selected and does not persist them in watch history or a playlist cache.

## Why the earlier video requests failed

The first probes used the shared paid-content defaults rather than the actual Discover/forward path. They returned HTTP 200 with a **25-byte protobuf error, code 3016030, `Invalid parameters`**, or a JSON message **`url doesn’t match`** without videos. Those responses were failed resolves.

The corrected contract is supported by the native caller chain:

- Discover selection `0x807616c` invokes `0x808c8e0` / table slot `0x24073650` → builder `0x8089040`, which explicitly constructs **`root_scene=2`** at `0x8089298`–`0x80892b4` and **`enter_from=series_discover`** at `0x8089160`–`0x8089180`. The older default of 1 does not describe this entry route.
- Newer collection builder `0x73b4984` chooses app-difference endpoint type 6 and the new MD protobuf serializer. Forward caller `0x73b07b4` takes the last sequence plus 1 at `0x73b0928`, then supplies **`seq_id`, direction 1, count 10, `load_more`** at `0x73b0974`–`0x73b098c`, and **`need_collection_detail=false`** at `0x73b0990`. Reverse paging instead uses `load_latest` and direction 0.
- Request-type implementation `0x73af338` / jump table `0x19435855` maps `init_fetch`, `load_more`, `load_latest`, `refresh`, `urlless`, `play_next`. The key built at `0x73b4ee4` is **`request_source`**, not `source`.
- `DramaPagingParams` initializer `0x73af5fc` defaults to GET; a separate runtime feature can enable POST. The working bounded request uses the native GET branch. Protobuf serialization does not imply a POST body.
- The IAP provider accessor in this image resolves `0x3e4c0` → `0x7c08e4c` → `0xf888890` → `0x105d6f7c`, an immediate nil return. Newer builder `0x73b4bac`–`0x73b4bc0` converts an absent optional country into an empty string. An alpha-2 `VN` or guessed alpha-3 `VNM` is not justified for this route; the verified request sends the empty value.

The newer request fields must be considered together. This investigation does not claim that changing only `root_scene` repairs every invalid request.

## Protobuf decoder and identity checks

The MD response descriptor `0x552275c` / table `0x237ec110` establishes:

| Field | Meaning |
| --- | --- |
| 1 | statusCode (int32; omitted zero is success) |
| 2 | repeated PaidVideoV2 |
| 3 | VideoPageInfoV2 |
| 5 / 6 | hasPurchased / numVideos |
| 8 / 9 | hasIntro / hasPreview |
| 14 / 15 | collection / isLimitedFree |
| 19 / 26 / 27 | bizMsg / statusMsg / bizCode |

Playback and cross-check fields:

```text
response.field2[] PaidVideoV2
  field1 = paidVideoId (int64)
  field12 = seqId (int64)
  field4 = AwemeStructV2
    field1 = awemeId (string)
    field317 = PaidContentInfo
      field1 = paidCollectionId
      field3 = episodeNum
      field6 = paidVideoId
      field7 / field8 = isPartialPreview / shouldShowPreview
      field17 = isPaidVideoEncrypted
    field7 = VideoStructV2
      field1 = playAddr (UrlStructV2)
        field2[] = URLListArray (string)
      field18 = H264 alternate address
      field3 / field4 / field13 = height / width / duration
      field24 / field26 = needSetToken / tokenAuth
```

`VideoPageInfoV2` fields are 1 `hasBefore`, 2 `hasNext`, 3 `currPage`. PaidVideo descriptor `0x5521234` uses table `0x237e8f88` with 40-byte entries including an eight-byte default prefix. Aweme descriptor `0x11ab1858` uses table `0x237d11d8` with the same format; Video `0x11ab221c` / table `0x237cc0a0` and URL `0x11ab197c` / table `0x237d96c0` use 32-byte entries. A decoder cannot assume every generated descriptor has the same stride.

With `need_collection_detail=0`, response **field 14 may be absent**. The row’s actual `AwemeStructV2.field317` carries its collection identity. Response-wide **`hasPreview=true` also occurs on these successful responses**; it must not be confused with the selected row’s `isPartialPreview` / `shouldShowPreview`. The latter per-video markers are checked before offering a full episode.

## Decode evidence and limits

| Episode | Actual ID | Observed headless decode |
| --- | --- | --- |
| 1 | `7676620734394862865` | HEVC, 540×960, 90 frames, 3.000 s, exit 0 |
| 2 | `7676620627842731265` | HEVC, 540×960, 90 frames, 3.000 s, exit 0 |
| 40 | `7676620695161310481` | HEVC, 540×960, 90 frames, 3.000 s, exit 0 |

FFmpeg decoded to a null sink; no media file was saved. API metadata advertised 1080×1920 for the first sample, while the actually decoded representation was **540×960**. Only the decoded resolution is a decoder result. Episode 1 was first resolved through the native mini-drama JSON request described below; the later forward window independently returned the same exact ID.

The four-window sweep inspected metadata and URL availability. It did **not** download or decode all 40 episodes, establish continuous whole-series playback, confirm every series in the catalog, or verify playback on a physical iPhone. Network availability and time-limited-free state may change; a fresh response and exact identity check remain necessary.

## Other original routes: useful distinctions

`/tiktok/md/mini_drama/video/v1/` is native **POST JSON** with `collection_ids` and `root_scene`. Native callers `0x72f9788` / `0x734ca30` and wrapper `0x72fa39c` prove the method/body. Its response maps `video_list[i].collection_id`, `video.paid_video_id`, `video.seq_id`, `video.aweme.aweme_id`, and `video.aweme.video.play_addr.url_list`. A bounded request returned the matching first episode and an HTTP 206 MP4 prefix. It requests collections, so its first/resume row cannot replace an arbitrary selected episode.

The binary also retains `/tiktok/v1/paid_content/mini_drama/video_by_ids` and generic `/aweme/v1/aweme/detail/` branches. Static presence alone does not establish live suitability for PineDrama. Neither branch is used by the implemented resolver. The verified native Discover/forward path above supplies the exact episode and complete-series evidence without depending on those alternatives.

## Application boundary

Phim AI uses independent models, provider, cache and watch-progress keys. It consumes the complete episode panel, resolves only the selected stable identity, cancels stale resolution work and uses one active portrait playback owner. Neighboring pages do not resolve or play their videos until selected. The product UI keeps vertical episode swipes, playback controls and the full-series episode selector; hearts, comments and sharing controls are omitted.

These implementation choices are separate from verification status. Source 1/3 and existing source-2 live failures are not declared repaired by the PineDrama results. The feature’s UI-test artifacts, regression checks and remaining device limitations belong in the feature delivery report.

Raw IPA/framework files, Capstone listings, service payloads and signed URL files remain in private scratch. The checked-in evidence uses whitelisted identity/count/flag/hash fields only.
