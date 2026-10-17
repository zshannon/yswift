import Foundation
import Testing
import Synchronization
@testable import YSwift

@YSwiftActor
@Suite("Undo manager destruction")
struct YUndoLifetimeTests {
    @Test
    func releaseInsideTransaction() throws {
        let document = YDocument()
        let text = document.getOrCreateText(named: "text")
        let manager = Mutex<YUndoManager?>(try document.undoManager(trackedRefs: [text], timestamp: { 1 }))
        weak var releasedManager = manager.withLock { $0 }

        document.transactSync { transaction in
            text.append("a", in: transaction)
            manager.withLock { $0 = nil }
            #expect(releasedManager == nil)
            text.append("b", in: transaction)
        }
        document.transactSync { text.append("c", in: $0) }
        #expect(text.getString() == "abc")
    }

    @Test
    func releaseFromOwnObserver() async throws {
        let exercise: @YSwiftActor (Confirmation) throws -> sending Void = { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            let manager = Mutex<YUndoManager?>(try document.undoManager(trackedRefs: [text], timestamp: { 1 }))
            weak var releasedManager = manager.withLock { $0 }
            var callbackCapture: TestMetadata? = TestMetadata("capture")
            weak var releasedCapture = callbackCapture

            try manager.withLock { $0 }?.observeAdded(key: "release") { [callbackCapture] _, metadata in
                received()
                manager.withLock { $0 = nil }
                #expect(callbackCapture != nil)
                return metadata
            }
            callbackCapture = nil
            #expect(releasedCapture != nil)

            document.transactSync { text.append("a", in: $0) }
            #expect(releasedManager == nil)
            #expect(releasedCapture == nil)
            document.transactSync { text.append("b", in: $0) }
            #expect(text.getString() == "ab")
        }
        try await confirmation("Receives only the event that releases the manager", exercise)
    }

    @Test
    func releaseFromCollectionObserver() async throws {
        try await confirmation("Released manager receives no undo event", expectedCount: 0) { undoEvent in
            let exercise: @YSwiftActor (Confirmation) throws -> sending Void = { received in
                let document = YDocument()
                let text = document.getOrCreateText(named: "text")
                let manager = Mutex<YUndoManager?>(try document.undoManager(trackedRefs: [text], timestamp: { 1 }))
                try manager.withLock { $0 }?.observeAdded(key: "undo") { _, metadata in
                    undoEvent()
                    return metadata
                }
                document.transactSync { transaction in
                    #expect(text.observe(key: "release", transaction: transaction) { _ in
                        received()
                        manager.withLock { $0 = nil }
                    })
                    text.append("a", in: transaction)
                }
                #expect(manager.withLock { $0 == nil })
                document.transactSync { transaction in
                    #expect(text.unobserve(key: "release", transaction: transaction))
                    text.append("b", in: transaction)
                }
                #expect(text.getString() == "ab")
            }
            try await confirmation("Collection callback releases the manager", exercise)
        }
    }
}
