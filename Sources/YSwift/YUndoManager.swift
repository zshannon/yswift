import Foundation
import Yniffi

/// Tracks reversible changes across documents on the same actor as document transactions.
/// Observers receive owned values and cannot synchronously reenter document mutation.
@YSwiftActor
public final class YUndoManager {
    private let manager: YrsUndoManager

    init(manager: YrsUndoManager) { self.manager = manager }

    public func addOrigin(_ origin: Origin) throws -> Void {
        try manager.addOrigin(origin: origin.origin)
    }

    public func addOriginAsync(_ origin: Origin) async throws -> Void {
        try manager.addOrigin(origin: origin.origin)
    }

    public func removeOrigin(_ origin: Origin) throws -> Void {
        try manager.removeOrigin(origin: origin.origin)
    }

    public func removeOriginAsync(_ origin: Origin) async throws -> Void {
        try manager.removeOrigin(origin: origin.origin)
    }

    public func track(_ collection: any YCollection) throws -> Void {
        try manager.addScope(doc: collection.document.document, trackedRef: collection.pointer())
    }

    public func trackAsync(_ collection: any YCollection) async throws -> Void {
        try manager.addScope(doc: collection.document.document, trackedRef: collection.pointer())
    }

    public func undo() throws -> Bool {
        try manager.undo()
    }

    public func undoAsync() async throws -> Bool {
        try manager.undo()
    }

    public func redo() throws -> Bool {
        try manager.redo()
    }

    public func redoAsync() async throws -> Bool {
        try manager.redo()
    }

    public func wrap() throws -> Void {
        try manager.wrapChanges()
    }

    public func wrapAsync() async throws -> Void {
        try manager.wrapChanges()
    }

    public func clear() throws -> Void {
        try manager.clear()
    }

    public func clearAsync() async throws -> Void {
        try manager.clear()
    }

    public func clearUndo() throws -> Void {
        try manager.clearUndo()
    }

    public func clearUndoAsync() async throws -> Void {
        try manager.clearUndo()
    }

    public func clearRedo() throws -> Void {
        try manager.clearRedo()
    }

    public func clearRedoAsync() async throws -> Void {
        try manager.clearRedo()
    }

    public func state() throws -> YUndoState {
        YUndoState(try manager.state())
    }

    public func stateAsync() async throws -> YUndoState {
        YUndoState(try manager.state())
    }

    public func observeAdded(key: String, _ body: @escaping @Sendable (UndoEvent, Data?) -> Data?) throws {
        try manager.observeAdded(key: key, delegate: YUndoManagerObservationDelegate(callback: body))
    }

    @discardableResult
    public func unobserveAdded(key: String) throws -> Bool {
        try manager.unobserveAdded(key: key)
    }

