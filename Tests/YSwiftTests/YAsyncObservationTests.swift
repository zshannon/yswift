import Testing
import Synchronization
@testable import YSwift

@YSwiftActor
@Suite("Async observation without timed waits")
struct YAsyncObservationTests {
    @Test
    func receivesEveryChangeAfterRegistration() async throws {
        try await confirmation("Receives both registered changes", expectedCount: 2) { received in
            let document = YDocument()
            let map: YMap<Int> = document.getOrCreateMap(named: "map")
            var events = await map.observeAsync().makeAsyncIterator()
            await map.set(1, forKey: "a")
            await map.set(2, forKey: "b")
            let first = try #require(await events.next())
            received()
            #expect(first == [.inserted(key: "a", value: 1)])
            let second = try #require(await events.next())
            received()
            #expect(second == [.inserted(key: "b", value: 2)])
        }
    }

    @Test
    func consumerCanReadStateAfterDelivery() async throws {
        try await confirmation("Consumer receives the change") { received in
            let document = YDocument()
            let map: YMap<Int> = document.getOrCreateMap(named: "map")
            let events = await map.observeAsync()
            let consumer = Task {
                var iterator = events.makeAsyncIterator()
                let event = try #require(await iterator.next())
                received()
                #expect(event == [.inserted(key: "count", value: 42)])
                return await map.toMapAsync()
            }
            await map.set(42, forKey: "count")
            let state = try await consumer.value
            #expect(state == ["count": 42])
        }
    }

    @Test
    func applyNestedUpdateWithRegisteredObserver() async throws {
        try await confirmation("Receives the replicated root change") { received in
            let source = YDocument()
            let root: YMap<Int> = source.getOrCreateMap(named: "root")
            let update = await source.transact { transaction in
                let state: YMap<Int> = root.insertMap(forKey: "state", transaction: transaction)
                state.updateValue(7, forKey: "count", transaction: transaction)
                root.updateValue(1, forKey: "version", transaction: transaction)
                return transaction.transactionEncodeStateAsUpdate()
            }
            let target = YDocument()
            let targetRoot: YMap<Int> = target.getOrCreateMap(named: "root")
            var events = await targetRoot.observeAsync().makeAsyncIterator()
            try await target.transact { try $0.transactionApplyUpdate(update: update) }
            let event = try #require(await events.next())
            received()
            #expect(event == [.inserted(key: "version", value: 1)])
            let count = await target.transact { transaction in
                let state: YMap<Int>? = targetRoot.getMap(forKey: "state", transaction: transaction)
                return state?.get(key: "count", transaction: transaction)
            }
            #expect(count == 7)
        }
    }

    @Test(arguments: [false, true])
    func replicatedChangesCoordinateWithConcurrentReads(nested: Bool) async throws {
        try await confirmation("Receives each replicated change", expectedCount: 3) { received in
            let source = YDocument()
            let sourceRoot: YMap<Int> = source.getOrCreateMap(named: "root")
            let sourceMap: YMap<Int>
            if nested {
                sourceMap = await source.transact { sourceRoot.insertMap(forKey: "state", transaction: $0) }
            } else {
                sourceMap = sourceRoot
            }
            await sourceMap.set(0, forKey: "count")
            let initial = await source.transact { $0.transactionEncodeStateAsUpdate() }
            let target = YDocument()
            try await target.transact { try $0.transactionApplyUpdate(update: initial) }
            let targetRoot: YMap<Int> = target.getOrCreateMap(named: "root")
            let targetMap: YMap<Int>
            if nested {
                let state: YMap<Int>? = await target.transact { targetRoot.getMap(forKey: "state", transaction: $0) }
                targetMap = try #require(state)
            } else {
                targetMap = targetRoot
            }
            let events = await targetMap.observeAsync()
            let (acknowledgements, acknowledgement) = AsyncStream<Int>.makeStream()
            let consumer = Task {
                defer { acknowledgement.finish() }
                var iterator = events.makeAsyncIterator()
                for expected in 1...3 {
                    let event = try #require(await iterator.next())
                    received()
                    #expect(event == [.updated(key: "count", oldValue: expected - 1, newValue: expected)])
                    #expect(await targetMap.get(key: "count") == expected)
                    acknowledgement.yield(expected)
                }
            }
            var reads = acknowledgements.makeAsyncIterator()
            for value in 1...3 {
                let update = await source.transact { transaction in
                    sourceMap.updateValue(value, forKey: "count", transaction: transaction)
                    return transaction.transactionEncodeUpdate()
                }
                try await target.transact { try $0.transactionApplyUpdate(update: update) }
                async let vector = target.transact { $0.transactionStateVector() }
                #expect(await reads.next() == value)
                #expect(!(await vector).isEmpty)
            }
            try await consumer.value
        }
    }
}
