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
