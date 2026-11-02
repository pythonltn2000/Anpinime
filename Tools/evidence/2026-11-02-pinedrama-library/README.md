# PineDrama independent library: native catalog evidence

These observations were made on 2026-11-02 using the original app's public
catalog contract. The IPA and its JavaScript were inspected statically and
never executed.

- [Native library contract](native-library-contract.json): shipped asset hashes,
  source byte offsets, native screen scenes, category schema and home continuation.
- [Catalog paging observations](catalog-paging-summary.json): whitelisted response
  hashes, counts, exact collection IDs, server cursors and `has_more` values.

Hot ranking, latest ranking, new works and categories each returned a second
page with 12 additional identities. Native home recommendation state returned
14 rows containing 3 additional identities after the first 14; repetitions
require exact-ID deduplication. These are bounded two-page observations and
do not prove an unlimited catalog or iPhone playback.

Requests were sequential, with 12-second timeouts and 2-MiB response caps. No
account sessions, install registration, cookies, signatures, purchase changes
or media downloads were used. No raw service reply, media URL, signed URL or
account data is included here. The verified selected-episode resolver is
unchanged.
