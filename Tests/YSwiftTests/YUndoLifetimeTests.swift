import Foundation
import Testing
@testable import YSwift

@Suite("Undo manager destruction")
struct YUndoLifetimeTests {
    @Test
    func releaseInsideTransaction() {
        let document = YDocument()
        let text = document.getOrCreateText(named: "text")
        var manager: YUndoManager<NSObject>? = document.undoManager(trackedRefs: [text])
        weak var releasedManager = manager

        document.transactSync { transaction in
            text.append("a", in: transaction)
            manager = nil
            #expect(releasedManager == nil)
            text.append("b", in: transaction)
        }
        document.transactSync { text.append("c", in: $0) }
        #expect(text.getString() == "abc")
    }

    @Test
    func releaseFromOwnObserver() async throws {
        let exercise: (Confirmation) throws -> sending Void = { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            var manager: YUndoManager<NSObject>? = document.undoManager(trackedRefs: [text])
            weak var releasedManager = manager
            var callbackCapture: NSObject? = NSObject()
            weak var releasedCapture = callbackCapture

            try manager?.observeAdded(key: "release") { [callbackCapture] _, metadata in
                received()
                manager = nil
                #expect(releasedManager == nil)
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
            let exercise: (Confirmation) throws -> sending Void = { received in
                let document = YDocument()
                let text = document.getOrCreateText(named: "text")
                var manager: YUndoManager<NSObject>? = document.undoManager(trackedRefs: [text])
                try manager?.observeAdded(key: "undo") { _, metadata in
                    undoEvent()
                    return metadata
                }
                document.transactSync { transaction in
                    #expect(text.observe(key: "release", transaction: transaction) { _ in
                        received()
                        manager = nil
                    })
                    text.append("a", in: transaction)
                }
                #expect(manager == nil)
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
