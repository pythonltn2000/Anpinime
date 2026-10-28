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
