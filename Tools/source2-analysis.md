# Source 2 interoperability notes — 2026-10-23

Reference IPA: Phim4K 2.8.4 iOS. SHA-256:
`5dceeaf338222cd8c9dacb5f15426382a7d11ebbcb0d04a28fb1b8b9d6158ea0`.
Original preserved; no installation or execution of the IPA was needed.

Static analysis of the arm64 Flutter App.framework image used the experimental
iOS-capable lbr77/blutter fork with Dart 3.12.2 and Capstone. Mach-O slice offset
is 0x4000; the following are Dart object-pool offsets, not file offsets.

Pairs of integer arrays decode by element-wise XOR. Pool entries 0xb418/0xb420
decode an obsolete REST base; 0xb4a0/0xb4a8 decode the live directory endpoint
`https://rip.cryboiz.workers.dev/api/add`. Pool entries 0x8578/0x8580 supply
client configuration decoding material. The response is AES-GCM-256, base64url
nonce and ciphertext with a 16-byte trailing authentication tag; the key is
SHA-256 of the decoded client string. Successful authenticated decryption, not
just printable strings, confirmed the configuration format.

The directory points `free1` at `free.cryboiz.workers.dev`; this API returns actual
movie lists, search results, artwork, separate dubbed/subtitled server groups and
episode links. Current episode rows use `link`, with extensionless
`/api/content/stream/hls` URLs. Old `.lol` addresses alone are not sufficient.
The app now refreshes this directory and retains the last valid public addresses.
No advertising URLs, account tokens, Supabase data or remote plugin code are consumed.

Bounded network checks: first page, one search, four movie details, and selected
manifest/segment GETs; no account requests or catalog-wide downloads. The first
episode of `thuong-nguyen-do` returned HLS and a transport-stream segment with the
app's User-Agent. Two newly added movies returned HTTP 500 from the stream server.
The REST backend and Free2 were unavailable in these checks; Free1 is the working
integration path, not a replacement with an unrelated service.

The reference app uses media_kit/mpv, whereas this app uses AVPlayer and WebKit.
Embedded HLS audio/subtitle choices are enumerated natively; separate server
versions remain separate episodes. Burned-in subtitles cannot be disabled.
Full MKV/ASS support and account-only backend parity have not been implemented.

CI's live source-2 smoke test explicitly selects the documented sample, then
requires playback time > 1 second and landscape dimensions before writing
`playback-phim4k-live.json`. A successful build without that artifact is not proof
of live playback. Website failures remain visible and never trigger substitution
of another movie or another content provider.

## Recovery audit — 2026-10-27

The last refactor removed Core calls and only retained Free1. This lost the app's
original high-bitrate server list. Restoring the old cross-site aggregation would
also be wrong: that code could label a Free1 fallback as a Core 4K/MKV server.

The current authenticated directory points Core to `api.phim4k.space`. Bounded
GETs with the directory's client API header confirmed `home_content_for_android`,
`movies`, `tvseries`, `search`, `content_by_genre_id`, `content_by_country_id` and
`single_details` under `/rest-api/v130/`. List endpoints return a top-level array;
home supplies `all_genre`/`all_country` and separate movie/TV lists. Details expose
`video_file_id` for film servers and `seasons_id`/`episodes_id` for series.

`Phim4KCatalog` and `Phim4KProvider` now consume this Core catalog directly alongside
labelled Free1/Free2 catalogs. They keep original media URLs and refresh by stable
IDs. There is no title-guess matching or cross-provider replacement. Runtime Free1
currently shares KKPhim's catalog, but its playback links use the app's stream API.
This explains overlapping Free1/KKPhim results without treating them as Core.

Sample Core details returned all original 1080p/2160p/Remux entries, including MKV.
The referenced `cdn.phim4k.lol` links and the directory's Free2 host failed DNS in
this environment. The announced CDN host rejected the bounded request; no guessed
rewrite has been installed. Restoring catalog entries is not proof of live Core
playback, and AVPlayer still does not implement mpv's full MKV/ASS capabilities.
The user has been asked for a currently working original-app VIP sample.

## Wakanda and VIP transport follow-up — 2026-10-27

The user supplied Black Panther: Wakanda Forever as an original-app sample.
Core `single_details?type=movie&id=10403` returned five `videos` entries, preserved
in `Tests/Fixtures/phim4k-wakanda.json`: file IDs 31937, 33090, 27463, 31938,
31939. Three are 1080p; two are 2160p including UHD Remux. All report MKV.
Four entries also expose `stream_key`; ID 27463 does not. No positional or
quality-based deduplication is applied.

