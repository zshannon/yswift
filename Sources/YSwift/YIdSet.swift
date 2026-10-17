import Yniffi

/// A contiguous range of CRDT item IDs from one client.
///
/// Set and map operations validate that the client fits in 53 bits and that the
/// exclusive range end fits in a 32-bit clock. Empty ranges are permitted.
public struct YIdRange: Codable, Hashable, Sendable {
    public let clientId: UInt64
    public let clock: UInt32
    public let length: UInt32

    public init(clientId: UInt64, clock: UInt32, length: UInt32) {
        self.clientId = clientId
        self.clock = clock
        self.length = length
    }

    init(_ native: YrsIdRange) {
        self.init(clientId: native.clientId, clock: native.clock, length: native.length)
    }

    var native: YrsIdRange {
        YrsIdRange(clientId: clientId, clock: clock, length: length)
    }
}

/// An immutable set of CRDT item IDs, independent of a document's lifetime.
/// Operations return new values and use Yrs's native range algebra.
public struct YIdSet: Equatable, Sendable {
    public let clientCount: UInt64
    public let ranges: [YIdRange]

    private let encodedV1: [UInt8]
    private let encodedV2: [UInt8]

    public var isEmpty: Bool { ranges.isEmpty }

    public init() { self.init(native: YrsIdSet()) }

    /// Decodes the native Yrs V1 representation.
    public init(encodedV1: [UInt8]) throws {
        let decoded = try YrsIdSet.decodeV1(data: encodedV1)
        try self.init(ranges: decoded.ranges().map(YIdRange.init))
    }

    /// Decodes the native Yrs V2 representation.
    public init(encodedV2: [UInt8]) throws {
        let decoded = try YrsIdSet.decodeV2(data: encodedV2)
        try self.init(ranges: decoded.ranges().map(YIdRange.init))
    }

    public init(ranges: [YIdRange]) throws {
        self.init(native: try YrsIdSet.fromRanges(ranges: ranges.map(\.native)))
    }

    init(native: YrsIdSet) {
        clientCount = native.clientCount()
        ranges = native.ranges().map(YIdRange.init)
        encodedV1 = native.encodeV1()
        encodedV2 = native.encodeV2()
    }

    func native() throws -> YrsIdSet {
        try YrsIdSet.decodeV1(data: encodedV1)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ranges == rhs.ranges
    }

    public func contains(clientId: UInt64, clock: UInt32) throws -> Bool {
        try native().contains(client: clientId, clock: clock)
    }

    public func encodeV1() -> [UInt8] { encodedV1 }
    public func encodeV2() -> [UInt8] { encodedV2 }

    public func inserting(_ range: YIdRange) throws -> Self {
        Self(native: try native().withRange(range: range.native))
    }

    public func intersection(_ other: Self) throws -> Self {
        Self(native: try native().intersection(other: other.native()))
    }

    public func removing(_ range: YIdRange) throws -> Self {
        Self(native: try native().withoutRange(range: range.native))
    }

    public func subtracting(_ other: Self) throws -> Self {
        Self(native: try native().difference(other: other.native()))
    }

    public func union(_ other: Self) throws -> Self {
        Self(native: try native().union(other: other.native()))
    }
}
