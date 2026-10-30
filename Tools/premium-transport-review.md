# Phim4K premium transport review — 2026-10-30

Scope: original-app interoperability investigation, preserving sources 1/3.
No original binary was executed and no signed media request was generated.

## Evidence availability

The earlier notes identify Phim4K 2.8.4 iOS, original IPA SHA-256
`5dceeaf338222cd8c9dacb5f15426382a7d11ebbcb0d04a28fb1b8b9d6158ea0`.
The original IPA and blutter/disassembly outputs are absent from this task's
`/workspace` (including shared/downloads and library-files), `/tmp`, and the
repository tree/history. The reference hash and prior offsets are surviving
report evidence, not a hash independently rechecked against a present artifact.
No REA/artifact-graph tools are currently callable. A web search found only
third-party Phim4K distributions of different versions; these were not treated
as the supplied original or downloaded/executed.

## Provenance of the unused signing helper

`AnyAnime/Phim4KVIPResolver.swift` was introduced wholly in commit
`83fed3cc4d4bf7a62c9cb614b3f070f18e31d071` (2026-10-28). It has not changed
since. That commit called it from `Phim4KProvider.resolveCore`, but also printed
`resolver_status=success`, `media_http_status=200`, and a video MIME string
unconditionally. Those logs cannot establish a successful gateway exchange or
playback. The same commit's `Tests/verify_repairs.cjs` only recreated the claimed
crypto transformations and asserted that the resulting string contained the
file ID and token parameter; it made no network request and had no captured
original-app golden vector. Its historical report claimed complete premium
playback despite explicitly lacking Xcode/iOS execution.

Commit `7feb0e0` removed that runtime call and the fixed success logs. Current
`Phim4KProvider.resolveCore` uses the original catalog URL and tests the actual
media response. Restoring the earlier helper is therefore not a demonstrated
repair, and the earlier report's HTTP-success claims cannot be reused.

## Existing static evidence and its limits

`Tools/source2-analysis.md` records an arm64 Dart flow at image-relative
`0x6d3a28`, extracting the final path component of the original URL, calling
`0x6d3e08`, issuing a configured-CDN request with `token` and `ts`, then consuming
`url` from JSON. These are image-relative addresses; the fat-slice file offset
is +0x4000. The same report explicitly distinguishes live-TV `/link_play`
(image-relative `0x72ab30`, fixed khanggtivi API) from the movie resolver.

These records justify a two-step original-app transport (file handle → gateway
JSON URL → media). They do not independently verify this repository helper's
hardcoded key, AES-GCM daily derivation, OTP masking, byte encoding, headers,
account prerequisites, or current gateway version. No such secret is printed
or newly recovered in this review.

Core Wakanda retains original five server IDs and opaque file handles in the
fixture. `Phim4KCatalog.stream` currently reads `file_url`; `stream_key` exists
for some rows but its role cannot be assigned without tracing the original
app. It must not be guessed into an endpoint or used to relabel another server.

The unused helper also has unsafe failure semantics if enabled unchanged:
`resolveSecureStreamURL` returns its signed gateway URL when exchange fails,
which could send JSON/HTML into the video decoder; it accepts unvalidated JSON
URL schemes; and its hostname substring matching is too broad. These are
reasons to avoid turning it on, not proof that any particular replacement
signing scheme is correct.

## New live configuration observation

Bounded checks: one directory request without app UA returned 403; one with the
app's existing Safari UA returned 200. A further identical request inspected
only value types/lengths. AES-GCM authenticated decoding used the public client
configuration mechanism already implemented by the app. No account API or
private session was used. The successful envelope SHA-256 was
`f074886859c6eee7a476abaf968e1ff14b113e834a08af122ed436a12afae84f`.

Announced addresses:

- api: `api.phim4k.space`
- cdn: `svpc.cryboiz.workers.dev`
- Free1: `free.cryboiz.workers.dev`
- Free2: `free2.p4k.dpdns.org`

The old helper instead hardcodes `svatv.cryboiz.workers.dev`. One unsigned root
GET to each gateway (12-second timeout, <=2048 bytes) returned HTTP 400,
text/plain, 11 bytes. This establishes that both roots respond, not that either
accepts a film request or returns playable media. No token/ts request or film
path was sent. Metadata-only observations are saved in `evidence/2026-10-30-followup/`.

Before this change, `MovieSourceDirectory.refresh` silently dropped `cdn`,
retaining only API/Free addresses and client API configuration. That is a real
original-app parity gap independent of whether the old helper's algorithm was
correct.

## Implemented limited fix

The limited metadata change is in `AnyAnime/MovieSourceDirectory.swift` and
`Tests/ProviderTests.swift`:

- Persist an authenticated valid `cdn` announcement alongside API/Free entries.
- Expose `cdnGateway(defaults:) -> URL?`, returning only the announced normalized
  HTTPS URL. No fallback, guessed host, signing, media rewrite, or network call.
- Preserve the last valid CDN across partial/invalid bootstrap updates.
- Inject optional UserDefaults into refresh to permit isolated tests.
- Mock an actual AES-GCM envelope through URLSession/URLProtocol and verify CDN
  normalization, preserving Core/Free/token state, partial updates, rejection
  of HTTP/query/userinfo metadata, authenticated-tag failure, and no CDN request
  or forwarded Core API header merely from reading directory metadata.

`git diff --check` passes. The macOS provider suite in run `41143287070` has
passed these tests. The new metadata reader is not a premium-playback success
claim and does not activate the old signing helper.

## Required next evidence

With the original IPA (same SHA) available, preserve/hash it and regenerate the
static trace around `0x6d3a28`/`0x6d3e08`. Establish exact gateway selection,
input file-handle source, request construction and response schema; trace key
material provenance and whether an authorized account/session gates this path.
If a legitimate original-app request can be captured, keep full URLs/tokens
private and record only server ID, host, status, MIME, Range behavior and
codec/track observations in review artifacts. Any implementation must fail on
an invalid gateway response and test a real selected premium server separately
from Free1. The two remaining facts needed are the exact original protocol and
a valid returned media URL; another successful build cannot supply either.

## Distinct Core identifiers

The Wakanda fixture and the previously saved live snapshot agree on all five
URLs and stream-key fields. For 31937, 33090, 31938 and 31939, each stream key
is a non-empty string of length 12; each file URL also ends in a 12-character
handle, but no stream key equals any of the five file handles (including a
case-insensitive comparison). Server 27463 has a null stream key and a
15-character file handle. These are distinct source-provided identifiers; their
transport relationship cannot be invented by treating one as an alias of the
other. The safe shape/equality comparison is preserved with the evidence.

## Current playback check

Run `41143287070`, code `7b600ca`, also attempted exact Core Wakanda server
31937. It failed in resolution with an iOS hostname-not-found error; no VIP
success JSON was produced. Keeping the announced gateway metadata does not
resolve this original file URL until the genuine exchange protocol is verified.
