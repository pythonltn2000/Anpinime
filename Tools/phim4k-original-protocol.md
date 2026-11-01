# Phim4K 2.8.4: original premium transport

This report supersedes the earlier missing-binary/unknown-signing findings for
this supplied package. Static protocol recovery, live media access and decoding
are separate results. No account session, membership change or original-app
execution was used.

## Preserved artifact and address convention

| Artifact | Identity |
| --- | --- |
| Supplied IPA | 26,503,200 bytes; SHA-256 `fd0ef22c4f12e39ed35e335c22eb8dbf6edeb7c1d8be466be690aae6d316aed5` |
| App identity | `ios.phim4k.xyz`, version 2.8.4, build 65 |
| `App.framework/App` | SHA-256 `070b6e44ffa8ca863ae60191179188db8cb3397ae3570c1757cd7a114da5af75` |

The original IPA remains unchanged. Its ZIP hash differs from the package named
in the older reports; no previous App-image hash was recorded, so byte identity
between packages is not asserted. This package independently confirms the code
locations below.

There is one arm64 FAT slice at App-file offset `0x4000`. The thin image has
`__TEXT` VM/file base 0, `__text` at `0x4000`–`0x762090`, and `__const` at
`0x764000`–`0xaf49f0`. Code addresses below are **thin-image-relative**: add
`0x4000` to locate the bytes in the FAT App file. `PP` values are Dart object-pool
indexes/offsets, not code addresses or file offsets.

Analysis used Capstone 5 and the iOS-capable lbr77/blutter fork with Dart 3.12.2,
without compressed pointers. Some generated function sizes were unavailable;
the relevant instructions were decoded independently with Capstone and checked
against the complete object-pool dump.

## Routing and exchange recovered statically

The original resolver starts at `0x6d3a28`. Its second argument is the model's
`is_free_source` flag, deserialized into the primary/fallback model fields
`0xff`/`0xd7`, default false. When true, it returns the original Free URL. Local
prefixes `http://127.0.0.1`, `http://localhost`, `file://`, and `content://` also
bypass signing (`PP 0x2ac28`, `0x2ac30`, `0xfd8`, `0x2ac38`).

For a non-Free remote source, it parses the original URL and takes the final
path component, then calls signer `0x6d3e08` at `0x6d3b68`. It does not substitute
the API server ID, remove a file extension, or use `stream_key` in this path.
The catalog's `video_file_id` identifies the selected server; the URL's opaque
file handle is a distinct identifier. Server IDs and versions must remain
independent even when labels or quality match.

The signer reads `Config.cdn` through `0x24fb00` (configuration field `0x27`),
removes a trailing slash, and appends the original file handle. The gateway host
comes from the authenticated public directory; it is not a fixed `.lol` host
replacement. The observed announcement was `svpc.cryboiz.workers.dev`, different
from the old helper's hardcoded gateway.

The resolver creates a fresh Dio client, performs a GET with a validate-status
callback, then checks HTTP 200 itself (`0x6d3c50`, SMI `0x190`). It extracts a
nonempty JSON `url` field (`PP 0xdbc0`). Failed status, missing/empty URL and
exceptions return null. Returning the signed gateway request itself as a video
fallback was behavior of the old Swift helper, not this original flow.

No account token or session is supplied to this fresh gateway request. This
observation describes the public client transport; it does not generalize to
other account-dependent app features. The separate live-TV `/link_play` flow
is not the movie-premium resolver and is not used here.

## Seed provenance and signing algorithm

The shipped client seed is `Hfb.VRh`, static field-table offset `0x2960`
(`PP 0x8428`). Its getter reads `_Ifb.VRh`, static `0x29e0` (`PP 0x8548`).
Initializer `0x5dcac` generates 32 character codes; closure `0x5dd58` XORs the
integer arrays at `PP 0x8558` and `0x8560` element by element. The result differs
from the old Swift helper's constant.

