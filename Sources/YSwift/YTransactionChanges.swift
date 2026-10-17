import Foundation
import Yniffi

/// Owned transaction changes that remain usable after the transaction closes.
public struct YTransactionChanges: Sendable {
    public let afterState: [UInt8]
    public let beforeState: [UInt8]
    public let deletions: YIdSet
    public let documentGuid: String
    public let insertions: YIdSet
    public let origin: Origin?

    public var hasChanges: Bool { !insertions.isEmpty || !deletions.isEmpty }

    init(_ changes: YrsTransactionChanges) {
        afterState = changes.afterState
        beforeState = changes.beforeState
        deletions = YIdSet(native: changes.deletions)
        documentGuid = changes.documentGuid
        insertions = YIdSet(native: changes.insertions)
        origin = changes.origin.map(Origin.init)
    }
}

extension YrsTransaction {
    /// Inserted CRDT identifier ranges accumulated by this transaction.
    public var insertions: YIdSet { YIdSet(native: insertSet()) }

    /// Deleted CRDT identifier ranges accumulated by this transaction.
    public var deletions: YIdSet { YIdSet(native: deleteSet()) }

    public var changeSnapshot: YTransactionChanges { YTransactionChanges(changes()) }
}

extension YDocument {
    /// Runs synchronously after the transaction body and before collection observers.
    /// This includes empty transactions. The snapshot is safe to retain.
    public func observeBeforeObserverCalls(
        key: String,
        transaction: YrsTransaction,
        _ body: @escaping @Sendable (YTransactionChanges) -> Void
    ) {
        transaction.observeBeforeObserverCalls(key: key, delegate: YBeforeObserverDelegate(callback: body))
    }

    @discardableResult
    public func unobserveBeforeObserverCalls(key: String, transaction: YrsTransaction) -> Bool {
        transaction.unobserveBeforeObserverCalls(key: key)
    }

    /// Emits changed transactions captured before collection observers run.
    /// Empty transactions (including registration and cleanup) are omitted.
    public func observeBeforeObserverCallsAsync() async -> AsyncStream<YTransactionChanges> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<YTransactionChanges>.makeStream()
        transact { transaction in
            self.observeBeforeObserverCalls(key: key, transaction: transaction) { changes in
                if changes.hasChanges { continuation.yield(changes) }
            }
        }
        continuation.onTermination = { _ in
            Task {
                await self.transact { transaction in
                    self.unobserveBeforeObserverCalls(key: key, transaction: transaction)
                }
            }
        }
        return stream
    }
}

private final class YBeforeObserverDelegate: YrsBeforeObserverDelegate {
    private let callback: @Sendable (YTransactionChanges) -> Void

    init(callback: @escaping @Sendable (YTransactionChanges) -> Void) { self.callback = callback }
    func call(changes: YrsTransactionChanges) { callback(YTransactionChanges(changes)) }
}
