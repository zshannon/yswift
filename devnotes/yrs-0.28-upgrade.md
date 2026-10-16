# Yrs 0.28 upgrade

Updated `/Volumes/Shockey/Code/yswift` on `codex/yrs-0.28-upgrade` from the patched
Yrs 0.25 fork to upstream 0.28.0 with a focused native destruction patch.
Prepared for release 0.6.0 from the verified source and matching XCFramework.

- [x] Clone the fork and verify upstream API changes.
- [x] Adapt 53-bit client IDs, keyed observers, and undo-manager APIs.
- [x] Remove array moves, subscription wrappers, Combine publishers, and obsolete completion-based transactions.
- [x] Use standard AsyncStream with registration completed before returning; retain the existing Matt Massicotte AsyncQueue for transactions.
- [x] Compile the public library and test target in Swift 6 mode. Generated UniFFI 0.27 remains in Swift 5 mode.
- [x] Migrate every XCTest case to Swift Testing; use confirmations for event receipt, with consumers awaited within each scope.
- [x] Cover legacy 0.25 updates, high client IDs, integer values, malformed UTF-8, out-of-order updates, keyed replacement/removal, cancelled consumers, deleted nested collections, subdocument lifecycle, and undo callback reentry.
- [x] Regenerate bindings and rebuild all five Rust targets into the local XCFramework.
- [x] Replace the example's Combine UI state with Apple Observation and check Swift 6 iOS compilation.
- [x] Fix native undo-manager destruction during transactions and callbacks; review the ownership fix and deterministic regressions.
- [x] Review final changes and document build/release preparation.

## Verification, 2026-10-16

- `cargo test --manifest-path lib/Cargo.toml --lib --locked`: 9 passed.
- `swift build`: passed.
- `swift test --enable-code-coverage`: 145 tests across 10 suites passed in 4 ms total;
  maximum individual reported duration 3 ms, none at or above 100 ms.
- Tests contain no sleeps, polling deadlines, or wall-clock assertions. Undo grouping
  uses explicit boundaries. Event assertions use Swift Testing confirmation.
- `xcodebuild -scheme YSwift -destination 'generic/platform=iOS' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build`: passed.
- Todo list source type-checks with Swift 6 for arm64 iOS 17 against the local framework.
  Full Tuist project generation and interactive sample execution were not run; Tuist
  is not installed. Its local dependency path uses the verified Tuist 3.39 API.
- `bash -n` passes for build/release scripts. Release URL/checksum substitution was
  tested on a temporary manifest; no publishing script was executed.
- `git diff --check`: passed.

XCFramework targets: aarch64 iOS device; aarch64/x86_64 iOS simulator;
aarch64/x86_64 macOS. Archive: `lib/yniffiFFI.xcframework.zip`.
SHA-256: `968195a90558a5ad7638ea6545c99aa5c16a23a05272a45e1beb0ba462c5f434`.
Rust 1.99.0 and lockfiles are retained for reproducible source builds. The release manifest pins the matching 0.6.0 archive and checksum.
Set `YSWIFT_LOCAL=1` to use a locally rebuilt framework during development.

## Review conclusions and limits

Native observation uses Yrs keys directly. Collection hooks resolve against a live
transaction before unobserving deleted nested collections. Undo observer-table
changes reject reentry while a document transaction or undo callback is active.
Uniterated AsyncStream teardown was verified to release the document.

The new example finds mutation indices inside the document transaction, avoiding
stale indices from its observable UI snapshot. DocC examples await stream registration.

The original Yrs 0.28 destructor aborted when released during an active transaction;
`releaseInsideTransaction` reproduced signal 6 before the fix. The local Cargo patch
in `lib/vendor/yrs` changes only observer-cell ownership and undo destruction. It
cancels native callbacks without acquiring a document transaction and retains Inner
through an in-flight callback's final metadata write. No new unsafe code, cleanup
threads, timers, public subscription API, or Swift stream infrastructure is added.
The exact source delta and upstream provenance are recorded in `lib/vendor/README.md`
and `lib/vendor/yrs-undo-drop.patch`.

Three Swift Testing lifetime cases pass (2 ms each), including release in a transaction,
from a collection observer, and from the manager's own observer. Four native regressions
also cover barrier-controlled concurrent destruction and document destruction before
manager destruction. Fixed clock closures and weak probes verify both callback captures
and the native state survive while needed and are released after delivery. All five
native framework targets were rebuilt with the fix, and the iOS build passed again.
