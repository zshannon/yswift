import Foundation
@preconcurrency import Yniffi

/// A type that provides a text-oriented shared data type.
///
/// Create a new `YText` instance using ``YSwift/YDocument/getOrCreateText(named:)`` from a ``YDocument``.
public final class YText: Transactable, YCollection, @unchecked Sendable {
    private let _text: YrsText
    let document: YDocument

    init(text: YrsText, document: YDocument) {
        _text = text
        self.document = document
    }

    // MARK: - Async APIs (Preferred)

    /// Appends a string asynchronously.
    /// - Parameter text: The string to append.
    public func append(_ text: String) async {
        await document.transact { txn in
            self._text.append(tx: txn, text: text)
        }
    }

    /// Inserts a string at an index position asynchronously.
    /// - Parameters:
    ///   - text: The string to insert.
    ///   - index: The position, within the UTF-8 buffer view, to insert the string.
    public func insert(_ text: String, at index: UInt32) async {
        await document.transact { txn in
            self._text.insert(tx: txn, index: index, chunk: text)
        }
    }

    /// Inserts a string with attributes asynchronously.
    /// - Parameters:
    ///   - text: The string to insert.
    ///   - attributes: The attributes to associate with the string.
    ///   - index: The position to insert at.
    public func insertWithAttributes(_ text: String, attributes: [String: Any], at index: UInt32) async {
        let encodedAttributes = Coder.encoded(attributes)
        await document.transact { txn in
            self._text.insertWithAttributes(tx: txn, index: index, chunk: text, attrs: encodedAttributes)
        }
    }

    /// Embeds a Codable type asynchronously.
    /// - Parameters:
    ///   - embed: The codable type to embed.
    ///   - index: The position to embed at.
    public func insertEmbed<T: Encodable & Sendable>(_ embed: T, at index: UInt32) async {
        await document.transact { txn in
            self._text.insertEmbed(tx: txn, index: index, content: Coder.encoded(embed))
        }
    }

    /// Embeds a Codable type with attributes asynchronously.
    /// - Parameters:
    ///   - embed: The codable type to embed.
    ///   - attributes: The attributes to associate with the embedded type.
    ///   - index: The position to embed at.
    public func insertEmbedWithAttributes<T: Encodable & Sendable>(_ embed: T, attributes: [String: Any], at index: UInt32) async {
        let encodedAttributes = Coder.encoded(attributes)
        await document.transact { txn in
            self._text.insertEmbedWithAttributes(tx: txn, index: index, content: Coder.encoded(embed), attrs: encodedAttributes)
        }
    }

    /// Applies or updates attributes for a range asynchronously.
    /// - Parameters:
    ///   - index: The index position to start formatting.
    ///   - length: The length of characters to update.
    ///   - attributes: The attributes to associate.
    public func format(at index: UInt32, length: UInt32, attributes: [String: Any]) async {
        let encodedAttributes = Coder.encoded(attributes)
        await document.transact { txn in
            self._text.format(tx: txn, index: index, length: length, attrs: encodedAttributes)
        }
    }

    /// Removes a range of text asynchronously.
    /// - Parameters:
    ///   - start: The index position to start removing.
    ///   - length: The length of characters to remove.
    public func removeRange(start: UInt32, length: UInt32) async {
        await document.transact { txn in
            self._text.removeRange(tx: txn, start: start, length: length)
        }
    }

    /// Returns the string asynchronously.
    public func getStringAsync() async -> String {
        await document.transact { txn in
            self._text.getString(tx: txn)
        }
    }

    /// Returns the length asynchronously.
    public func lengthAsync() async -> UInt32 {
        await document.transact { txn in
            self._text.length(tx: txn)
        }
    }

