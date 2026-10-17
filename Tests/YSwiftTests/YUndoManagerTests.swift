import Foundation
import Testing
import Synchronization
@testable import YSwift

final class TestMetadata: Sendable {
    public let value: String
    init(_ value: String) {
        self.value = value
    }
}

@YSwiftActor
func exchangeUpdates(_ document1: YDocument, _ document2: YDocument) {
    let clock1 = document1.transactSync { txn in
        txn.transactionStateVector()
    }
    let clock2 = document2.transactSync { txn in
        txn.transactionStateVector()
    }
    let update1 = document1.transactSync { txn in
        document1.diff(txn: txn, from: clock2)
    }
    let update2 = document2.transactSync { txn in
        document2.diff(txn: txn, from: clock1)
    }
    document1.transactSync { txn in
        try! txn.transactionApplyUpdate(update: update2)
    }
    document2.transactSync { txn in
        try! txn.transactionApplyUpdate(update: update1)
    }
}

@YSwiftActor
@Suite
final class YUndoManagerTests {
    var document: YDocument!
    var text: YText!
    var manager: YUndoManager!

    init() throws {
        document = YDocument()
        text = document.getOrCreateText(named: "test")
        manager = try document.undoManager(trackedRefs: [text], timestamp: { 1 })
    }

    @Test
    func test_undoTextBasic() throws {
        text.insert("1221", at: 0)
        try manager.wrap()
        text.insert("3", at: 2)
        try manager.wrap()
        text.insert("3", at: 3)
        try manager.wrap()

        #expect((text.getString()) == ("123321"))

        #expect(try manager.undo())
        #expect((text.getString()) == ("12321"))

        #expect(try manager.undo())
        #expect((text.getString()) == ("1221"))

        text.insert("3", at: 2)
        #expect((text.getString()) == ("12321"))
    }

    @Test
    func test_undoEvents() async throws {
        let exercise: @YSwiftActor (Confirmation) throws -> sending Void = { [self] eventReceived in
            let received = Mutex(Data())

            try manager.observeAdded(key: "added", { (e, metadata) -> Data? in
                    eventReceived()
                let m = metadata ?? Data()
                return m + Data("A".utf8)
            })

            try manager.observePopped(key: "popped", { (e, metadata) -> Data? in
                    eventReceived()
                received.withLock { $0 = metadata! }
                return metadata
            })

            text.insert("abc", at: 0)

            #expect(try manager.undo())
            #expect((received.withLock { String(decoding: $0, as: UTF8.self) }) == ("A"))

            #expect(try manager.redo())
            #expect((received.withLock { String(decoding: $0, as: UTF8.self) }) == ("A"))

            try manager.unobserveAdded(key: "added")
            try manager.unobservePopped(key: "popped")
        }
        try await confirmation("Receives each change", expectedCount: 5, exercise)
    }

    @Test
    func test_undoDifferentOrigins() throws {
        let localOrigin = Origin("local")

        let remoteDocument = YDocument()
        let remoteText = remoteDocument.getOrCreateText(named: "test")
        try manager.addOrigin(localOrigin) // only track transaction from local origin

        // create some changes locally
        document.transactSync(origin: localOrigin) { txn in
            self.text.insert("hello", at: 0, in: txn)
        }
        try self.manager.wrap() // add changes on a stack: they will be undone as one

        exchangeUpdates(document, remoteDocument)

        // concurrent change on the remote replica
        document.transactSync(origin: localOrigin) { txn in
            self.text.insert(" world", at: 5, in: txn)
        }
        try self.manager.wrap() // add next batch of changes on a stack
        remoteText.insert("<break>", at: 1)

        #expect((text.getString()) == ("hello world"))

        exchangeUpdates(document, remoteDocument)

        #expect((text.getString()) == ("h<break>ello world"))
        #expect((remoteText.getString()) == ("h<break>ello world"))

        #expect(try manager.undo())

        // only changes marked locally have been reversed
        #expect((text.getString()) == ("h<break>ello"))

        #expect(try manager.undo())
        #expect((text.getString()) == ("<break>"))

        #expect(!(try manager.undo())) // remote changes are not reverted
        #expect((text.getString()) == ("<break>"))
    }
}
