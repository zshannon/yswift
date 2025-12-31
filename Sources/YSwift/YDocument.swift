import Combine
import Foundation
import Yniffi

/// YDocument holds YSwift shared data types and coordinates collaboration and changes.
public final class YDocument {
    let document: YrsDoc
    /// Multiple `YDocument` instances are supported. Because `label` is required only for debugging purposes.
    /// It is not used for unique differentiation between queues. So we safely get unique queue for each `YDocument` instance.
    private let transactionQueue = DispatchQueue(label: "YSwift.YDocument", qos: .userInitiated)

    /// Create a new YSwift Document.
    public init() {
        document = YrsDoc()
    }

    /// Create a new YSwift Document with custom options.
    /// - Parameter options: Configuration options for the document.
    public init(options: YDocumentOptions) {
        document = YrsDoc.newWithOptions(options: options.yrsOptions)
    }

    /// Internal initializer for wrapping a YrsDoc (used when retrieving subdocuments).
    internal init(wrapping doc: YrsDoc) {
        document = doc
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

    // MARK: - Subdocument Observation

    /// Registers a closure that is called when subdocuments are added, loaded, or removed.
    /// - Parameter body: A closure that receives the subdocs event.
    /// - Returns: A subscription that can be used to cancel the observation.
    public func observeSubdocs(_ body: @escaping (YSubdocsEvent) -> Void) -> YSubscription {
        let delegate = YSubdocsObservationDelegateWrapper(callback: body)
        return YSubscription(subscription: document.observeSubdocs(delegate: delegate))
    }

    /// Returns a publisher that emits subdocument lifecycle events.
    public func observeSubdocs() -> AnyPublisher<YSubdocsEvent, Never> {
        let subject = PassthroughSubject<YSubdocsEvent, Never>()
        let subscription = observeSubdocs { subject.send($0) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    /// Registers a closure that is called when this document is destroyed.
    /// - Parameter body: A closure that is called when the document is destroyed.
    /// - Returns: A subscription that can be used to cancel the observation.
    public func observeDestroy(_ body: @escaping () -> Void) -> YSubscription {
        let delegate = YDestroyObservationDelegateWrapper(callback: body)
        return YSubscription(subscription: document.observeDestroy(delegate: delegate))
    }

    /// Returns a publisher that emits when this document is destroyed.
    public func observeDestroy() -> AnyPublisher<Void, Never> {
        let subject = PassthroughSubject<Void, Never>()
        let subscription = observeDestroy { subject.send(()) }
        return subject.handleEvents(receiveCancel: {
            subscription.cancel()
        })
        .eraseToAnyPublisher()
    }

    // MARK: - Subdocument Queries

    /// Returns the GUIDs of all subdocuments in this document.
    /// - Parameter transaction: An optional transaction to use. If not provided, a new one is created.
    /// - Returns: An array of subdocument GUIDs.
    public func subdocGuids(transaction: YrsTransaction? = nil) -> [String] {
        if let transaction = transaction {
            return transaction.subdocGuids()
        } else {
            return transactSync { $0.subdocGuids() }
        }
    }

    /// Returns all subdocuments in this document.
    /// - Parameter transaction: An optional transaction to use. If not provided, a new one is created.
    /// - Returns: An array of subdocuments.
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

    // MARK: - Transaction methods

    /// Creates a synchronous transaction and provides that transaction to a trailing closure, within which you make changes to shared data types.
    /// - Parameter changes: The closure in which you make changes to the document.
    /// - Returns: The value that you return from the closure.
    public func transactSync<T>(origin: Origin? = nil, _ changes: @escaping (YrsTransaction) -> T) -> T {
        // Avoiding deadlocks & thread explosion. We do not allow re-entrancy in Transaction methods.
        // It is a programmer's error to invoke synchronous transact from within transaction.
        // Better approach would be to leverage something like `DispatchSpecificKey` in Watchdog style implementation
        // Reference: https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/SchedulingWatchdog.swift
        dispatchPrecondition(condition: .notOnQueue(transactionQueue))
        return transactionQueue.sync {
            let transaction = document.transact(origin: origin?.origin)
            defer {
                transaction.free()
            }
            return changes(transaction)
        }
    }

    /// Creates an asynchronous transaction and provides that transaction to a trailing closure, within which you make changes to shared data types.
    /// - Parameter changes: The closure in which you make changes to the document.
    /// - Returns: The value that you return from the closure.
    public func transact<T>(origin: Origin? = nil, _ changes: @escaping (YrsTransaction) -> T) async -> T {
        await withCheckedContinuation { continuation in
            transactAsync(origin, changes) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Creates an asynchronous transaction and provides that transaction to a trailing closure, within which you make changes to shared data types.
    /// - Parameter changes: The closure in which you make changes to the document.
    /// - Parameter completion: A completion handler that is called with the value returned from the closure in which you made changes.
    public func transactAsync<T>(_ origin: Origin? = nil, _ changes: @escaping (YrsTransaction) -> T, completion: @escaping (T) -> Void) {
        transactionQueue.async { [weak self] in
            guard let self = self else { return }
            let transaction = self.document.transact(origin: origin?.origin)
            defer {
                transaction.free()
            }
            let result = changes(transaction)
            completion(result)
        }
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
    public func getOrCreateArray<T: Codable>(named: String) -> YArray<T> {
        YArray(array: document.getArray(name: named), document: self)
    }

    /// Retrieves or creates a Map shared data type.
    /// - Parameter named: The key you use to reference the Map shared data type.
    /// - Returns: The map shared type.
    public func getOrCreateMap<T: Codable>(named: String) -> YMap<T> {
        YMap(map: document.getMap(name: named), document: self)
    }

    /// Creates an Undo Manager for a document with the collections that is tracks.
    /// - Parameter trackedRefs: The collections to track to undo and redo changes.
    /// - Returns: A reference to the undo manager to control those actions.
    public func undoManager<T: AnyObject>(trackedRefs: [YCollection]) -> YUndoManager<T> {
        let mapped = trackedRefs.map { $0.pointer() }
        return YUndoManager(manager: document.undoManager(trackedRefs: mapped))
    }

    // MARK: - JSON Path Queries

    /// Queries the document using JSON path syntax.
    ///
    /// JSON path allows you to query nested document structures. Examples:
    /// - `$.users` - Get the "users" root-level collection
    /// - `$.users[0]` - Get the first user
    /// - `$.users[*].name` - Get all user names
    /// - `$..name` - Recursively find all "name" fields
    ///
    /// - Parameters:
    ///   - path: A JSON path expression (e.g., "$.users[*].name")
    ///   - transaction: An optional transaction to use. If not provided, a new one is created.
    /// - Returns: An array of JSON-encoded strings representing matching values.
    /// - Throws: `YrsJsonPathError` if the path expression is invalid.
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
