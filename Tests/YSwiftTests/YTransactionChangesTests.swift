import Foundation
import Testing
import Synchronization
@testable import YSwift

@YSwiftActor
@Suite
struct YTransactionChangesTests {
    @Test
    func insertionAndDeletionSnapshotsOutliveTheirTransactions() async throws {
        let document = YDocument(options: .init(clientId: (1 << 32) + 17))
        let text = document.getOrCreateText(named: "text")
        let inserted = await document.transact { transaction in
            text.append("abc", in: transaction)
            return transaction.changeSnapshot
        }
        let deleted = await document.transact { transaction in
            text.removeRange(start: 1, length: 1, in: transaction)
            return transaction.changeSnapshot
        }
        #expect(inserted.documentGuid == document.guid)
        #expect(inserted.insertions.ranges == [YIdRange(clientId: document.clientId, clock: 0, length: 3)])
        #expect(inserted.deletions.isEmpty)
        #expect(deleted.insertions.isEmpty)
        #expect(deleted.deletions.ranges == [YIdRange(clientId: document.clientId, clock: 1, length: 1)])
        #expect(inserted.beforeState != inserted.afterState)
        #expect(deleted.beforeState == deleted.afterState)
    }

    @Test
    func beforeObserverStreamCarriesOwnedChanges() async throws {
        try await confirmation("Receives a changed transaction") { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            var changes = await document.observeBeforeObserverCallsAsync().makeAsyncIterator()
            await text.append("hello")
            let snapshot = try #require(await changes.next())
            received()
            #expect(snapshot.documentGuid == document.guid)
            #expect(snapshot.insertions.ranges.map(\.length) == [5])
            #expect(snapshot.deletions.isEmpty)
            #expect(snapshot.hasChanges)
        }
    }

    @Test
    func rootDestructionFinishesItsStream() async throws {
        try await confirmation("Receives root destruction once") { received in
            let document = YDocument()
            var destruction = await document.observeDestroyAsync().makeAsyncIterator()
            try await document.destroyAsync()
            #expect(await destruction.next() != nil)
            received()
            #expect(await destruction.next() == nil)
        }
    }

    @Test
    func snapshotsDoNotCacheStateBeforeLaterEdits() {
        let document = YDocument(options: .init(clientId: 7))
        let text = document.getOrCreateText(named: "text")
        let (early, late) = document.transact { transaction in
            text.append("a", in: transaction)
            let early = transaction.changeSnapshot
            text.append("b", in: transaction)
            return (early, transaction.changeSnapshot)
        }
        #expect(early.insertions.ranges.map(\.length) == [1])
        #expect(late.insertions.ranges.map(\.length) == [2])
        #expect(early.afterState != late.afterState)
        #expect(late.afterState == document.transact { $0.transactionStateVector() })
    }

    @Test
    func beforeObserverHookPreservesCommitOrder() async {
        await confirmation("Both transaction phases run", expectedCount: 2) { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            let phases = Mutex<[String]>([])
            document.transact { transaction in
                document.observeBeforeObserverCalls(key: "before", transaction: transaction) { change in
                    if change.hasChanges {
                        phases.withLock { $0.append("before") }
                        received()
                    }
                }
                text.observe(key: "text", transaction: transaction) { _ in
                    phases.withLock { $0.append("text") }
                    received()
                }
                text.append("a", in: transaction)
            }
            #expect(phases.withLock { $0 } == ["before", "text"])
        }
    }

    @Test
    func formattingCleanupRemovesRedundantConcurrentAttributes() throws {
        let initial = YDocument(options: .init(clientId: 1))
        let text = initial.getOrCreateText(named: "text")
        let seed = initial.transact { transaction in
            text.append("abc", in: transaction)
            return transaction.transactionEncodeStateAsUpdate()
        }
        let updates = try [UInt64(2), 3].map { clientId in
            let author = YDocument(options: .init(clientId: clientId))
            let text = author.getOrCreateText(named: "text")
            try author.transact { try $0.transactionApplyUpdate(update: seed) }
            return author.transact { transaction in
                text.format(at: 0, length: 3, attributes: ["bold": true], in: transaction)
                return transaction.transactionEncodeStateAsUpdate()
            }
        }
        let states = try [true, false].map { cleanup in
            let target = YDocument(options: .init(cleanupFormatting: cleanup, clientId: 4))
            let text = target.getOrCreateText(named: "text")
            for update in updates {
                try target.transact { try $0.transactionApplyUpdate(update: update) }
            }
            #expect(text.getString() == "abc")
            #expect(text.diff() == [.text(value: "abc", attributes: ["bold": true])])
            return target.transact { $0.transactionEncodeStateAsUpdate() }
        }
        #expect(states[0] != states[1])
    }
}
