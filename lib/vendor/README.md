# Vendored Yrs and the destruction fix

`yrs/` contains the upstream Yrs crate plus the focused local diff in
`yrs-undo-drop.patch`. Cargo selects it through `[patch.crates-io]` in `lib/Cargo.toml`.
The exact source revision, crate version, archive SHA-256, and unresolved conflicts
are recorded in [upstream-yrs.json](../../.github/upstream-yrs.json).
The upstream MIT license is copied into `yrs/LICENSE`; Cargo registry metadata is omitted.

The initial baseline was crates.io Yrs 0.28.0, commit
`23b7f5693bbf9e7d26340c521ee8647f79bdfba2`, with only `src/observer.rs` and
`src/undo.rs` patched. Weekly updates download published stable crates, verify
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

Regression coverage is in `lib/src/undo.rs` and
`Tests/YSwiftTests/YUndoLifetimeTests.swift`. Native concurrency tests coordinate with
barriers and inject a fixed clock. Swift event tests use Testing.confirmation.

Remove this patch when a released upstream version supplies equivalent safe destruction,
after rerunning these regressions against the new release.
