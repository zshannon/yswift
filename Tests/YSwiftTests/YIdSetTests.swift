import Testing
@testable import YSwift

struct YIdSetTests {
    @Test
    func rangeAlgebraPreservesInputs() throws {
        let left = try YIdSet(ranges: [YIdRange(clientId: 7, clock: 2, length: 6)])
        let right = try YIdSet(ranges: [YIdRange(clientId: 7, clock: 5, length: 6)])
        #expect(try left.union(right).ranges == [YIdRange(clientId: 7, clock: 2, length: 9)])
        #expect(try left.intersection(right).ranges == [YIdRange(clientId: 7, clock: 5, length: 3)])
        #expect(try left.subtracting(right).ranges == [YIdRange(clientId: 7, clock: 2, length: 3)])
        #expect(left.ranges == [YIdRange(clientId: 7, clock: 2, length: 6)])
        #expect(try left.contains(clientId: 7, clock: 7))
        #expect(try !left.contains(clientId: 7, clock: 8))
    }

    @Test
    func disjointRangesAndLargeClientIDsRoundTrip() throws {
        let high = (UInt64(1) << 53) - 1
        let value = try YIdSet(ranges: [
            YIdRange(clientId: high, clock: 10, length: 2),
            YIdRange(clientId: 7, clock: 1, length: 2),
            YIdRange(clientId: high, clock: 20, length: 3)
        ])
        #expect(value.clientCount == 2)
        #expect(try YIdSet(encodedV1: value.encodeV1()) == value)
        #expect(try YIdSet(encodedV2: value.encodeV2()) == value)
        let split = try value.removing(YIdRange(clientId: high, clock: 21, length: 1))
        #expect(try !split.contains(clientId: high, clock: 21))
        #expect(try value.contains(clientId: high, clock: 21))
        #expect(try YIdSet().inserting(YIdRange(clientId: 1, clock: 0, length: 0)).isEmpty)
    }

    @Test
    func rejectsInvalidBoundaries() throws {
        #expect(throws: (any Error).self) {
            try YIdSet(ranges: [YIdRange(clientId: 1 << 53, clock: 0, length: 1)])
        }
        #expect(throws: (any Error).self) {
            try YIdSet(ranges: [YIdRange(clientId: 0, clock: .max, length: 1)])
        }
        #expect(throws: (any Error).self) { try YIdSet(encodedV1: [255]) }
        #expect(throws: (any Error).self) { try YIdSet(encodedV2: [255]) }
    }

    @Test
    func ownedValuesCrossTaskBoundaries() async throws {
        let original = try YIdSet(ranges: [YIdRange(clientId: 7, clock: 0, length: 2)])
        let extended = try await Task.detached {
            try original.inserting(YIdRange(clientId: 7, clock: 2, length: 2))
        }.value
        #expect(original.ranges == [YIdRange(clientId: 7, clock: 0, length: 2)])
        #expect(extended.ranges == [YIdRange(clientId: 7, clock: 0, length: 4)])
    }
}