The recovered seed is not included in this report. Its fingerprint is:

`SHA-256 dae26b5d01bd01fde70f6d3f5f1a03f32a77da4cc9f38578f1ec92b33405db53`

The derivation path `0x6d4748` → `0x6d47d4` trims the client seed and rejects an
empty value. It obtains UTC `YYYYMMDD` from `0x5d6f4` and calls `0x68f804`:

```text
K = SHA256(UTF8(seed))
IV = SHA256(UTF8("iv:" + seed))[0:12]
P = UTF8(seed + ":" + YYYYMMDD_UTC)
C, T = AES-256-GCM.encrypt(K, IV, P, no additional data)
dailySecret = seed + ":" + lowercaseHex(C || T)
```

The nonce is 12 bytes and the authentication tag is 16 bytes. `iv:` is
`PP 0x8430`; the encryption helper is `0x68fa1c`.

Signer `0x6d3e08` derives integer Unix seconds and uses HMAC helper `0x6d40a8`:

```text
S = UTF8(dailySecret)
mask = HMAC-SHA256(S, UTF8("otp-ts-mask"))[0:4]
ts = lowercaseHex(uint32BigEndian(unixSeconds) XOR mask)
token = lowercaseHex(HMAC-SHA256(S, UTF8(fileHandle + ":" + unixSeconds)))
```

The four-byte encoding and XOR are explicit in `0x250d90`; the mask path starts
at `0x6d4544`. Query keys are `token`/`ts` (`PP 0x8f48`/`0x85a0`). The daily key
and seconds must use the same timestamp so a UTC date boundary cannot mix days.

The offline consistency vector uses **non-secret fixture input**, not the app
seed: seed `fixture-seed`, file handle `fixture-file-id`, Unix seconds
`1767355200` (2026-01-02 12:00 UTC). Expected token digest is
`3d0d01a2601096e202692e96b7c3323a728a039bb58b3d6944ee2d7b7ba45a31` and masked
`ts` is `7a8dcfb5`. This vector checks implementation consistency with the traced
algorithm; the live exchange below supplies independent interoperability evidence.

## HTTP behavior and credential scope

Gateway construction has no explicit account authorization or custom User-Agent
map. Dart's default HTTP User-Agent is generated at `0x63610` from `Dart/`, the
runtime major/minor version and ` (dart:io)` (`PP 0x8ca8`/`0x8cb0`), then applied
to requests at `0x75118`. In this package that is `Dart/3.12 (dart:io)`.
The separate source-2 media path explicitly sets `User-Agent: oxoo` at
`0x7247c4`–`0x724830` (`PP 0x3c568`/`0x3c570`). It is not a global catalog UA.

Core's movie-detail wrapper `0x6febcc` calls shared header builder `0x245914`
at `0x6fec24`, assigns its map to Dio, then GETs the runtime base plus
`/single_details?type=movie&id=` (`PP 0x2a528`). Home `0x729d54` and TV detail
`0x72b840` use the same builder. Base builder `0x245718` normalizes runtime API
field `0x3f`, `/rest-api/` and `v130` (`PP 0xb460`).

The header builder reads runtime `tokens` (configuration field `0x57`), mapped
to the `tokens` key at `0x599a8`–`0x599d0` / `PP 0x85f0`. Helper
`0x6cf834` accepts a map or JSON object string. API-key extraction `0x245aa0`
also accepts a plain trimmed string, or the aliases `api_key`, `apiKey`, `key`,
`token` (`PP 0x86c0`). Username aliases are `username`/`user` (`PP 0xb298`);
password aliases are `password`/`pass` (`PP 0xb2a8`). If those client fields are
absent, the original uses two shipped fallback strings (`PP 0xb2a0`/`0xb2b0`),
not a user's login. Their raw values are omitted here. The builder adds
`API-KEY` (`PP 0xb2b8`) and `authorization` (`PP 0x9b30`), where the latter is
`Basic ` plus Base64 of UTF-8 client username, colon and password. It adds no
Safari User-Agent. These are observed API-client settings, separate from the
CDN signing seed and user accounts. Matching this original UA/header behavior
does not prove that a particular Cloudflare HTML 403 will be resolved.

