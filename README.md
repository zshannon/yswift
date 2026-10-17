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

This fork uses **Yrs 0.28.0** with [targeted lifetime, history, and decoding fixes](lib/vendor/README.md),
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

The library, generated UniFFI bridge, and tests all compile in Swift 6 language mode.
Minimum deployment targets are iOS 18 and macOS 15. The bridge preparation step
uses the standard-library `Mutex` for callback handles and explicit `sending`
ownership for native subdocument events; it adds no unchecked Sendable conformances.

## Migrating to 0.7

- `YDocument`, collections, synchronization, and undo operations share
  `YSwiftActor`. A transaction executes synchronously on that actor and cannot
  suspend. Outside the actor, await document access; inside a transaction, use
  the supplied transaction for every collection operation.
- Array/map values require `Codable & Sendable`. Rich-text attributes use
  `SwifterJSON.JSON`, and events are owned `Sendable` values. Live CRDT collections
  no longer conform to synchronous standard-library collection protocols; iterate
  `toArrayAsync()` / `toMapAsync()` snapshots instead.
- Combine publishers, `YSubscription`, array `move`, and `moveRange` are removed.
  Observation uses standard `AsyncStream`. Await registration before the first
  mutation. Consumer cancellation schedules native observer removal on the actor.
- Keyed callbacks are `@Sendable` and receive owned event data. They cannot
  synchronously reenter actor-isolated mutation. Use a `Task` and `await` for
  subsequent document work. Registering the same key replaces its observer.
- `YUndoManager` spans collections from multiple documents, supports selective
  undo/redo clearing, exposes state snapshots and stack-cleared events, and retains
  document identity on undo events. Metadata is owned `Data?`, replacing retained
  object pointers; encode custom metadata explicitly when needed.
- Undo grouping accepts an injected timestamp closure. Use `wrap()` for an explicit
  capture boundary. Managers can safely be released during transactions or callbacks.
- `YIdSet` and `YIdMap<Value>` expose released Yrs range algebra and V1/V2 encoding.
  They own Swift values, retain no native handles, and can cross tasks safely.
  Operations that decode or validate data throw.
- Transactions expose insertion/deletion sets and owned change snapshots.
  `observeBeforeObserverCalls` runs synchronously in the native commit phase;
  its async stream provides snapshots for later consumption.
- `cleanupFormatting` defaults to true and can be disabled in document options.
  Root documents support `destroyAsync()`; subdocuments use their parent transaction.
- Client IDs must fit in 53 bits. Tests cover legacy Yrs 0.25 updates and current
  replication using released Yrs 0.28.0.

```swift
let document = YDocument()
let counts: YMap<Int> = await document.getOrCreateMap(named: "counts")
let changes = await counts.observeAsync()
let consumer = Task {
    for await change in changes {
        print(change)
    }
}
await counts.set(1, forKey: "visits")
consumer.cancel()
await consumer.value
```

Swift Testing event tests use `confirmation` and await receipt inside its scope.
Tests do not sleep, poll deadlines, or depend on elapsed time; capture-group tests
advance an injected timestamp directly.

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
