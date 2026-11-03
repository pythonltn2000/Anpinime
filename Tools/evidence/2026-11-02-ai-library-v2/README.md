# Historical 2.6 library checks

These snapshots describe their recorded commits/runs; they do not certify the
current 2.7 app. In particular, `release-artifact.json` is explicitly superseded
and must not be used as a final delivery IPA.

The 2.6 sequence isolated a SwiftUI nested-lazy-grid layout hang, then verified
New-page continuation after replacing it with one grid. Its later pull-refresh
precondition still failed. Separate lifecycle/history and Movie search hit-region
cases passed. One live series reported 45 episodes in its catalog but only 41 in
its native panel; it was not accepted as a complete playlist.

The older `source-preservation.json` records the state before shared PiP/UI
changes. Current preservation evidence and native 2.7 results are in
`../2026-11-03-short-feed/` and `PHIM_AI_REPORT.md` at the repository root.