Neither Core header belongs on the gateway/media request. No account credentials
were recovered or used in the probes. Cross-origin redirects of Core/gateway
requests were blocked, and the Core client API header was never forwarded to media.

The HTTPS gateway can legitimately return **HTTP media**. The selected response
contained `url` and `expires_in` (21600 seconds), with an HTTP URL on
`sv.p4kzz.workers.dev`. No hostname or scheme rewrite was performed. The media
response declares `video/mp4` but its EBML prefix identifies MKV; MIME alone must
not reject or misidentify it.

## Bounded live prefix observations — October 31

One fresh authenticated public directory and one fresh Core detail for Wakanda
movie `10403` were followed by at most one gateway exchange and 2048 media bytes
per exact server, serially, with a 15-second timeout and no retries/guessed
signatures. All five selected identities were preserved:

| Server ID | Gateway | Media | Declared MIME | Total bytes | Actual prefix |
| --- | --- | --- | --- | ---: | --- |
| 31937 | 200 JSON | 206 | video/mp4 | 9,155,116,283 | MKV |
| 33090 | 200 JSON | 206 | video/mp4 | 12,811,020,482 | MKV |
| 27463 | 200 JSON | 206 | video/mp4 | 16,862,722,442 | MKV |
| 31938 | 200 JSON | 206 | video/mp4 | 17,447,699,322 | MKV |
| 31939 | 200 JSON | 206 | video/mp4 | 57,170,889,679 | MKV |

Gateway host: `svpc.cryboiz.workers.dev`; returned media host:
`sv.p4kzz.workers.dev`. Server `27463` worked despite its null `stream_key`,
confirming the observed file-handle path does not depend on that field.
No film was downloaded in full. These prefix observations establish access and
container format, not playback, video frames, audio or subtitles.

## Headless decoding — November 1

A fresh exact-server `31937` test subsequently decoded through FFmpeg 7.1.5:
**72 H.264 frames, 1920×1080, 3.003 seconds**, exit 0, no HTTP errors. It used
`oxoo` without an Origin header, saved no media bytes, limited output to 3 seconds,
probe size to 2,000,000 bytes, analysis to 3 seconds, network timeout to 10 seconds
and process duration to 35 seconds.

This is stronger than a prefix probe: real video frames decoded. It is still a
Linux headless test, not iOS/libmpv rendering or audio/subtitle verification.
The subsequent iOS checks separately exercised the production provider/resolver
with captured Core metadata for exact server 31937, a freshly authenticated
directory and live gateway/media. Full run `41259259589` decoded 1920×1080
H.264/AC-3 at 3.42 seconds. Follow-up `41260161453` reached **16.808 seconds**;
the downloaded screenshot visibly contains the film and Vietnamese subtitles.
The app source tree is identical across those runs. Two audio choices and three
subtitle choices (including off) were enumerated; VIP track switching and a
whole-film session were not verified. The later screenshot includes a buffering
indicator, so this is not evidence of sustained smooth playback.

This proves the live gateway-to-native-player path with **replayed Core metadata**.
The separate full Core live check still failed HTTP 403 before resolution; anime
live required browser verification and Free1 segments returned 404 HTML. No live
success JSON exists for those three checks. A green build or the separate local
MKV fixture cannot supply the missing full-live/physical-iPhone proof.

Sanitized permanent evidence is in [evidence/2026-11-01-original4k/](evidence/2026-11-01-original4k/):
artifact metadata, all-five prefix results, a fresh selected prefix and the
FFmpeg decoding result. The raw seed, full signed URLs and private gateway
responses remain outside the repository and outside this report.
