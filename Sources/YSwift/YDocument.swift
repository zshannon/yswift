import Foundation
import Yniffi

/// YDocument holds YSwift shared data types and coordinates collaboration and changes.
@YSwiftActor
public final class YDocument {
    private let nativeDocument: @YSwiftActor () -> YrsDoc

    var document: YrsDoc { nativeDocument() }

    /// Create a new YSwift Document.
    public nonisolated init() {
        let document = YrsDoc()
        nativeDocument = { @YSwiftActor in document }
    }

    /// Create a new YSwift Document with custom options.
    /// - Parameter options: Configuration options for the document.
    public nonisolated init(options: YDocumentOptions) {
        precondition(options.clientId.map { $0 < (1 << 53) } ?? true, "Yrs client IDs must fit in 53 bits")
        let document = YrsDoc.newWithOptions(options: options.yrsOptions)
        nativeDocument = { @YSwiftActor in document }
    }

    /// Internal initializer for wrapping a YrsDoc (used when retrieving subdocuments).
    internal init(wrapping doc: YrsDoc) {
        nativeDocument = { @YSwiftActor in doc }
    }

    // MARK: - Identity Properties

    /// Whether this document will automatically load when accessed as a subdocument.
    public var autoLoad: Bool {
        document.autoLoad()
    }

    /// The client ID of this document.
    public var clientId: UInt64 {
        document.clientId()
    }

    /// The unique identifier (GUID) of this document.
    public var guid: String {
        document.guid()
    }

    /// Whether this document should be loaded when accessed.
    public var shouldLoad: Bool {
        document.shouldLoad()
    }

    /// The parent document if this is a subdocument, or nil if this is a root document.
    public var parentDocument: YDocument? {
        document.parentDoc().map { YDocument(wrapping: $0) }
    }

    // MARK: - Identity Methods

    /// Returns whether this document is the same instance as another document.
    /// - Parameter other: The document to compare with.
    /// - Returns: True if both documents reference the same underlying document.
    public func isSame(as other: YDocument) -> Bool {
        document.ptrEq(other: other.document)
    }

    // MARK: - Subdocument Lifecycle

    /// Loads a subdocument. Call this within a transaction of the parent document.
    /// - Parameter transaction: A transaction from the parent document.
    public func load(in transaction: YrsTransaction) {
        document.load(parentTxn: transaction)
    }

    /// Destroys and removes this subdocument from its parent. Call this within a transaction of the parent document.
    /// - Parameter transaction: A transaction from the parent document.
    public func destroy(in transaction: YrsTransaction) {
        document.destroy(parentTxn: transaction)
    }

    /// Destroys a root document, invalidating native observers and undo tracking.
    /// Subdocuments must instead use `destroy(in:)` with their parent's transaction.
    public func destroyAsync() async throws {
        try document.destroyRoot()
    }

    // MARK: - Subdocument Observation

    /// Observes lifecycle events under a key in this document's transaction.
    /// Registering the same key replaces its previous callback.
    public func observeSubdocs(key: String, transaction: YrsTransaction, _ body: @escaping @Sendable (YSubdocsEvent) -> Void) {
        document.observeSubdocs(tx: transaction, key: key, delegate: YSubdocsObservationDelegateWrapper(callback: body))
    }

    /// Removes a lifecycle observer in a transaction after event delivery has finished.
    @discardableResult
    public func unobserveSubdocs(key: String, transaction: YrsTransaction) -> Bool {
        document.unobserveSubdocs(tx: transaction, key: key)
    }