Further static inspection explains why replacing the `.lol` host alone is
insufficient. In the arm64 image, code at image-relative 0x6d3a28 parses the
original URL's last path component, calls the signing path at 0x6d3e08 and then
reads a `url` from the CDN response JSON. That path constructs a time-dependent
request on the configured CDN with `token` and `ts` query parameters. These are
image-relative addresses (fat-slice file offset +0x4000), not object-pool offsets.
This behavior has not been integrated or validated against live VIP playback;
no signing secret or account credentials are added to this repository.

Catalog/menu changes are independent of this unresolved transport. Tests cover
all five Wakanda IDs and preserve each original server without relabelling a
Free1 stream as VIP. The original IPA remains unchanged.

## Player upgrade — 2026-10-28

The supplied IPA uses media_kit/libmpv. Direct streams now use MPVKit's LGPL
product, pinned to d9194243bdc68b87d8989376ab52aee7da6c8e0b, with Matroska,
embedded audio/subtitles, external SRT/ASS/SSA/VTT, and primary/secondary subtitle
selection. The original five Wakanda entries remain independent. A required iOS
simulator check generates its own MKV with two audio and two subtitle tracks,
requires playback without pressing Play, and switches real libmpv track IDs.
This checks decoder integration; it does not prove expired CDN URLs are usable.
The original-app time-dependent CDN resolver above is still a separate concern.

NguonC's public StreamC embed currently configures JW Player advertising and
`autostart:false`. It can also use a custom sealed playlist loader. The app removes
only the advertising setup and enables autoplay, preserving access verification,
license and custom loader. Sealed playback stays in WebKit. Its audio/captions
are read from the actual JW track lists. Dual subtitles and local subtitle files
are available on direct libmpv playback; the web player exposes its primary lane.
Regression tests cover preroll on the same video element, configured movie
handoff before video creation, sealed-loader preservation and JW track selection.
Film4k.net's public client uses a server HLS proxy and a media envelope decoder;
its server implementation was not available for inspection.

The new intro is the user's original MP4, copied without transcoding. Anime
schedule uses the source's actual /lich-chieu-phim.html page, including its day
selectors, rather than an invented timetable. Duplicate HTML loads share one
request and cached episode pages can be reused by the player.

## Free catalog/configuration repair — 2026-10-29

The app's manual Free URL previously replaced the entire source-2 configuration
with `core:nil` and one catalog. This made Core and the other Free catalog vanish
when the user saved any manual URL. `applyingCatalogOverride` now replaces only
the selected Free ID. Clearing it restores the app directory configuration;
AnimeVietsub hosts are rejected in this setting. Partial bootstrap updates merge
with known configuration so omitted Free2 values do not erase the last address.

Bounded public checks on 2026-10-29 (read-only, two details and one media sample):
`free.cryboiz.workers.dev/danh-sach/phim-moi-cap-nhat-v3` returned 200.
`/phim/thuong-nguyen-do` returned 100 Vietsub episodes, and `/phim/xom-nho`
returned six. Each selected row used its original `link` at
`sf.phim4k.space/api/content/stream/hls`; query values and media URLs are not
included here. The Thương Nguyên Đồ sample returned a 28,277-byte HLS playlist;
its first media request returned 200, `video/mp2t`, and an MPEG-TS sync byte 0x47.
Prefix requests with `oxoo`, `exoplayer`, and the existing Safari user agent all
returned HLS; this does not establish a need to change the Free user agent.
These are network/media-format observations, not proof of iPhone playback.

The stored Free2 hostname failed DNS in this environment. The Core detail sample
returned HTTP 403 with HTML/Cloudflare using both stored and default public client
configuration; this does not prove an account authorization failure. No origin
credentials, signing material or fake token were recovered or installed.

Existing static evidence identifies `/link_play` at image-relative 0x72ab30 as a
separate flow built on the fixed `khanggtivi.xyz/api/` live-TV service with a
`play_urls` model. It is not evidence of the Core movie VIP resolver and has not
been grafted onto it. The previously documented VIP resolver at 0x6d3a28 remains
unverified without a legitimate active URL/session. Full original-app parity and
live VIP video/audio/subtitle playback therefore remain unproven.

