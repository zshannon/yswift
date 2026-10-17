import Testing
import Synchronization
@testable import YSwift

@YSwiftActor
@Suite
struct YUpstreamUndoTests {
    @Test
    func tracksCollectionsFromAnotherDocument() async throws {
        let first = YDocument()
        let second = YDocument()
        let text = second.getOrCreateText(named: "text")
        let manager: YUndoManager = try await first.undoManagerAsync(trackedRefs: [], timestamp: { 1 })
        try await manager.trackAsync(text)
        await text.append("second")
        #expect(try await manager.undoAsync())
        #expect(await text.getString() == "")
        #expect(try await manager.redoAsync())
        #expect(await text.getString() == "second")
    }

    @Test
    func interleavedHistoryUsesEachCollectionsDocument() async throws {
        let first = YDocument()
        let second = YDocument()
        let a = first.getOrCreateText(named: "text")
        let b = second.getOrCreateText(named: "text")
        let manager: YUndoManager = try await first.undoManagerAsync(trackedRefs: [a, b], timestamp: { 1 })
        await a.append("a")
        await b.append("b")
        await a.append("c")
        #expect(try await manager.stateAsync().undoCount == 3)
        #expect(try await manager.undoAsync())
        #expect(await a.getString() == "a")
        #expect(await b.getString() == "b")
        #expect(try await manager.undoAsync())
        #expect(await b.getString() == "")
        #expect(try await manager.undoAsync())
        #expect(await a.getString() == "")
        #expect(try await !manager.undoAsync())
        for _ in 0..<3 { #expect(try await manager.redoAsync()) }
        #expect(await a.getString() == "ac")
        #expect(await b.getString() == "b")
    }

    @Test
    func concurrentDocumentTasksShareSafeUndoHistory() async throws {
        let documents = (0..<4).map { _ in YDocument() }
        let texts = documents.map { $0.getOrCreateText(named: "text") }
        let manager: YUndoManager = try await documents[0].undoManagerAsync(trackedRefs: texts, timestamp: { 1 })
        await withTaskGroup(of: Void.self) { group in
            for text in texts {
                group.addTask {
                    for _ in 0..<4 { await text.append("a") }
                }
            }
        }
        let count = try await manager.stateAsync().undoCount
        #expect(count >= 4 && count <= 16)
        for _ in 0..<count { #expect(try await manager.undoAsync()) }
        for text in texts { #expect(await text.getString() == "") }
        for _ in 0..<count { #expect(try await manager.redoAsync()) }
        for text in texts { #expect(await text.getString() == "aaaa") }
    }

    @Test(arguments: [true, false])
    func selectiveClearPreservesTheOtherStack(clearUndo: Bool) async throws {
        try await confirmation("Receives the selective clear") { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            let manager: YUndoManager = try await document.undoManagerAsync(trackedRefs: [text], timestamp: { 1 })
            var events = try await manager.observeClearedAsync().makeAsyncIterator()
            await text.append("a")
            try await manager.wrapAsync()
            await text.append("b")
            #expect(try await manager.undoAsync())
            if clearUndo { try await manager.clearUndoAsync() } else { try await manager.clearRedoAsync() }
            let event = try #require(await events.next())
            received()
            #expect(event.undoCleared == clearUndo)
            #expect(event.redoCleared == !clearUndo)
            let state = try await manager.stateAsync()
            #expect(state.canUndo == !clearUndo)
            #expect(state.canRedo == clearUndo)
            if clearUndo {
                #expect(try await manager.redoAsync())
                #expect(await text.getString() == "ab")
            } else {
                #expect(try await manager.undoAsync())
                #expect(await text.getString() == "")
            }
        }
    }

    @Test
    func destroyedDocumentDoesNotDisableRemainingHistory() async throws {
        let first = YDocument()
        let second = YDocument()
        let a = first.getOrCreateText(named: "text")
        let b = second.getOrCreateText(named: "text")
        let manager: YUndoManager = try await first.undoManagerAsync(trackedRefs: [a, b], timestamp: { 1 })
        await a.append("a")
        await b.append("b")
        try await second.destroyAsync()
        #expect(try await manager.stateAsync().documentGuids == [first.guid])
        #expect(try await manager.undoAsync())
        #expect(await a.getString() == "")
        #expect(try await manager.redoAsync())
        #expect(await a.getString() == "a")
        try await manager.wrapAsync()
        await a.append("c")
        #expect(try await manager.undoAsync())
        #expect(await a.getString() == "a")
    }

    @Test
    func undoStreamsOwnTheirEvents() async throws {
        try await confirmation("Receives added, updated and popped snapshots", expectedCount: 3) { received in
            let document = YDocument()
            let text = document.getOrCreateText(named: "text")
            let manager: YUndoManager = try await document.undoManagerAsync(trackedRefs: [text], timestamp: { 1 })
            var added = try await manager.observeAddedAsync().makeAsyncIterator()
            var updated = try await manager.observeUpdatedAsync().makeAsyncIterator()
            var popped = try await manager.observePoppedAsync().makeAsyncIterator()
            await text.append("a")
            let addition = try #require(await added.next())
            received()
            await text.append("b")
            let update = try #require(await updated.next())
            received()
            #expect(try await manager.undoAsync())
            let pop = try #require(await popped.next())
            received()
            // All originating native callbacks and transactions have ended.
            for event in [addition, update, pop] {
                #expect(event.documentGuid == document.guid)
                #expect(event.hasChanged(text))
                #expect(event.type == .undo)
            }
            #expect(addition.origin == nil)
            #expect(pop.origin != nil)
        }
    }

    @Test
    func duplicateReplicaGuidsAreRejected() async throws {
        let first = YDocument(options: .init(guid: "shared-guid"))
        let second = YDocument(options: .init(guid: "shared-guid"))
        let a = first.getOrCreateText(named: "text")
        let b = second.getOrCreateText(named: "text")
        let manager: YUndoManager = try await first.undoManagerAsync(trackedRefs: [a], timestamp: { 1 })
        await #expect(throws: (any Error).self) { try await manager.trackAsync(b) }
        await a.append("a")
        #expect(try await manager.undoAsync())
        #expect(await a.getString() == "")
    }
    @Test
    func captureGroupingUsesOnlyTheInjectedTimestamp() throws {
        let document = YDocument()
        let text = document.getOrCreateText(named: "text")
        let timestamp = Mutex<UInt64>(1)
        let manager = try document.undoManager(trackedRefs: [text], timestamp: { timestamp.withLock { $0 } })
        document.transact { text.append("a", in: $0) }
        timestamp.withLock { $0 = 500 }
        document.transact { text.append("b", in: $0) }
        #expect(try manager.state().undoCount == 1)
        timestamp.withLock { $0 = 1000 }
        document.transact { text.append("c", in: $0) }
        #expect(try manager.state().undoCount == 2)
        #expect(try manager.undo())
        #expect(text.getString() == "ab")
        #expect(try manager.undo())
        #expect(text.getString() == "")
    }

}