    /// Returns an async stream of text changes.
    public func observeAsync() async -> AsyncStream<[YTextChange]> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<[YTextChange]>.makeStream(bufferingPolicy: .unbounded)
        let observing = await document.transact { transaction in
            self.observe(key: key, transaction: transaction) { continuation.yield($0) }
        }
        continuation.onTermination = { _ in
            Task { await self.unobserveAsync(key: key) }
        }
        if !observing { continuation.finish() }
        return stream
    }

    /// Applies a delta asynchronously.
    /// - Parameter delta: An array of text changes to apply.
    public func applyDelta(_ delta: [YTextChange]) async {
        let yrsDelta: [YrsDelta] = delta.map { change in
            switch change {
            case let .inserted(value, attributes):
                return YrsDelta.inserted(value: value, attrs: Coder.encoded(attributes))
            case let .deleted(index):
                return YrsDelta.deleted(index: index)
            case let .retained(index, attributes):
                return YrsDelta.retained(index: index, attrs: Coder.encoded(attributes))
            }
        }
        await document.transact { txn in
            self._text.applyDelta(tx: txn, delta: yrsDelta)
        }
    }

    /// Returns the text content as diff chunks asynchronously.
    public func diffAsync() async -> [YTextDiff] {
        let differences = await document.transact { txn in
            self._text.diff(tx: txn)
        }
        return differences.map { yrsDiff in
            switch yrsDiff {
            case let .text(value, attrs):
                return YTextDiff.text(value: value, attributes: Coder.decoded(attrs))
            case let .embed(value, attrs):
                return YTextDiff.embed(value: value, attributes: Coder.decoded(attrs))
            case let .other(attrs):
                return YTextDiff.other(attributes: Coder.decoded(attrs))
            }
        }
    }

    // MARK: - Sync APIs (Deprecated)

    /// Appends a string you provide to the shared text data type.
    /// - Warning: Deprecated. Use async `append(_:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - text: The string to append.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async append(_:) or pass explicit transaction")
    public func append(_ text: String, in transaction: YrsTransaction? = nil) {
        if let transaction {
            self._text.append(tx: transaction, text: text)
        } else {
            withTransaction(transaction) { txn in
                self._text.append(tx: txn, text: text)
            }
        }
    }

    /// Inserts a string at an index position you provide.
    /// - Warning: Deprecated. Use async `insert(_:at:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - text: The string to insert.
    ///   - index: The position, within the UTF-8 buffer view, to insert the string.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async insert(_:at:) or pass explicit transaction")
    public func insert(
        _ text: String,
        at index: UInt32,
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.insert(tx: transaction, index: index, chunk: text)
        } else {
            withTransaction(transaction) { txn in
                self._text.insert(tx: txn, index: index, chunk: text)
            }
        }
    }

    /// Inserts a string, with attributes, at an index position you provide.
    /// - Warning: Deprecated. Use async `insertWithAttributes(_:attributes:at:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - text: The string to insert.
    ///   - attributes: The attributes to associate with the appended string.
    ///   - index: The position, within the UTF-8 buffer view, to insert the string.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async insertWithAttributes(_:attributes:at:) or pass explicit transaction")
    public func insertWithAttributes(
        _ text: String,
        attributes: [String: Any],
        at index: UInt32,
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.insertWithAttributes(tx: transaction, index: index, chunk: text, attrs: Coder.encoded(attributes))
        } else {
            withTransaction(transaction) { txn in
                self._text.insertWithAttributes(tx: txn, index: index, chunk: text, attrs: Coder.encoded(attributes))
            }
        }
    }

    /// Embeds a Codable type you provide within the text at the location you provide.
    /// - Warning: Deprecated. Use async `insertEmbed(_:at:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - embed: The codable type to embed.
    ///   - index: The position, within the UTF-8 buffer view, to embed the object.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async insertEmbed(_:at:) or pass explicit transaction")
    public func insertEmbed<T: Encodable>(
        _ embed: T,
        at index: UInt32,
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.insertEmbed(tx: transaction, index: index, content: Coder.encoded(embed))
        } else {
            withTransaction(transaction) { txn in
                self._text.insertEmbed(tx: txn, index: index, content: Coder.encoded(embed))
            }
        }
    }

    /// Embeds a Codable type you provide within the text at the location you provide.
    /// - Warning: Deprecated. Use async `insertEmbedWithAttributes(_:attributes:at:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - embed: The codable type to embed.
    ///   - attributes: The attributes to associate with the embedded type.
    ///   - index: The position, within the UTF-8 buffer view, to embed the object.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async insertEmbedWithAttributes(_:attributes:at:) or pass explicit transaction")
    public func insertEmbedWithAttributes<T: Encodable>(
        _ embed: T,
        attributes: [String: Any],
        at index: UInt32,
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.insertEmbedWithAttributes(tx: transaction, index: index, content: Coder.encoded(embed), attrs: Coder.encoded(attributes))
        } else {
            withTransaction(transaction) { txn in
                self._text.insertEmbedWithAttributes(tx: txn, index: index, content: Coder.encoded(embed), attrs: Coder.encoded(attributes))
            }
        }
    }

    /// Applies or updates attributes associated with a range of the string.
    /// - Warning: Deprecated. Use async `format(at:length:attributes:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - index: The index position, in the UTF-8 view of the string, to start formatting characters.
    ///   - length: The length of characters to update.
    ///   - attributes: The attributes to associate with the string.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async format(at:length:attributes:) or pass explicit transaction")
    public func format(
        at index: UInt32,
        length: UInt32,
        attributes: [String: Any],
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.format(tx: transaction, index: index, length: length, attrs: Coder.encoded(attributes))
        } else {
            withTransaction(transaction) { txn in
                self._text.format(tx: txn, index: index, length: length, attrs: Coder.encoded(attributes))
            }
        }
    }

    /// Removes a range of text starting at a position you provide, removing the length that you provide.
    /// - Warning: Deprecated. Use async `removeRange(start:length:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - start: The index position, in the UTF-8 view of the string, to start removing characters.
    ///   - length: The length of characters to remove.
    ///   - transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async removeRange(start:length:) or pass explicit transaction")
    public func removeRange(
        start: UInt32,
        length: UInt32,
        in transaction: YrsTransaction? = nil
    ) {
        if let transaction {
            self._text.removeRange(tx: transaction, start: start, length: length)
        } else {
            withTransaction(transaction) { txn in
                self._text.removeRange(tx: txn, start: start, length: length)
            }
        }
    }

    /// Returns the string within the text.
    /// - Warning: Deprecated. Use async `getStringAsync()` or pass an explicit transaction.
    /// - Parameter transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async getStringAsync() or pass explicit transaction")
    public func getString(in transaction: YrsTransaction? = nil) -> String {
        if let transaction {
            self._text.getString(tx: transaction)
        } else {
            withTransaction(transaction) { txn in
                self._text.getString(tx: txn)
            }
        }
    }

    /// Returns the length of the string.
    /// - Warning: Deprecated. Use async `lengthAsync()` or pass an explicit transaction.
    /// - Parameter transaction: An optional transaction to use when appending the string.
    @available(*, deprecated, message: "Use async lengthAsync() or pass explicit transaction")
    public func length(in transaction: YrsTransaction? = nil) -> UInt32 {
        if let transaction {
            self._text.length(tx: transaction)
        } else {
            withTransaction(transaction) { txn in
                self._text.length(tx: txn)
            }
        }
    }



    /// Registers a closure that is called with an array of changes to the text.
    /// - Warning: Deprecated. Use `observeAsync()` instead.
    /// - Parameter callback: The closure to process reported changes from the text.
    /// The key replaces any existing observer with the same key. Use this collection's document transaction.
    /// - Returns: False if the collection has been deleted.
    @discardableResult
    public func observe(key: String, transaction: YrsTransaction, _ body: @escaping (sending [YTextChange]) -> Void) -> Bool {
        let delegate = YTextObservationDelegate(callback: body)
        return _text.observe(tx: transaction, key: key, delegate: delegate)
    }

    /// Removes the observer registered under `key`. Use a transaction from this collection's document.
    /// Returns false if the collection was deleted or the key was not registered.
    @discardableResult
    public func unobserve(key: String, transaction: YrsTransaction) -> Bool {
        _text.unobserve(tx: transaction, key: key)
    }

    /// Removes an observer on the document's async transaction queue.
    @discardableResult
    public func unobserveAsync(key: String) async -> Bool {
        await document.transact { transaction in
            self.unobserve(key: key, transaction: transaction)
        }
    }
    
    public func pointer() -> YrsCollectionPtr {
        return _text.rawPtr()
    }

    // MARK: - Delta Operations (Deprecated)

    /// Applies a delta to the text.
    /// - Warning: Deprecated. Use async `applyDelta(_:)` or pass an explicit transaction.
    /// - Parameters:
    ///   - delta: An array of text changes to apply.
    ///   - transaction: An optional transaction to use.
    @available(*, deprecated, message: "Use async applyDelta(_:) or pass explicit transaction")
    public func applyDelta(_ delta: [YTextChange], in transaction: YrsTransaction? = nil) {
        let yrsDelta: [YrsDelta] = delta.map { change in
            switch change {
            case let .inserted(value, attributes):
                return YrsDelta.inserted(value: value, attrs: Coder.encoded(attributes))
            case let .deleted(index):
                return YrsDelta.deleted(index: index)
            case let .retained(index, attributes):
                return YrsDelta.retained(index: index, attrs: Coder.encoded(attributes))
            }
        }
        withTransaction(transaction) { txn in
            self._text.applyDelta(tx: txn, delta: yrsDelta)
        }
    }

    /// Returns the text content as a list of diff chunks with formatting.
    /// - Warning: Deprecated. Use async `diffAsync()` or pass an explicit transaction.
    /// - Parameter transaction: An optional transaction to use.
    /// - Returns: An array of text diff chunks.
    @available(*, deprecated, message: "Use async diffAsync() or pass explicit transaction")
    public func diff(in transaction: YrsTransaction? = nil) -> [YTextDiff] {
        withTransaction(transaction) { txn in
            self._text.diff(tx: txn).map { yrsDiff in
                switch yrsDiff {
                case let .text(value, attrs):
                    return YTextDiff.text(value: value, attributes: Coder.decoded(attrs))
                case let .embed(value, attrs):
                    return YTextDiff.embed(value: value, attributes: Coder.decoded(attrs))
                case let .other(attrs):
                    return YTextDiff.other(attributes: Coder.decoded(attrs))
                }
            }
        }
    }
}

