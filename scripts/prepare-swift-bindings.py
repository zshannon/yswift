#!/usr/bin/env python3
"""Apply checked Swift 6 ownership to the pinned UniFFI 0.27 generated bridge.

UniFFI's foreign pointer cell retains callback table pointers for the process
lifetime. Each table is allocated once and stays immutable after registration.
Callback handles use the standard-library Mutex; callbacks must be Sendable.
Fail on generator drift instead of silently emitting an unchecked bridge.
"""
from pathlib import Path
import re

path = Path(__file__).resolve().parents[1] / "lib/swift/scaffold/yniffi.swift"
source = path.read_text()
old = "func call(event: YrsSubdocsEvent)"
assert source.count(old) == 1, "Expected one owned subdocument callback"
source = source.replace(old, "func call(event: sending YrsSubdocsEvent)")
# The generic lift result is conservatively connected to its RustBuffer argument.
# Reading from copied Swift Data creates fresh wrappers with disconnected ownership.
event_converter = "public struct FfiConverterTypeYrsSubdocsEvent: FfiConverterRustBuffer {"
assert source.count(event_converter) == 1, "Expected one subdocument event converter"
source = source.replace(event_converter, event_converter + '''
    public static func lift(_ buf: RustBuffer) throws -> sending YrsSubdocsEvent {
        defer { buf.deallocate() }
        var reader = createReader(data: Data(rustBuffer: buf))
        let value = try read(from: &reader)
        if hasRemaining(reader) {
            throw UniffiInternalError.incompleteData
        }
        return value
    }
''')
source = source.replace("import Foundation", "import Foundation\nimport Synchronization", 1)
start = source.index("private class UniffiHandleMap<T> {")
end = source.index("// Public interface members begin here.", start)
source = source[:start] + '''private final class UniffiHandleMap<T: Sendable>: Sendable {
    private let state = Mutex((nextHandle: UInt64(1), values: [UInt64: T]()))

    func insert(obj: T) -> UInt64 {
        state.withLock { state in
            let handle = state.nextHandle
            state.nextHandle += 1
            state.values[handle] = obj
            return handle
        }
    }

    func get(handle: UInt64) throws -> T {
        try state.withLock { state in
            guard let value = state.values[handle] else {
                throw UniffiInternalError.unexpectedStaleHandle
            }
            return value
        }
    }

    @discardableResult
    func remove(handle: UInt64) throws -> T {
        try state.withLock { state in
            guard let value = state.values.removeValue(forKey: handle) else {
                throw UniffiInternalError.unexpectedStaleHandle
            }
            return value
        }
    }

    var count: Int { state.withLock { $0.values.count } }
}

''' + source[end:]
source = re.sub(r"(public protocol Yrs\w+(?:Delegate|Clock)): AnyObject", r"\1: AnyObject, Sendable", source)
source = source.replace("fileprivate static var handleMap", "fileprivate static let handleMap")
pattern = re.compile(
    r"private enum (UniffiCallbackInterface\w+) \{\n"
    r".*?    static var vtable: (\w+) = (\.init\(.*?)\n    \)\n\}\n\n"
    r"private func (uniffiCallbackInit\w+)\(\) \{\n"
    r"    (\w+)\(&\1.vtable\)\n\}", re.S)

def table(match):
    enum, typ, initializer, function, register = match.groups()
    return f'''private enum {enum} {{
    // Rust retains this immutable callback table for the lifetime of the process.
    static let initialized: Void = {{
        let table = UnsafeMutablePointer<{typ}>.allocate(capacity: 1)
        table.initialize(to: {initializer}
        ))
        {register}(table)
    }}()
}}

private func {function}() {{
    _ = {enum}.initialized
}}'''

source, count = pattern.subn(table, source)
assert count > 0, "No generated callback tables matched"
assert "static var vtable" not in source, "Unconverted callback table"
# Generated version checks and callback registration must execute once.
source = source.replace("private var initializationResult: InitializationResult {", "private let initializationResult: InitializationResult = {")
source = source.replace("    return InitializationResult.ok\n}\n\nprivate func uniffiEnsureInitialized", "    return InitializationResult.ok\n}()\n\nprivate func uniffiEnsureInitialized")
assert "@unchecked" not in source and "@preconcurrency" not in source
path.write_text(source)