    /// Returns a standard async stream of subdocument lifecycle events.
    public func observeSubdocsAsync() async -> AsyncStream<YSubdocsEvent> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<YSubdocsEvent>.makeStream(bufferingPolicy: .unbounded)
        transact { transaction in
            self.observeSubdocs(key: key, transaction: transaction) { continuation.yield($0) }
        }
        continuation.onTermination = { _ in
            Task {
                await self.transact { transaction in
                    self.unobserveSubdocs(key: key, transaction: transaction)
                }
            }
        }
        return stream
    }

    /// Observes destruction under a key in this document's transaction.
    public func observeDestroy(key: String, transaction: YrsTransaction, _ body: @escaping @Sendable () -> Void) {
        document.observeDestroy(tx: transaction, key: key, delegate: YDestroyObservationDelegateWrapper(callback: body))
    }

    /// Removes a destroy observer in a transaction after event delivery has finished.
    @discardableResult
    public func unobserveDestroy(key: String, transaction: YrsTransaction) -> Bool {
        document.unobserveDestroy(tx: transaction, key: key)
    }

    /// Returns a standard async stream that emits once when this document is destroyed.
    public func observeDestroyAsync() async -> AsyncStream<Void> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
        transact { transaction in
            self.observeDestroy(key: key, transaction: transaction) {
                continuation.yield(())
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in
            Task {
                await self.transact { transaction in
                    self.unobserveDestroy(key: key, transaction: transaction)
                }
            }
        }
        return stream
    }

    // MARK: - Subdocument Queries (Async)

    /// Returns the GUIDs of all subdocuments in this document asynchronously.
    /// - Returns: An array of subdocument GUIDs.
    public func subdocGuidsAsync() async -> [String] {
        transact { $0.subdocGuids() }
    }

    /// Returns all subdocuments in this document asynchronously.
    /// - Returns: An array of subdocuments.
    public func subdocsAsync() async -> [YDocument] {
        transact { txn in
            txn.subdocs().map { YDocument(wrapping: $0) }
        }
    }

    // MARK: - Subdocument Queries (With Explicit Transaction)

    /// Returns the GUIDs of all subdocuments using an existing transaction.
    /// - Parameter transaction: The transaction to use.
    /// - Returns: An array of subdocument GUIDs.
    public func subdocGuids(transaction: YrsTransaction) -> [String] {
        transaction.subdocGuids()
    }

    /// Returns all subdocuments using an existing transaction.
    /// - Parameter transaction: The transaction to use.
    /// - Returns: An array of subdocuments.
    public func subdocs(transaction: YrsTransaction) -> [YDocument] {
        transaction.subdocs().map { YDocument(wrapping: $0) }
    }

    // MARK: - Subdocument Queries (Actor-isolated)

    /// Returns the GUIDs of all subdocuments in this document.
    public func subdocGuids(transaction: YrsTransaction? = nil) -> [String] {
        if let transaction = transaction {
            return transaction.subdocGuids()
        } else {
            return transactSync { $0.subdocGuids() }
        }
    }

    /// Returns all subdocuments in this document.
    public func subdocs(transaction: YrsTransaction? = nil) -> [YDocument] {
        if let transaction = transaction {
            return transaction.subdocs().map { YDocument(wrapping: $0) }
        } else {
            return transactSync { txn in
                txn.subdocs().map { YDocument(wrapping: $0) }
            }
        }
    }

    /// Compares the state vector from another YSwift document to return a data buffer you can use to synchronize with another YSwift document.
    ///
    /// Use `transactionStateVector()` on a transaction to get a state buffer to compare with this method.
    ///
    /// - Parameters:
    ///   - txn: A transaction within which to compare the state of the document.
    ///   - state: A data buffer from another YSwift document.
    /// - Returns: A buffer that contains the diff you can use to synchronize another YSwift document.
    public func diff(txn: YrsTransaction, from state: [UInt8] = []) -> [UInt8] {
        try! document.encodeDiffV1(tx: txn, stateVector: state)
    }

    /// Runs a complete transaction without suspension on the YSwift actor.
    /// The transaction cannot cross an actor boundary; return owned Sendable values.
    public func transact<T: Sendable>(
        origin: Origin? = nil,
        _ changes: @YSwiftActor @Sendable (YrsTransaction) throws -> T
    ) rethrows -> T {
        let transaction = document.transact(origin: origin?.origin)
        defer { transaction.free() }
        return try changes(transaction)
    }

    /// Synchronous convenience for code already running on the YSwift actor.
    public func transactSync<T>(origin: Origin? = nil, _ changes: (YrsTransaction) throws -> T) rethrows -> T {
        let transaction = document.transact(origin: origin?.origin)
        defer { transaction.free() }
        return try changes(transaction)
    }

    // MARK: - Factory methods

    /// Retrieves or creates a Text shared data type.
    /// - Parameter named: The key you use to reference the Text shared data type.
    /// - Returns: The text shared type.
    public func getOrCreateText(named: String) -> YText {
        YText(text: document.getText(name: named), document: self)
    }

    /// Retrieves or creates an Array shared data type.
    /// - Parameter named: The key you use to reference the Array shared data type.
    /// - Returns: The array shared type.
    public func getOrCreateArray<T: Codable & Sendable>(named: String) -> YArray<T> {
        YArray(array: document.getArray(name: named), document: self)
    }

    /// Retrieves or creates a Map shared data type.
    /// - Parameter named: The key you use to reference the Map shared data type.
    /// - Returns: The map shared type.
    public func getOrCreateMap<T: Codable & Sendable>(named: String) -> YMap<T> {
        YMap(map: document.getMap(name: named), document: self)
    }

    /// Creates an undo manager whose collections may belong to different documents.
    /// Supply a timestamp closure to control capture grouping in tests.
    public func undoManager(
        captureTimeoutMilliseconds: UInt64 = 500,
        trackedRefs: [any YCollection],
        timestamp: (@Sendable () -> UInt64)? = nil
    ) throws -> YUndoManager {
        let manager = YrsUndoManager(captureTimeoutMillis: captureTimeoutMilliseconds, clock: timestamp.map(YUndoClockDelegate.init))
        for collection in trackedRefs {
            try manager.addScope(doc: collection.document.document, trackedRef: collection.pointer())
        }
        return YUndoManager(manager: manager)
    }

    /// Creates and registers an undo manager on the YSwift actor.
    public func undoManagerAsync(
        captureTimeoutMilliseconds: UInt64 = 500,
        trackedRefs: [any YCollection],
        timestamp: (@Sendable () -> UInt64)? = nil
    ) async throws -> YUndoManager {
        try undoManager(captureTimeoutMilliseconds: captureTimeoutMilliseconds, trackedRefs: trackedRefs, timestamp: timestamp)
    }

    // MARK: - JSON Path Queries (Async)

    /// Queries the document using JSON path syntax asynchronously.
    ///
    /// JSON path allows you to query nested document structures. Examples:
    /// - `$.users` - Get the "users" root-level collection
    /// - `$.users[0]` - Get the first user
    /// - `$.users[*].name` - Get all user names
    /// - `$..name` - Recursively find all "name" fields
    ///
    /// - Parameters:
    ///   - path: A JSON path expression (e.g., "$.users[*].name")
    /// - Returns: An array of JSON-encoded strings representing matching values.
    /// - Throws: `YrsJsonPathError` if the path expression is invalid.
    public func queryAsync(_ path: String) async throws -> [String] {
        try transact { txn in
            try txn.jsonPath(path: path)
        }
    }

    /// Queries the document using JSON path syntax with an existing transaction.
    ///
    /// - Parameters:
    ///   - path: A JSON path expression (e.g., "$.users[*].name")
    ///   - transaction: The transaction to use.
    /// - Returns: An array of JSON-encoded strings representing matching values.
    /// - Throws: `YrsJsonPathError` if the path expression is invalid.
    public func query(_ path: String, transaction: YrsTransaction) throws -> [String] {
        try transaction.jsonPath(path: path)
    }

    // MARK: - JSON Path Queries (Actor-isolated)

    /// Queries the document using JSON path syntax.
    public func query(_ path: String, transaction: YrsTransaction? = nil) throws -> [String] {
        if let transaction = transaction {
            return try transaction.jsonPath(path: path)
        } else {
            var result: Result<[String], Error>?
            transactSync { txn in
                do {
                    result = .success(try txn.jsonPath(path: path))
                } catch {
                    result = .failure(error)
                }
            }
            return try result!.get()
        }
    }
}