extension YText: Equatable {
    /// Returns a Boolean value that indicates whether the text values are identical.
    /// - Parameters:
    ///   - lhs: The first text type
    ///   - rhs: The second text type
    /// - Returns: Returns `true` if the text is identical, irrespective of attributes, otherwise false.
    public static func == (lhs: YText, rhs: YText) -> Bool {
        lhs.getString() == rhs.getString()
    }
}

public extension String {
    init(_ yText: YText) {
        self = yText.getString()
    }
}

extension YText: CustomStringConvertible {
    /// Returns the current string within the text.
    public var description: String {
        getString()
    }
}

class YTextObservationDelegate: YrsTextObservationDelegate {
    private var callback: (sending [YTextChange]) -> Void

    init(callback: @escaping (sending [YTextChange]) -> Void) {
        self.callback = callback
    }

    func call(value: [YrsDelta]) {
        // Build fresh values without carrying the borrowed FFI array's isolation region.
        var result: [YTextChange] = []
        for change in value {
            switch change {
            case let .inserted(value, attrs):
                result.append(.inserted(value: value, attributes: Coder.decoded(attrs)))
            case let .retained(index, attrs):
                result.append(.retained(index: index, attributes: Coder.decoded(attrs)))
            case let .deleted(index):
                result.append(.deleted(index: index))
            }
        }
        callback(result)
    }
}

/// A change to the text or attributes associated with the text.
public enum YTextChange {
    /// Inserted string,and any associated attributes.
    case inserted(value: String, attributes: [String: Any])
    /// Deleted characters.
    case deleted(index: UInt32)
    /// Updated character position and any associated attributes.
    case retained(index: UInt32, attributes: [String: Any])
}

/// A diff chunk from the text with formatting information.
public enum YTextDiff {
    /// A text chunk with optional attributes.
    case text(value: String, attributes: [String: Any])
    /// An embedded object with optional attributes.
    case embed(value: String, attributes: [String: Any])
    /// Other content with optional attributes.
    case other(attributes: [String: Any])
}
