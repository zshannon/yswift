import Foundation
import Testing
@testable import YSwift

struct YIdMapTests {
    struct Author: Codable, Equatable, Sendable {
        let name: String
        let revision: Int
    }

    @Test
    func overlappingAttributionsPreserveBothAuthors() throws {
        let alice = YIdAttribute(name: "author", value: Author(name: "Alice", revision: 1))
        let bob = YIdAttribute(name: "author", value: Author(name: "Bob", revision: 2))
        let first = try YIdMap<Author>().inserting(attributes: [alice], range: YIdRange(clientId: 7, clock: 2, length: 6))
        let combined = try first.inserting(attributes: [bob], range: YIdRange(clientId: 7, clock: 5, length: 5))
        let spans = try combined.attributions(in: YIdRange(clientId: 7, clock: 0, length: 12))
        #expect(spans.map(\.range) == [
            YIdRange(clientId: 7, clock: 0, length: 2),
            YIdRange(clientId: 7, clock: 2, length: 3),
            YIdRange(clientId: 7, clock: 5, length: 3),
            YIdRange(clientId: 7, clock: 8, length: 2),
            YIdRange(clientId: 7, clock: 10, length: 2)
        ])
        #expect(spans[2].attributes.contains(alice))
        #expect(spans[2].attributes.contains(bob))
        #expect(spans.first?.attributes.isEmpty == true)
        #expect(first.ranges().count == 1)
        #expect(combined.idSet.ranges == [YIdRange(clientId: 7, clock: 2, length: 8)])
        let second = try YIdMap<Author>().inserting(attributes: [bob], range: YIdRange(clientId: 7, clock: 5, length: 5))
        let intersection = try first.intersection(second).ranges()
        #expect(intersection.map(\.range) == [YIdRange(clientId: 7, clock: 5, length: 3)])
        #expect(intersection.first?.attributes.contains(alice) == true)
        #expect(intersection.first?.attributes.contains(bob) == true)
        #expect(try first.subtracting(second).idSet.ranges == [YIdRange(clientId: 7, clock: 2, length: 3)])
    }

    @Test
    func nativeSerializationAndSetOperations() throws {
        let range = YIdRange(clientId: (1 << 53) - 1, clock: 2, length: 6)
        let set = try YIdSet(ranges: [range])
        let map = try YIdMap(attributes: [YIdAttribute(name: "author", value: "Alice")], idSet: set)
        #expect(try YIdMap<String>(encodedV1: map.encodeV1()).isEqual(to: map))
        #expect(try YIdMap<String>(encodedV2: map.encodeV2()).isEqual(to: map))
        let cut = try YIdSet(ranges: [YIdRange(clientId: range.clientId, clock: 4, length: 2)])
        let remaining = try map.subtracting(cut)
        #expect(try remaining.idSet == set.subtracting(cut))
        #expect(try map.intersection(remaining).idSet == remaining.idSet)
        #expect(try remaining.union(map).idSet == set)
        #expect(try map.subtracting(remaining).idSet == cut)
        #expect(try map.filter { $0.contains { $0.value == "Alice" } }.isEqual(to: map))
        #expect(try map.filter { _ in false }.isEmpty)
        #expect(try !map.removing(range).contains(clientId: range.clientId, clock: 2))
        let unattributed = try YIdMap<String>(attributes: [], idSet: set)
        #expect(try unattributed.filter { $0.isEmpty }.isEqual(to: unattributed))
    }

    @Test
    func malformedAndMismatchedValuesThrow() throws {
        #expect(throws: (any Error).self) { try YIdMap<String>(encodedV1: [255]) }
        #expect(throws: (any Error).self) { try YIdMap<String>(encodedV2: [255]) }
        #expect(throws: (any Error).self) {
            try YIdMap<String>().inserting(attributes: [], range: YIdRange(clientId: 1 << 53, clock: 0, length: 1))
        }
        let strings = try YIdMap<String>().inserting(attributes: [YIdAttribute(name: "value", value: "text")], range: YIdRange(clientId: 1, clock: 0, length: 1))
        #expect(throws: (any Error).self) { try YIdMap<Int>(encodedV1: strings.encodeV1()) }
    }

    @Test
    func ownedAttributionsCrossTaskBoundaries() async throws {
        let original = try YIdMap<String>().inserting(
            attributes: [YIdAttribute(name: "author", value: "Alice")],
            range: YIdRange(clientId: 7, clock: 0, length: 2)
        )
        let extended = try await Task.detached {
            try original.inserting(
                attributes: [YIdAttribute(name: "author", value: "Bob")],
                range: YIdRange(clientId: 7, clock: 2, length: 2)
            )
        }.value
        #expect(original.ranges().count == 1)
        #expect(extended.ranges().count == 2)
        #expect(extended.idSet.ranges == [YIdRange(clientId: 7, clock: 0, length: 4)])
    }
}
