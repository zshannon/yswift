import Foundation
import Yniffi

/// A type that provides a map shared data type.
///
/// Store, order, and retrieve any single `Codable` type within a `YMap` keyed with a `String`.
///
/// Create a new `YMap` instance using ``YSwift/YDocument/getOrCreateMap(named:)`` from a ``YDocument``.
@YSwiftActor
public final class YMap<T: Codable & Sendable>: Transactable, YCollection {
    private let _map: YrsMap
    public let document: YDocument

    init(map: YrsMap, document: YDocument) {
        _map = map
        self.document = document
    }

    // MARK: - Properties

    /// Returns a Boolean value that indicates whether the map is empty.
    public var isEmpty: Bool {
        length() == 0
    }

    /// Returns the number of items in the map.
    public var count: Int {
        Int(length())
    }

    // MARK: - Async API (Preferred)

    /// Gets the value within a map identified by the string you provide.
    /// - Parameter key: The string that identifies the object.
    /// - Returns: The object within the map at that key, or `nil` if it's not available.
    public func get(key: String) async -> T? {
        withTransaction { txn -> T? in
            if let result = try? self._map.get(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Sets the value within a map identified by the string you provide.
    /// - Parameters:
    ///   - value: The object to set, or nil to remove.
    ///   - key: The string that identifies the object.
    public func set(_ value: T?, forKey key: String) async {
        withTransaction { txn in
            if let value = value {
                self._map.insert(tx: txn, key: key, value: Coder.encoded(value))
            } else {
                _ = try? self._map.remove(tx: txn, key: key)
            }
        }
    }

    /// Returns the length of the map.
    public func length() async -> UInt32 {
        withTransaction { txn in
            self._map.length(tx: txn)
        }
    }

    /// Returns a Boolean value indicating whether the key you provide is in the map.
    /// - Parameter key: A string that identifies an object within the map.
    public func containsKey(_ key: String) async -> Bool {
        withTransaction { txn in
            self._map.containsKey(tx: txn, key: key)
        }
    }

    /// Removes an object from the map.
    /// - Parameter key: A string that identifies the object to remove.
    /// - Returns: The item removed, or `nil` if unavailable.
    @discardableResult
    public func removeValue(forKey key: String) async -> T? {
        withTransaction { txn -> T? in
            if let result = try? self._map.remove(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Removes all items from the map.
    public func removeAll() async {
        withTransaction { txn in
            self._map.clear(tx: txn)
        }
    }

    /// Returns all keys from the map.
    public func keys() async -> [String] {
        withTransaction { self._map.keys(tx: $0) }
    }

    /// Returns all values from the map.
    public func values() async -> [T] {
        withTransaction { transaction in
            self._map.entries(tx: transaction).map { Coder.decoded($0.value) }
        }
    }

    /// Returns the map as a dictionary asynchronously.
    public func toMapAsync() async -> [String: T] {
        withTransaction { self.toMap(transaction: $0) }
    }

    // MARK: - Sync API with Explicit Transaction (Always Available)

    /// Gets the value using an existing transaction.
    public func get(key: String, transaction: YrsTransaction) -> T? {
        if let result = try? _map.get(tx: transaction, key: key) {
            return Coder.decoded(result)
        }
        return nil
    }

    /// Updates or inserts the value using an existing transaction.
    public func updateValue(_ value: T, forKey key: String, transaction: YrsTransaction) {
        _map.insert(tx: transaction, key: key, value: Coder.encoded(value))
    }

    /// Returns the length using an existing transaction.
    public func length(transaction: YrsTransaction) -> UInt32 {
        _map.length(tx: transaction)
    }

    /// Returns whether the key exists using an existing transaction.
    public func containsKey(_ key: String, transaction: YrsTransaction) -> Bool {
        _map.containsKey(tx: transaction, key: key)
    }

    /// Removes a value using an existing transaction.
    @discardableResult
    public func removeValue(forKey key: String, transaction: YrsTransaction) -> T? {
        if let result = try? _map.remove(tx: transaction, key: key) {
            return Coder.decoded(result)
        }
        return nil
    }

    /// Removes all items using an existing transaction.
    public func removeAll(transaction: YrsTransaction) {
        _map.clear(tx: transaction)
    }

    /// Iterates keys using an existing transaction.
    public func keys(transaction: YrsTransaction, _ body: @escaping (String) -> Void) {
        _map.keys(tx: transaction).forEach(body)
    }

    /// Iterates values using an existing transaction.
    public func values(transaction: YrsTransaction, _ body: @escaping (T) -> Void) {
        for entry in _map.entries(tx: transaction) { body(Coder.decoded(entry.value)) }
    }

    /// Iterates key-value pairs using an existing transaction.
    public func each(transaction: YrsTransaction, _ body: @escaping (String, T) -> Void) {
        for entry in _map.entries(tx: transaction) { body(entry.key, Coder.decoded(entry.value)) }
    }

    /// Returns the map as a dictionary using an existing transaction.
    public func toMap(transaction: YrsTransaction) -> [String: T] {
        Dictionary(uniqueKeysWithValues: _map.entries(tx: transaction).map { ($0.key, Coder.decoded($0.value)) })
    }

    // MARK: - Actor-isolated API (Creates Own Transaction)

    /// Gets or sets the value within a map identified by the string you provide.
    public subscript(key: String) -> T? {
        get {
            get(key: key, transaction: nil)
        }
        set {
            if let newValue = newValue {
                updateValue(newValue, forKey: key, transaction: nil)
            } else {
                removeValue(forKey: key, transaction: nil)
            }
        }
    }

    /// Updates or inserts the object for the key you provide.
    public func updateValue(_ value: T, forKey key: String, transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._map.insert(tx: txn, key: key, value: Coder.encoded(value))
        }
    }

    /// Returns the length of the map.
    public func length(transaction: YrsTransaction? = nil) -> UInt32 {
        withTransaction(transaction) { txn in
            self._map.length(tx: txn)
        }
    }

    /// Returns the object from the map identified by the key you provide.
    public func get(key: String, transaction: YrsTransaction? = nil) -> T? {
        withTransaction(transaction) { txn -> T? in
            if let result = try? self._map.get(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Returns a Boolean value indicating whether the key you provide is in the map.
    public func containsKey(_ key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.containsKey(tx: txn, key: key)
        }
    }

    /// Removes an object from the map.
    @discardableResult
    public func removeValue(forKey key: String, transaction: YrsTransaction? = nil) -> T? {
        withTransaction(transaction) { txn -> T? in
            if let result = try? self._map.remove(tx: txn, key: key) {
                return Coder.decoded(result)
            } else {
                return nil
            }
        }
    }

    /// Removes all items from the map.
    public func removeAll(transaction: YrsTransaction? = nil) {
        withTransaction(transaction) { txn in
            self._map.clear(tx: txn)
        }
    }

    /// Calls the closure you provide with each key from the map.
    public func keys(transaction: YrsTransaction? = nil, _ body: @escaping (String) -> Void) {
        withTransaction(transaction) { self.keys(transaction: $0, body) }
    }

    /// Calls the closure you provide with each value from the map.
    public func values(transaction: YrsTransaction? = nil, _ body: @escaping (T) -> Void) {
        withTransaction(transaction) { self.values(transaction: $0, body) }
    }

    /// Iterates over the map of elements, providing each element to the closure you provide.
    public func each(transaction: YrsTransaction? = nil, _ body: @escaping (String, T) -> Void) {
        withTransaction(transaction) { self.each(transaction: $0, body) }
    }



    /// Registers a closure that is called with an array of changes to the map.
    /// - Parameter body: A closure that is called with an array of map changes.
    /// The key replaces any existing observer with the same key. Use this collection's document transaction.
    /// - Returns: False if the collection has been deleted.
    @discardableResult
    public func observe(key: String, transaction: YrsTransaction, _ body: @escaping @Sendable ([YMapChange<T>]) -> Void) -> Bool {
        let delegate = YMapObservationDelegate(decoded: Coder.decoded, callback: body)
        return _map.observe(tx: transaction, key: key, delegate: delegate)
    }

    /// Removes the observer registered under `key`. Use a transaction from this collection's document.
    /// Returns false if the collection was deleted or the key was not registered.
    @discardableResult
    public func unobserve(key: String, transaction: YrsTransaction) -> Bool {
        _map.unobserve(tx: transaction, key: key)
    }

    /// Removes an observer on the YSwift actor.
    @discardableResult
    public func unobserveAsync(key: String) async -> Bool {
        document.transact { transaction in
            self.unobserve(key: key, transaction: transaction)
        }
    }

    /// Returns an async stream of map changes.
    ///
    /// Changes are delivered asynchronously after the transaction commits,
    /// making it safe to read document state from within the stream consumer.
    ///
    /// ```swift
    /// for await changes in await map.observeAsync() {
    ///     // Safe to call transactSync or read state here
    ///     let currentState = map.toMap()
    /// }
    /// ```
    ///
    public func observeAsync() async -> AsyncStream<[YMapChange<T>]> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<[YMapChange<T>]>.makeStream(bufferingPolicy: .unbounded)
        let observing = document.transact { transaction in
            self.observe(key: key, transaction: transaction) { continuation.yield($0) }
        }
        continuation.onTermination = { _ in
            Task { await self.unobserveAsync(key: key) }
        }
        if !observing { continuation.finish() }
        return stream
    }

    /// Returns the map as a dictionary.
    public func toMap(transaction: YrsTransaction? = nil) -> [String: T] {
        withTransaction(transaction) { self.toMap(transaction: $0) }
    }
    
    public func pointer() -> YrsCollectionPtr {
        return _map.rawPtr()
    }
}

final class YMapObservationDelegate<T: Codable & Sendable>: YrsMapObservationDelegate {
    private let callback: @Sendable ([YMapChange<T>]) -> Void
    private let decoded: @Sendable (String) -> T

    init(
        decoded: @escaping @Sendable (String) -> T,
        callback: @escaping @Sendable ([YMapChange<T>]) -> Void
    ) {
        self.decoded = decoded
        self.callback = callback
    }

    func call(value: [YrsMapChange]) {
        let result: [YMapChange<T>] = value.map { rsChange -> YMapChange<T> in
            switch rsChange.change {
            case let .inserted(value):
                return YMapChange.inserted(key: rsChange.key, value: decoded(value))
            case let .updated(oldValue, newValue):
                return YMapChange.updated(key: rsChange.key, oldValue: decoded(oldValue), newValue: decoded(newValue))
            case let .removed(value):
                return YMapChange.removed(key: rsChange.key, value: decoded(value))
            }
        }
        callback(result)
    }
}

/// A type that represents changes to a Map.
public enum YMapChange<T> {
    /// The key and value inserted into the map.
    case inserted(key: String, value: T)
    /// The key, old value, and new value updated in the map.
    case updated(key: String, oldValue: T, newValue: T)
    /// The key and value removed from the map.
    case removed(key: String, value: T)
}

extension YMapChange: Equatable where T: Equatable {
    public static func == (lhs: YMapChange<T>, rhs: YMapChange<T>) -> Bool {
        switch (lhs, rhs) {
        case let (.inserted(key1, value1), .inserted(key2, value2)):
            return key1 == key2 && value1 == value2
        case let (.updated(key1, oldValue1, newValue1), .updated(key2, oldValue2, newValue2)):
            return key1 == key2 && oldValue1 == oldValue2 && newValue1 == newValue2
        case let (.removed(key1, value1), .removed(key2, value2)):
            return key1 == key2 && value1 == value2
        default:
            return false
        }
    }
}

extension YMapChange: Sendable where T: Sendable {}

extension YMapChange: Hashable where T: Hashable {}

// MARK: - Subdocument Support

extension YMap {
    /// Returns a subdocument for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the subdocument.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The subdocument for the specified key, or nil if no subdocument exists for that key.
    public func getSubdoc(forKey key: String, transaction: YrsTransaction? = nil) -> YDocument? {
        withTransaction(transaction) { txn in
            self._map.getDoc(tx: txn, key: key).map { YDocument(wrapping: $0) }
        }
    }

    /// Inserts a subdocument for the specified key.
    /// - Parameters:
    ///   - subdoc: The subdocument to insert.
    ///   - key: The key to associate with the subdocument.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The integrated subdocument (may be different from the input if the document was already integrated).
    @discardableResult
    public func insertSubdoc(_ subdoc: YDocument, forKey key: String, transaction: YrsTransaction? = nil) -> YDocument {
        withTransaction(transaction) { txn in
            let inserted = self._map.insertDoc(tx: txn, key: key, doc: subdoc.document)
            return YDocument(wrapping: inserted)
        }
    }
}

// MARK: - Nested Shared Type Support

extension YMap {
    /// Returns a nested YArray for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested array, or nil if no array exists for that key.
    public func getArray<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U>? {
        withTransaction(transaction) { txn in
            self._map.getArray(tx: txn, key: key).map { YArray(array: $0, document: self.document) }
        }
    }

    /// Returns a nested YMap for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested map, or nil if no map exists for that key.
    public func getMap<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U>? {
        withTransaction(transaction) { txn in
            self._map.getMap(tx: txn, key: key).map { YMap<U>(map: $0, document: self.document) }
        }
    }

    /// Returns a nested YText for the specified key.
    /// - Parameters:
    ///   - key: The key that identifies the nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The nested text, or nil if no text exists for that key.
    public func getText(forKey key: String, transaction: YrsTransaction? = nil) -> YText? {
        withTransaction(transaction) { txn in
            self._map.getText(tx: txn, key: key).map { YText(text: $0, document: self.document) }
        }
    }

    /// Checks if the value at the specified key is an undefined reference.
    /// - Parameters:
    ///   - key: The key to check.
    ///   - transaction: An optional transaction to use.
    /// - Returns: True if the key exists but holds an undefined/deleted reference.
    public func isUndefined(forKey key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.isUndefined(tx: txn, key: key)
        }
    }

    /// Inserts an empty nested YMap at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested map.
    @discardableResult
    public func insertMap<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._map.insertMap(tx: txn, key: key), document: self.document)
        }
    }

    /// Inserts an empty nested YArray at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested array.
    @discardableResult
    public func insertArray<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._map.insertArray(tx: txn, key: key), document: self.document)
        }
    }

    /// Inserts an empty nested YText at the specified key.
    /// - Parameters:
    ///   - key: The key for the new nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The newly inserted nested text.
    @discardableResult
    public func insertText(forKey key: String, transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._map.insertText(tx: txn, key: key), document: self.document)
        }
    }

    /// Updates value only if different from current value.
    /// - Parameters:
    ///   - value: The new value to set.
    ///   - key: The key to update.
    ///   - transaction: An optional transaction to use.
    /// - Returns: True if the value was updated, false if unchanged.
    @discardableResult
    public func tryUpdate(_ value: T, forKey key: String, transaction: YrsTransaction? = nil) -> Bool {
        withTransaction(transaction) { txn in
            self._map.tryUpdate(tx: txn, key: key, value: Coder.encoded(value))
        }
    }

    /// Gets existing nested map or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested map.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested map.
    public func getOrInsertMap<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YMap<U> {
        withTransaction(transaction) { txn in
            YMap<U>(map: self._map.getOrInsertMap(tx: txn, key: key), document: self.document)
        }
    }

    /// Gets existing nested array or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested array.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested array.
    public func getOrInsertArray<U: Codable & Sendable>(forKey key: String, transaction: YrsTransaction? = nil) -> YArray<U> {
        withTransaction(transaction) { txn in
            YArray<U>(array: self._map.getOrInsertArray(tx: txn, key: key), document: self.document)
        }
    }

    /// Gets existing nested text or creates new one at key.
    /// - Parameters:
    ///   - key: The key for the nested text.
    ///   - transaction: An optional transaction to use.
    /// - Returns: The existing or newly created nested text.
    public func getOrInsertText(forKey key: String, transaction: YrsTransaction? = nil) -> YText {
        withTransaction(transaction) { txn in
            YText(text: self._map.getOrInsertText(tx: txn, key: key), document: self.document)
        }
    }
}
