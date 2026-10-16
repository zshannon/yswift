# YSwift

This library builds on top of [Yrs](https://github.com/y-crdt/y-crdt) to provide Swift language bindings that
seamlessly interoperate with other Yjs implementations.

**This repository is WIP (Work In Progress)**
Not all features and capabilities from Yrs or Yjs are exposed at this time.
We plan to add them as the library evolves.

The repository includes two swift packages:

`yniffiFFI` a static binary packaged as an XCFramework in the `lib` directory, built with the Rust compiler and overlaid using [UniFFI](https://github.com/mozilla/uniffi-rs/).
`YSwift` which is an overlay to provide more idiomatic Swift language operations.

## Building from source

This fork uses **Yrs 0.28.0** with a [focused destruction fix](lib/vendor/README.md),
with Rust **1.99.0** pinned in
`rust-toolchain.toml`. Install Xcode with Swift 6 and Rust through rustup, then run:

```bash
./scripts/build-xcframework.sh
swift build
swift test --enable-code-coverage
```

The build script installs the five required Rust targets and produces an XCFramework
for iOS devices, iOS simulators, and macOS. Unreleased source checkouts use that local
framework by default, so Swift bindings cannot silently link an older release's ABI.
Released manifests contain a matching binary URL and checksum; `YSWIFT_LOCAL=1`
overrides them for source development. Commit `Cargo.lock` and `Package.resolved`
when dependencies resolve.

The public library and tests compile in Swift 6 language mode. Generated UniFFI 0.27
bindings remain in Swift 5 mode because their generated global callback tables do
not yet satisfy Swift 6 checking.

## Migrating to Yrs 0.28

- Array `move` and `moveRange` were removed upstream and are removed here.
- Combine publishers and `YSubscription` are removed. Observation uses standard
  `AsyncStream`; no custom stream or subscription implementation is included.
- Await stream registration before making the first change. Cancelling the consuming
  task terminates its stream and schedules native observer removal on the document's
  transaction queue.
- Synchronous callbacks use caller-owned keys and an explicit document transaction.
  Registering a key again replaces its previous callback. Unregister after callback
  delivery, in another transaction.
- Client IDs must fit in 53 bits, as required by Yrs 0.28. Values above 32 bits are
  preserved. Tests cover legacy 0.25 update decoding and current replication.
- Undo callbacks also use keys. Registration and removal throw during an active
  transaction or undo callback. Undo managers can safely be released during those
  operations: the native patch cancels callbacks without acquiring a document
  transaction and preserves state until an already-running callback returns.

```swift
let document = YDocument()
let counts: YMap<Int> = document.getOrCreateMap(named: "counts")
let changes = await counts.observeAsync()
let consumer = Task {
    for await change in changes {
        print(change)
    }
}
await counts.set(1, forKey: "visits")
// When observation is no longer needed:
consumer.cancel()
await consumer.value
```

Use the async transaction APIs consistently for a document. The deprecated synchronous
convenience APIs use a separate queue and must not be mixed with async transactions.

Tests use Swift Testing, including `confirmation` for event receipt. Consumers finish
inside the confirmation scope; tests do not sleep, poll deadlines, or depend on elapsed
time. Undo grouping uses explicit `wrap()` boundaries.

## Releasing

To create a new release:

```bash
./scripts/release.sh <version>
```

This script:
1. Builds the xcframework for all platforms
2. Updates `Package.swift` with the new download URL and checksum
3. Commits, tags, and pushes to GitHub
4. Creates a GitHub release with the xcframework attached

Requires the `gh` CLI to be installed and authenticated.

## Decision log

This project maintains a [decision log](./devnotes/DevLog.md).
Please consult it in case there is some ambiguity in terms of why certain implementation details look as they are.

## License

This project is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Thanks to

Amazing people at Mozilla for their outsanding work on [UniFFI](https://github.com/mozilla/uniffi-rs/) and all of the supporting work they've done on using, packaging and distributing Rust code for Swift and Kotlin codebases.