REA 6.8.0 archive inventory was run using the existing Node 22.21.1 binary
(Node 20's zlib lacked the required zstd export). Evidence ID
`ev_bbe18dcb4952bd6b65047d4096c62c51bd40ce67abd55696ff5b8bd0f4825aa3`
confirms the supplied IPA SHA-256 above via `rea-artifact-graph`. This inventory
is static package evidence only; it does not establish runtime VIP behavior.


## HLS relay and live evidence — 2026-10-30

Continued from `8acf5c0`; see `REPAIR_REPORT_V4.md` for scope and evidence.
The relay changed TS segment paths to `.bin`, rejected by FFmpeg's HLS extension
checks. Source 2 now preserves known media suffixes under opaque loopback IDs;
the default relay behavior for sources 1/3 is unchanged. The required simulator
fixture traverses the real source-2 provider, extensionless HLS endpoint, relay
and pinned libmpv. Run `41001476273` (`410aafb`) produced decoded 640x360 video,
advancing to 3.44 seconds, and a visible test-pattern screenshot. MKV autoplay,
two audio tracks and two subtitle lanes also passed again.

Free1 live did **not** pass. Both the macOS network probe and actual simulator
player received HTTP 404 HTML for the documented sample's TS segments; the
manifest itself returned 200. The player stayed unloaded with time and video
dimensions at zero. No live success JSON was produced. A bounded Linux check
of Xom Nho also obtained a 200 manifest followed by a 404 segment; it was not
used to replace the selected movie.

Core Wakanda still returned all five original server IDs. The exact 31937
simulator check failed during resolution because the original CDN hostname
could not be found. No VIP success JSON was produced; the existing unused
signing helper has not been enabled or changed. Anime `.news` currently serves
a custom browser-check title missed by the old parser; that recognition is
repaired, while live anime playback remains unverified behind the challenge.

Playback artifact `12953593501` contains screenshots and redacted diagnostics;
small permanent JSON evidence is in `Tools/evidence/2026-10-30/`. The workflow's
live steps use continue-on-error: a green build still does not establish Free1
or VIP playback. There are no signed URLs, cookies or account sessions in the
new evidence files.


## Follow-up on earlier anime builds and premium configuration — 2026-10-30

`REPAIR_REPORT_V5.md` traces two episode-list regressions to the older code and
records a complete simulator anime pipeline with late JS-added episodes and
cancellation/cache checks. Final code `7b600ca`, run `41143287070`, passes that
fixture with two episodes and decoded 320x180 video at 3.958 seconds. Live .news
still requires browser verification in the runner; it has no live success JSON.

`Tools/premium-transport-review.md` records new source-2 evidence: the authenticated
public directory announces `svpc.cryboiz.workers.dev`, while the old unused
helper hardcodes another gateway. The directory reader now retains this CDN
metadata, without rewriting media URLs or enabling the unverified signer. The
original IPA/disassembly is unavailable in this workspace; earlier signing
claims and fixed success logs are not a substitute for that trace. Wakanda
stream keys and file handles are distinct, stable fields, not literal aliases.
Safe metadata and playback evidence live in `Tools/evidence/2026-10-30-followup/`.


## Supplied original IPA and verified gateway protocol — 2026-11-01

The user subsequently supplied the original Phim4K 2.8.4 (65) IPA again. Its
SHA-256 is `fd0ef22c4f12e39ed35e335c22eb8dbf6edeb7c1d8be466be690aae6d316aed5`;
this differs from the older package hash and is preserved independently.
[phim4k-original-protocol.md](phim4k-original-protocol.md) supersedes the
missing-binary and unknown-signing limitations above for this package, with
exact image hashes, address conventions and independently decoded instructions.

The Core resolver takes the URL's final file handle, derives its daily secret
from the actual shipped XOR arrays and exchanges a token/ts request at the
directory-announced CDN. The old Swift seed and fixed gateway were incorrect.
HTTP 200 JSON must contain a media `url`; failure does not return the gateway
request itself for playback. Free sources bypass this signer. The original
native media header is `User-Agent: oxoo`, separate from the Dart catalog client.
The HTTPS gateway legitimately returns HTTP media, preserved without host or
scheme rewriting. Core/gateway credentials do not belong on that media request.

All five original Wakanda servers returned 200 gateway JSON then 206 MKV prefixes
in bounded 2-KB checks. A fresh November 1 check of exact server 31937 also decoded
72 H.264 frames at 1920x1080 over 3.003 seconds in FFmpeg, with no media saved.
These observations establish the protocol and real decoding; the Linux result
does not substitute for the separately recorded iOS simulator/live checks.
See [../REPAIR_REPORT_V6.md](../REPAIR_REPORT_V6.md) for the final app verification
and remaining anime/Free1 limitations. Sanitized evidence is in
[evidence/2026-11-01-original4k/](evidence/2026-11-01-original4k/).

The iOS gateway check subsequently decoded/rendered the exact 31937 movie at
1920x1080 through 16.808 seconds, with a visible film frame and Vietnamese
subtitles inspected in artifact `13064543658`, run `41260161453`. Only Core
metadata was replayed; directory, signing, gateway, media and native player were
real. Full Core live still returned 403 before resolution, anime required browser
verification, and Free1 segments returned 404. This is not a claim that those
three live entry points or sustained whole-film playback are repaired.