    /// Registers before returning and yields owned snapshots through a standard AsyncStream.
    public func observeAddedAsync() async throws -> AsyncStream<UndoEvent> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<UndoEvent>.makeStream()
        try observeAdded(key: key) { event, metadata in
            continuation.yield(event)
            return metadata
        }
        continuation.onTermination = { [self] _ in
            Task { _ = try? await self.unobserveAdded(key: key) }
        }
        return stream
    }

    public func observeUpdated(key: String, _ body: @escaping @Sendable (UndoEvent, Data?) -> Data?) throws {
        try manager.observeUpdated(key: key, delegate: YUndoManagerObservationDelegate(callback: body))
    }

    @discardableResult
    public func unobserveUpdated(key: String) throws -> Bool {
        try manager.unobserveUpdated(key: key)
    }

    /// Registers before returning and yields owned snapshots through a standard AsyncStream.
    public func observeUpdatedAsync() async throws -> AsyncStream<UndoEvent> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<UndoEvent>.makeStream()
        try observeUpdated(key: key) { event, metadata in
            continuation.yield(event)
            return metadata
        }
        continuation.onTermination = { [self] _ in
            Task { _ = try? await self.unobserveUpdated(key: key) }
        }
        return stream
    }

    public func observePopped(key: String, _ body: @escaping @Sendable (UndoEvent, Data?) -> Data?) throws {
        try manager.observePopped(key: key, delegate: YUndoManagerObservationDelegate(callback: body))
    }

    @discardableResult
    public func unobservePopped(key: String) throws -> Bool {
        try manager.unobservePopped(key: key)
    }

    /// Registers before returning and yields owned snapshots through a standard AsyncStream.
    public func observePoppedAsync() async throws -> AsyncStream<UndoEvent> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<UndoEvent>.makeStream()
        try observePopped(key: key) { event, metadata in
            continuation.yield(event)
            return metadata
        }
        continuation.onTermination = { [self] _ in
            Task { _ = try? await self.unobservePopped(key: key) }
        }
        return stream
    }

    public func observeCleared(key: String, _ body: @escaping @Sendable (YUndoClearedEvent) -> Void) throws {
        try manager.observeCleared(key: key, delegate: YUndoClearedDelegate(callback: body))
    }

    @discardableResult
    public func unobserveCleared(key: String) throws -> Bool { try manager.unobserveCleared(key: key) }

    public func observeClearedAsync() async throws -> AsyncStream<YUndoClearedEvent> {
        let key = UUID().uuidString
        let (stream, continuation) = AsyncStream<YUndoClearedEvent>.makeStream()
        try observeCleared(key: key) { continuation.yield($0) }
        continuation.onTermination = { [self] _ in
            Task { _ = try? await self.unobserveCleared(key: key) }
        }
        return stream
    }
}

/// A stable snapshot that remains valid after its native callback returns.
public struct UndoEvent: Sendable {
    public enum Kind: Sendable { case undo, redo }

    public let documentGuid: String
    public let origin: Origin?
    public let type: Kind
    private let changedRefs: Set<UInt64>

    init(_ event: YrsUndoEvent) {
        documentGuid = event.documentGuid()
        origin = event.origin().map(Origin.init)
        type = event.kind() == .undo ? .undo : .redo
        changedRefs = Set(event.changedRefs())
    }

    /// Whether this event includes the collection or one of its descendants.
    @YSwiftActor public func hasChanged(_ collection: any YCollection) -> Bool {
        documentGuid == collection.document.guid && changedRefs.contains(collection.pointer())
    }
}

public struct YUndoState: Sendable {
    public let documentGuids: [String]
    public let redoCount: UInt64
    public let undoCount: UInt64

    public var canRedo: Bool { redoCount > 0 }
    public var canUndo: Bool { undoCount > 0 }

    init(_ state: YrsUndoState) {
        documentGuids = state.documentGuids
        redoCount = state.redoCount
        undoCount = state.undoCount
    }
}

public struct YUndoClearedEvent: Equatable, Sendable {
    public let redoCleared: Bool
    public let undoCleared: Bool
}

final class YUndoClockDelegate: YrsUndoClock {
    private let timestamp: @Sendable () -> UInt64

    init(timestamp: @escaping @Sendable () -> UInt64) { self.timestamp = timestamp }
    func now() -> UInt64 { timestamp() }
}

private final class YUndoClearedDelegate: YrsUndoClearedDelegate {
    private let callback: @Sendable (YUndoClearedEvent) -> Void

    init(callback: @escaping @Sendable (YUndoClearedEvent) -> Void) { self.callback = callback }
    func call(undoCleared: Bool, redoCleared: Bool) {
        callback(YUndoClearedEvent(redoCleared: redoCleared, undoCleared: undoCleared))
    }
}

private final class YUndoManagerObservationDelegate: YrsUndoManagerObservationDelegate {
    private let callback: @Sendable (UndoEvent, Data?) -> Data?

    init(callback: @escaping @Sendable (UndoEvent, Data?) -> Data?) { self.callback = callback }

    func call(e: YrsUndoEvent, metadata: [UInt8]?) -> [UInt8]? {
        callback(UndoEvent(e), metadata.map { Data($0) }).map { Array($0) }
    }
}
