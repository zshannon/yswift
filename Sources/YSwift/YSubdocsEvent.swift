import Yniffi

/// A lifecycle event with actor-isolated document handles.
public struct YSubdocsEvent: Sendable {
    private let nativeEvent: @YSwiftActor () -> YrsSubdocsEvent

    @YSwiftActor public var added: [YDocument] {
        nativeEvent().added.map { YDocument(wrapping: $0) }
    }
    @YSwiftActor public var loaded: [YDocument] {
        nativeEvent().loaded.map { YDocument(wrapping: $0) }
    }
    @YSwiftActor public var removed: [YDocument] {
        nativeEvent().removed.map { YDocument(wrapping: $0) }
    }

    init(from event: sending YrsSubdocsEvent) {
        nativeEvent = { @YSwiftActor in event }
    }
}

final class YSubdocsObservationDelegateWrapper: YrsSubdocsObservationDelegate {
    private let callback: @Sendable (YSubdocsEvent) -> Void
    init(callback: @escaping @Sendable (YSubdocsEvent) -> Void) { self.callback = callback }

    func call(event: sending YrsSubdocsEvent) {
        callback(YSubdocsEvent(from: event))
    }
}

final class YDestroyObservationDelegateWrapper: YrsDestroyObservationDelegate {
    private let callback: @Sendable () -> Void
    init(callback: @escaping @Sendable () -> Void) { self.callback = callback }
    func call() { callback() }
}
