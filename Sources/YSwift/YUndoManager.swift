import Foundation
@preconcurrency import Yniffi

/// An undo manager to track and reverse changes on YSwift collections.
///
/// The manager can be released during document transactions or observer callbacks.
/// Destruction cancels its observers without acquiring a document transaction;
/// native state stays alive until an already-running callback returns.
///
/// Set the one or more origins to track with ``addOrigin(_:)``.
/// If no origins are set, the undo manager tracks changes from any origin.
public final class YUndoManager<T: AnyObject> {
    private let _manager: YrsUndoManager

    init(manager: YrsUndoManager) {
        _manager = manager
    }

    /// Adds an origin that the Undo manager tracks.
    /// - Parameter origin: The origin to track.
    public func addOrigin(_ origin: Origin) {
        _manager.addOrigin(origin: origin.origin)
    }

    /// Removes an origin that the Undo manager tracks.
    /// - Parameter origin: The origin to remove from tracking.
    public func removeOrigin(_ origin: Origin) {
        _manager.removeOrigin(origin: origin.origin)
    }

    /// Adds another collection to track with the Undo manager
    /// - Parameter collection: The collection to track.
    public func track(_ collection: YCollection) {
        _manager.addScope(trackedRef: collection.pointer())
    }

    /// Undo a change on a collection you're tracking back to the last point you set
    ///
    /// Set a point to undo back to with ``wrap()``.
    /// Additional calls will undo to points further back on the stack, if set.
    /// - Returns: A Boolean value that indicates wether the change was undone.
    public func undo() throws -> Bool {
        return try _manager.undo()
    }

    /// Replays a change forward from the Undo managers stack.
    /// - Returns: A Boolean value that indicates wether the change was replayed.
    public func redo() throws -> Bool {
        return try _manager.redo()
    }

    /// Mark a point in time that you want to be able to reverse back to.
    ///
    /// The Undo Manager tracks the points you set in a stack.
    /// Undo the to the most recent point set using ``undo()``.
    public func wrap() {
        _manager.wrapChanges()
    }

    /// Clears the stack of undo/redo actions.
    public func clear() throws {
        try _manager.clear()
    }
    
    /// Registers an undo added callback under a key, replacing an existing callback with that key.
    /// Call outside document transactions and undo callbacks.
    public func observeAdded(key: String, _ body: @escaping (UndoEvent, T?) -> T?) throws {
        let delegate = YUndoManagerObservationDelegate(callback: body)
        try _manager.observeAdded(key: key, delegate: delegate)
    }

    /// Removes an undo added callback. Throws if a transaction or undo callback is active.
    @discardableResult
    public func unobserveAdded(key: String) throws -> Bool {
        try _manager.unobserveAdded(key: key)
    }

    /// Registers an undo updated callback under a key, replacing an existing callback with that key.
    /// Call outside document transactions and undo callbacks.
    public func observeUpdated(key: String, _ body: @escaping (UndoEvent, T?) -> T?) throws {
        let delegate = YUndoManagerObservationDelegate(callback: body)
        try _manager.observeUpdated(key: key, delegate: delegate)
    }

    /// Removes an undo updated callback. Throws if a transaction or undo callback is active.
    @discardableResult
    public func unobserveUpdated(key: String) throws -> Bool {
        try _manager.unobserveUpdated(key: key)
    }

    /// Registers an undo popped callback under a key, replacing an existing callback with that key.
    /// Call outside document transactions and undo callbacks.
    public func observePopped(key: String, _ body: @escaping (UndoEvent, T?) -> T?) throws {
        let delegate = YUndoManagerObservationDelegate(callback: body)
        try _manager.observePopped(key: key, delegate: delegate)
    }

    /// Removes an undo popped callback. Throws if a transaction or undo callback is active.
    @discardableResult
    public func unobservePopped(key: String) throws -> Bool {
        try _manager.unobservePopped(key: key)
    }
}

class YUndoManagerObservationDelegate<T: AnyObject>: YrsUndoManagerObservationDelegate {
    private var callback: (YrsUndoEvent, UInt64) -> UInt64

    init(callback: @escaping (UndoEvent, T?) -> T?) {
        self.callback = { (event: YrsUndoEvent, ptr: UInt64) -> UInt64 in
            let obj = callback(UndoEvent(event), YUndoManagerObservationDelegate.bridge(ptr: ptr))
            return YUndoManagerObservationDelegate.bridge(obj: obj)
        }
    }

    func call(e: Yniffi.YrsUndoEvent, ptr: UInt64) -> UInt64 {
        return callback(e, ptr)
    }

    static func bridge(obj: T?) -> UInt64 {
        if let obj {
            let ptr = UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
            return UInt64(bitPattern: Int64(Int(bitPattern: ptr)))
        } else {
            return UInt64(bitPattern: Int64(Int(bitPattern: nil)))
        }
    }

    static func bridge(ptr: UInt64) -> T? {
        let unsafe_ptr = UnsafeRawPointer(bitPattern: Int(ptr))
        if let unsafe_ptr {
            return Unmanaged.fromOpaque(unsafe_ptr).takeRetainedValue()
        } else {
            return nil
        }
    }
}

/// Metadata about an undo event
public struct UndoEvent {
    let event: YrsUndoEvent
    init(_ event: YrsUndoEvent) {
        self.event = event
    }
    
    /// The type of undo event.
    public var type: YrsUndoEventKind {
        return event.kind()
    }
    
    /// The origin of the set of changes.
    public var origin: Origin? {
        let origin = event.origin()
        if let origin {
            return Origin(origin)
        } else {
            return nil
        }
    }
    
    /// <#Description#>
    /// - Parameter sharedRef: <#sharedRef description#>
    /// - Returns: <#description#>
    public func hasChanged<T: YCollection>(_ sharedRef: T) -> Bool {
        return event.hasChanged(sharedRef: sharedRef.pointer())
    }
}
