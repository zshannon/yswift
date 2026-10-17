# Vendored Yrs corrections

`yrs/` contains the upstream Yrs crate plus the focused local diff in
`yrs-undo-drop.patch`. Cargo selects it through `[patch.crates-io]` in `lib/Cargo.toml`.
The exact source revision, crate version, archive SHA-256, and unresolved conflicts
are recorded in [upstream-yrs.json](../../.github/upstream-yrs.json).
The upstream MIT license is copied into `yrs/LICENSE`; Cargo registry metadata is omitted.

The initial baseline was crates.io Yrs 0.28.0, commit
`23b7f5693bbf9e7d26340c521ee8647f79bdfba2`. The patch includes observer/undo
lifetime corrections, selective undo clearing, continued capture after one tracked
document is destroyed, and standalone ID decoder validation. Weekly updates download published stable crates, verify
their registry checksums, and rebase this diff using Git's three-way merge.
Unreleased commits are ignored. Conflicts are preserved in a draft PR, never
silently discarded. See [upstream maintenance](../../docs/upstream-maintenance.md).

Upstream UndoManager::drop acquires document transactions to unregister its observers.
That panics when another transaction is active. Ignoring the failure is unsafe because
the registered callbacks contain pointers into the freed undo state.

The patch gives native observers private weak references to their existing atomic
callback cells. Destruction moves the sole state Arc into a shared OnceLock before
clearing those cells, without acquiring a transaction or accessing the inner state.
Callbacks capture that owner, skip delivery after destruction starts, and retain the
state through an already-running invocation. The existing observer dispatch guard
retains the callback until its entire invocation returns, including native metadata
writes after the user's callback. Inactive callbacks release immediately. Weak
cancellation handles avoid retaining callbacks after document destruction.

The owner is empty during normal operation, preserving Arc::get_mut uniqueness.
The ownership transfer uses Option::take; no new unsafe code, threads, timers,
subscription wrappers, or public cancellation APIs are introduced.

The undo correction also honors the separate `clear_undo`/`clear_redo` flags and
retains the manager's tracked origin until its last document is destroyed. This
preserves the other history stack and keeps undo/redo capture working in remaining
documents.

The standalone IdSet/IdMap bindings expose native decoding to external bytes. Their
decoders reject client IDs outside 53 bits, overflowing client/clock deltas, invalid
attribute/name indexes, zero-length ranges, and unordered or overlapping ranges.
V2 delete-set clock/length accumulation uses checked addition. These checks return
the existing decoder error instead of allowing panics during decoding or later
encoding. The affected files are `src/id_set.rs`, `src/id_map.rs`, and
`src/updates/decoder.rs`.

Regression coverage is in `lib/src/undo.rs`, `lib/src/id_set.rs`, `lib/src/id_map.rs`, and
`Tests/YSwiftTests/YUndoLifetimeTests.swift`. Native concurrency tests coordinate with
barriers and inject a fixed clock. Swift event tests use Testing.confirmation.

Remove each correction when a released upstream version supplies equivalent behavior,
after rerunning the corresponding regressions against the new release. The existing
`yrs-undo-drop.patch` filename remains the updater's stable patch location.
