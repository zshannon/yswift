import Foundation
import Yniffi

/// A named annotation attached to CRDT item IDs.
public struct YIdAttribute<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let value: Value

    public init(name: String, value: Value) {
        self.name = name
        self.value = value
    }

    init(_ native: YrsIdAttribute) throws {
        name = native.name
        value = try JSONDecoder().decode(Value.self, from: Data(native.value.utf8))
    }

    func encoded() throws -> YrsIdAttribute {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return YrsIdAttribute(name: name, value: String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}

extension YIdAttribute: Equatable where Value: Equatable {}
extension YIdAttribute: Hashable where Value: Hashable {}

/// A range and its annotations. Queries can include gaps with no annotations.
public struct YIdMapRange<Value: Codable & Sendable>: Sendable {
    public let attributes: [YIdAttribute<Value>]
    public let range: YIdRange

    public init(attributes: [YIdAttribute<Value>], range: YIdRange) {
        self.attributes = attributes
        self.range = range
    }

    init(_ native: YrsIdMapRange) throws {
        attributes = try native.attributes.map(YIdAttribute.init)
        range = YIdRange(native.range)
    }

    func encoded() throws -> YrsIdMapRange {
        YrsIdMapRange(attributes: try attributes.map { try $0.encoded() }, range: range.native)
    }
}

extension YIdMapRange: Equatable where Value: Equatable {}

/// An immutable native attribution map with Codable annotation values.
///
/// Overlapping ranges retain all distinct annotations. Values are encoded as
/// JSON strings inside the native Yrs representation. Each operation creates a
/// local native value; the map itself stores only owned Swift values.
public struct YIdMap<Value: Codable & Sendable>: Sendable {
    public let idSet: YIdSet

    private let encodedV1: [UInt8]
    private let encodedV2: [UInt8]
    private let entries: [YIdMapRange<Value>]

    public var isEmpty: Bool { idSet.isEmpty }

    public init() {
        let native = YrsIdMap()
        idSet = YIdSet()
        encodedV1 = native.encodeV1()
        encodedV2 = native.encodeV2()
        entries = []
    }

    public init(attributes: [YIdAttribute<Value>], idSet: YIdSet) throws {
        try self.init(native: YrsIdMap.fromSet(set: idSet.native(), values: attributes.map { try $0.encoded() }))
    }

    /// Decodes native V1 data and validates every annotation as `Value`.
    public init(encodedV1: [UInt8]) throws {
        try self.init(native: YrsIdMap.decodeV1(data: encodedV1))
    }

    /// Decodes native V2 data and validates every annotation as `Value`.
    public init(encodedV2: [UInt8]) throws {
        try self.init(native: YrsIdMap.decodeV2(data: encodedV2))
    }

    public init(ranges: [YIdMapRange<Value>]) throws {
        try self.init(native: YrsIdMap.fromRanges(ranges: ranges.map { try $0.encoded() }))
    }

    private init(native: YrsIdMap) throws {
        entries = try native.ranges().map(YIdMapRange.init)
        idSet = YIdSet(native: native.asIdSet())
        encodedV1 = native.encodeV1()
        encodedV2 = native.encodeV2()
    }

    private func native() throws -> YrsIdMap {
        try YrsIdMap.decodeV1(data: encodedV1)
    }

    /// Compares native ranges and annotations, including their encoded values.
    public func isEqual(to other: Self) throws -> Bool {
        try native().equals(other: other.native())
    }

    /// Covers the requested range, including gaps with an empty attribute list.
    public func attributions(in range: YIdRange) throws -> [YIdMapRange<Value>] {
        try native().attributions(range: range.native).map(YIdMapRange.init)
    }

    public func contains(clientId: UInt64, clock: UInt32) throws -> Bool {
        try native().contains(client: clientId, clock: clock)
    }

    public func encodeV1() -> [UInt8] { encodedV1 }
    public func encodeV2() -> [UInt8] { encodedV2 }

    /// Keeps ranges whose complete annotation list satisfies the predicate.
    public func filter(_ isIncluded: ([YIdAttribute<Value>]) throws -> Bool) throws -> Self {
        let selected = try ranges().filter { try isIncluded($0.attributes) }
        let included = try YIdSet(ranges: selected.map(\.range))
        return try intersection(Self(attributes: [], idSet: included))
    }

    public func inserting(attributes: [YIdAttribute<Value>], range: YIdRange) throws -> Self {
        try Self(native: native().withRange(values: attributes.map { try $0.encoded() }, range: range.native))
    }

    /// Keeps IDs present in both maps, combining their annotations.
    public func intersection(_ other: Self) throws -> Self {
        try Self(native: native().intersection(other: other.native()))
    }

    public func ranges() -> [YIdMapRange<Value>] {
        entries
    }

    public func removing(_ range: YIdRange) throws -> Self {
        try Self(native: native().withoutRange(range: range.native))
    }

    /// Removes IDs covered by the other map, regardless of its annotations.
    public func subtracting(_ other: Self) throws -> Self {
        try Self(native: native().difference(other: other.native()))
    }

    public func subtracting(_ other: YIdSet) throws -> Self {
        try Self(native: native().differenceSet(other: other.native()))
    }

    /// Combines covered IDs and all annotations attached to overlapping ranges.
    public func union(_ other: Self) throws -> Self {
        try Self(native: native().union(other: other.native()))
    }
}
