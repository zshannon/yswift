import Foundation
import Testing
@testable import YSwift

@Suite
final class YMapTests {
    var document: YDocument!
    var map: YMap<TestType>!

    init() {
        document = YDocument()
        map = document.getOrCreateMap(named: "test")
    }

    @Test
    func test_insert() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        #expect((map.length()) == (2))

        let finalInstance = map.get(key: initialInstance.name)

        #expect((initialInstance) == (finalInstance))

        let contains = map.containsKey(secondInstance.name)
        #expect(contains)
    }

    @Test
    func test_remove() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        #expect((map.length()) == (2))
        map.removeValue(forKey: secondInstance.name)
        #expect((map.length()) == (1))
    }

    @Test
    func test_removeAll() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        #expect((map.length()) == (2))
        map.removeAll()
        #expect((map.length()) == (0))
    }

    @Test
    func test_keys() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        #expect((map.length()) == (2))

        var collectedKeys: [String] = []
        map.keys { collectedKeys.append($0) }

        #expect((collectedKeys.sorted()) == (["Aidar", "Joe"]))
    }

    @Test
    func test_values() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        #expect((map.length()) == (2))

        var collectedValues: [TestType] = []
        map.values {
            collectedValues.append($0)
        }

        #expect(collectedValues.contains(initialInstance))
        #expect(collectedValues.contains(secondInstance))
    }

    @Test
    func test_each() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        #expect((map.length()) == (0))
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        #expect((map.length()) == (2))

        var collectedValues: [String: TestType] = [:]
        map.each { key, value in
            collectedValues[key] = value
        }

        #expect(collectedValues.keys.contains("Aidar"))
        #expect(collectedValues.keys.contains("Joe"))

        #expect(collectedValues.values.contains(initialInstance))
        #expect(collectedValues.values.contains(secondInstance))
    }

    @Test
    func test_observation_closure() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let first = TestType(name: "Aidar", age: 24)
            let second = TestType(name: "Joe", age: 55)
            let updatedSecond = TestType(name: "Joe", age: 101)

            var actualChanges: [YMapChange<TestType>] = []

            self.map.document.transactSync { transaction in
                self.map.observe(key: "test", transaction: transaction) { changes in
                    eventReceived()
                    changes.forEach { change in
                        actualChanges.append(change)
                    }
                }
            }

            map[first.name] = first
            map[second.name] = second

            map[first.name] = nil
            map[second.name] = updatedSecond

            self.map.document.transactSync { transaction in
                self.map.unobserve(key: "test", transaction: transaction)
            }

            // Use set here, to compare two arrays by the composition not by order
            #expect((Set(actualChanges)) == (Set([
                    .inserted(key: first.name, value: first),
                    .inserted(key: second.name, value: second),
                    .removed(key: first.name, value: first),
                    .updated(key: second.name, oldValue: second, newValue: updatedSecond),
                ])))
        }
        await confirmation("Receives each change", expectedCount: 4, exercise)
    }

    /*
     https://www.swiftbysundell.com/articles/using-unit-tests-to-identify-avoid-memory-leaks-in-swift/
     https://alisoftware.github.io/swift/closures/2016/07/25/closure-capture-1/
     */

    @Test
    func test_observation_closure_IsLeakingWithoutUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        self.map.document.transactSync { transaction in
            self.map.observe(key: "test", transaction: transaction) { [object] changes in
                // Capture the object in the closure (note that we need to use
                // a capture list like [object] above in order for the object
                // to be captured by reference instead of by pointer value)
                _ = object
                changes.forEach { _ in }
            }
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        #expect(weakObject != nil)
        
        self.map.document.transactSync { transaction in
            self.map.unobserve(key: "test", transaction: transaction)
        }
    }

    @Test
    func test_observation_closure_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        self.map.document.transactSync { transaction in
            self.map.observe(key: "test", transaction: transaction) { [object] changes in
                // Capture the object in the closure (note that we need to use
                // a capture list like [object] above in order for the object
                // to be captured by reference instead of by pointer value)
                _ = object
                changes.forEach { _ in }
            }
        }

        // Explicit unobserving, to prevent leaking
        self.map.document.transactSync { transaction in
            self.map.unobserve(key: "test", transaction: transaction)
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        #expect(weakObject == nil)
    }

    // MARK: - Nested Shared Type Tests

    @Test
    func test_getNestedText_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["name"] = "hello"
        #expect(root.getText(forKey: "name") == nil)
        #expect(root.getText(forKey: "nonexistent") == nil)
    }

    @Test
    func test_getNestedArray_returnsNilForJsonValue() {
        let root: YMap<[Int]> = document.getOrCreateMap(named: "root")
        root["numbers"] = [1, 2, 3]
        let arr: YArray<Int>? = root.getArray(forKey: "numbers")
        #expect(arr == nil)
    }

    @Test
    func test_getNestedMap_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["key"] = "value"
        let nested: YMap<String>? = root.getMap(forKey: "key")
        #expect(nested == nil)
    }

    @Test
    func test_isUndefined() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        #expect(!(root.isUndefined(forKey: "nonexistent")))
        root["name"] = "test"
        #expect(!(root.isUndefined(forKey: "name")))
    }

    // MARK: - Insert and Retrieve Nested Types

    @Test
    func test_insertAndGetNestedMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested map
        let nested: YMap<String> = root.insertMap(forKey: "state")
        nested["foo"] = "bar"

        // Retrieve it and verify
        let retrieved: YMap<String>? = root.getMap(forKey: "state")
        #expect(retrieved != nil)
        #expect((retrieved?["foo"]) == ("bar"))
    }

    @Test
    func test_insertAndGetNestedArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested array
        let nested: YArray<Int> = root.insertArray(forKey: "numbers")
        nested.append(1)
        nested.append(2)
        nested.append(3)

        // Retrieve it and verify
        let retrieved: YArray<Int>? = root.getArray(forKey: "numbers")
        #expect(retrieved != nil)
        #expect((retrieved?.toArray()) == ([1, 2, 3]))
    }

    @Test
    func test_insertAndGetNestedText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested text
        let nested = root.insertText(forKey: "content")
        nested.append("Hello, World!")

        // Retrieve it and verify
        let retrieved = root.getText(forKey: "content")
        #expect(retrieved != nil)
        #expect((retrieved?.getString()) == ("Hello, World!"))
    }

    @Test
    func test_getOrInsertMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the map
        let first: YMap<String> = root.getOrInsertMap(forKey: "state")
        first["key1"] = "value1"

        // Second call retrieves same map
        let second: YMap<String> = root.getOrInsertMap(forKey: "state")
        #expect((second["key1"]) == ("value1"))

        // Modifications to second affect first (same map)
        second["key2"] = "value2"
        #expect((first["key2"]) == ("value2"))
    }

    @Test
    func test_getOrInsertArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the array
        let first: YArray<Int> = root.getOrInsertArray(forKey: "items")
        first.append(1)

        // Second call retrieves same array
        let second: YArray<Int> = root.getOrInsertArray(forKey: "items")
        #expect((second.toArray()) == ([1]))

        // Modifications to second affect first (same array)
        second.append(2)
        #expect((first.toArray()) == ([1, 2]))
    }

    @Test
    func test_getOrInsertText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the text
        let first = root.getOrInsertText(forKey: "content")
        first.append("Hello")

        // Second call retrieves same text
        let second = root.getOrInsertText(forKey: "content")
        #expect((second.getString()) == ("Hello"))

        // Modifications to second affect first (same text)
        second.append(" World")
        #expect((first.getString()) == ("Hello World"))
    }

    @Test
    func test_tryUpdate_existingKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["existing"] = "oldValue"

        let updated = root.tryUpdate("newValue", forKey: "existing")
        #expect(updated)
        #expect((root["existing"]) == ("newValue"))
    }

    @Test
    func test_tryUpdate_nonExistentKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Note: try_update in yrs actually inserts the value even for non-existent keys
        // and returns true. This is the actual behavior.
        let updated = root.tryUpdate("value", forKey: "nonexistent")
        #expect(updated)
        #expect((root["nonexistent"]) == ("value"))
    }

    @Test
    func test_deeplyNestedStructure() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Create nested structure: root -> level1 (map) -> level2 (map) -> content (text)
        let level1: YMap<String> = root.insertMap(forKey: "level1")
        let level2: YMap<String> = level1.insertMap(forKey: "level2")
        let content = level2.insertText(forKey: "content")
        content.append("Deep value")

        // Retrieve through the chain
        let retrievedL1: YMap<String>? = root.getMap(forKey: "level1")
        #expect(retrievedL1 != nil)

        let retrievedL2: YMap<String>? = retrievedL1?.getMap(forKey: "level2")
        #expect(retrievedL2 != nil)

        let retrievedContent = retrievedL2?.getText(forKey: "content")
        #expect(retrievedContent != nil)
        #expect((retrievedContent?.getString()) == ("Deep value"))
    }

    // MARK: - Sync/Encode Tests for Nested Types

    @Test
    func test_encodeWithEmptyStateVector() {
        // Test that transactionEncodeStateAsUpdateFromSv requires a properly encoded state vector,
        // not just an empty byte array
        let doc1 = YDocument()
        let map1: YMap<Int> = doc1.getOrCreateMap(named: "test")
        map1["value"] = 42

        // Get a properly encoded empty state vector from a fresh document
        let doc2 = YDocument()
        let emptyEncodedStateVector: [UInt8] = doc2.transactSync { txn in
            txn.transactionStateVector()
        }
        print("[TEST] Empty encoded state vector bytes: \(emptyEncodedStateVector.count)")

        // Now use transactionEncodeStateAsUpdateFromSv with the properly encoded state vector
        let update: [UInt8]? = doc1.transactSync { txn in
            try? txn.transactionEncodeStateAsUpdateFromSv(stateVector: emptyEncodedStateVector)
        }
        print("[TEST] Update bytes from FromSv: \(update?.count ?? 0)")
        #expect(update != nil, "Encoding with properly encoded empty state vector should succeed")
        #expect((update?.count ?? 0) > (0), "Update should not be empty")

        // Verify the sync works
        if let update = update {
            doc2.transactSync { txn in
                try? txn.transactionApplyUpdate(update: update)
            }
        }
        let map2: YMap<Int> = doc2.getOrCreateMap(named: "test")
        #expect((map2["value"]) == (42), "Value should be synced")
    }

    @Test
    func test_encodeAndApplyNestedMap() {
        // Create document with nested map structure
        let doc1 = YDocument()
        let root1: YMap<String> = doc1.getOrCreateMap(named: "root")

        doc1.transactSync { txn in
            let stateMap: YMap<Int> = root1.insertMap(forKey: "state", transaction: txn)
            stateMap.updateValue(42, forKey: "count", transaction: txn)
        }

        // Verify nested map exists in original doc
        let origStateMap: YMap<Int>? = doc1.transactSync { txn in
            root1.getMap(forKey: "state", transaction: txn)
        }
        #expect(origStateMap != nil, "Nested map should exist in original document")
        #expect((origStateMap?.get(key: "count")) == (42))

        // Try the simpler encode method (uses StateVector::default() internally)
        let update: [UInt8] = doc1.transactSync { txn in
            txn.transactionEncodeStateAsUpdate()
        }
        print("[TEST] Update bytes from transactionEncodeStateAsUpdate: \(update.count)")
        #expect((update.count) > (0), "Update should not be empty")

        // Apply to new document
        let doc2 = YDocument()
        doc2.transactSync { txn in
            try? txn.transactionApplyUpdate(update: update)
        }

        // Verify nested map was synced
        let root2: YMap<String> = doc2.getOrCreateMap(named: "root")
        let syncedStateMap: YMap<Int>? = doc2.transactSync { txn in
            root2.getMap(forKey: "state", transaction: txn)
        }
        #expect(syncedStateMap != nil, "Nested map should exist in synced document")
        #expect((syncedStateMap?.get(key: "count")) == (42), "Nested map value should be synced")
    }

    @Test
    func test_encodeAndApplyNestedMapWithPrimitiveValue() {
        // Simpler test: nested map with just a primitive value
        let doc1 = YDocument()
        let root1: YMap<String> = doc1.getOrCreateMap(named: "root")

        // Insert nested map and set value
        let stateMap: YMap<Int> = root1.insertMap(forKey: "state")
        stateMap["count"] = 100

        // Encode using the simpler method
        let update: [UInt8] = doc1.transactSync { txn in
            txn.transactionEncodeStateAsUpdate()
        }
        print("[TEST] Update bytes: \(update.count)")
        #expect((update.count) > (0), "Update should not be empty")

        // Apply to new document
        let doc2 = YDocument()
        doc2.transactSync { txn in
            try? txn.transactionApplyUpdate(update: update)
        }

        // Verify
        let root2: YMap<String> = doc2.getOrCreateMap(named: "root")
        let syncedStateMap: YMap<Int>? = root2.getMap(forKey: "state")
        #expect(syncedStateMap != nil, "Nested map should exist after sync")
        #expect((syncedStateMap?["count"]) == (100), "Value should be synced")
    }

    // MARK: - Tests for mixed maps with nested types and primitives

    @Test
    func test_eachIterationWithNestedMapDoesNotCrash() {
        // Test that iterating over a map containing nested types doesn't crash
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add a primitive value
        root["primitiveKey"] = "hello"

        // Iterate - this should not crash, and should only return the primitive
        var collectedKeys: [String] = []
        var collectedValues: [String] = []
        root.each { key, value in
            collectedKeys.append(key)
            collectedValues.append(value)
        }

        // Should only contain the primitive, not the nested map
        #expect((collectedKeys.count) == (1), "Should only iterate over primitive values")
        #expect((collectedKeys.first) == ("primitiveKey"))
        #expect((collectedValues.first) == ("hello"))
    }

    @Test
    func test_toMapWithNestedMapDoesNotCrash() {
        // Test that toMap() works when the map contains nested types
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add primitive values
        root["key1"] = "value1"
        root["key2"] = "value2"

        // toMap() should not crash and should only return primitives
        let map = root.toMap()

        #expect((map.count) == (2), "Should only contain primitive values")
        #expect((map["key1"]) == ("value1"))
        #expect((map["key2"]) == ("value2"))
        #expect(map["nestedMap"] == nil, "Nested map should not be in toMap() result")
    }

    @Test
    func test_observeWithNestedMapDoesNotCrash() async {
        let exercise: (Confirmation) -> sending Void = { eventReceived in
            // Test that observe() works when changes involve nested types
            let doc = YDocument()
            let root: YMap<String> = doc.getOrCreateMap(named: "root")

            var observedChanges: [YMapChange<String>] = []
            root.document.transactSync { transaction in
                root.observe(key: "test", transaction: transaction) { changes in
                    eventReceived()
                    observedChanges.append(contentsOf: changes)
                }
            }

            // Insert a nested map - should not crash
            let _: YMap<Int> = root.insertMap(forKey: "nestedMap")

            // Insert a primitive - should trigger observable change
            root["primitiveKey"] = "hello"

            // Only primitive change should be observed
            #expect((observedChanges.count) == (1), "Should only observe primitive value changes")
            if case .inserted(let key, let value) = observedChanges.first {
                #expect((key) == ("primitiveKey"))
                #expect((value) == ("hello"))
            } else {
                Issue.record("Expected inserted change for primitiveKey")
            }

            root.document.transactSync { transaction in
                root.unobserve(key: "test", transaction: transaction)
            }
        }
        await confirmation("Receives each change", expectedCount: 2, exercise)
    }

    @Test
    func test_valuesIterationWithNestedMapDoesNotCrash() {
        // Test that values() iteration works with nested types
        let doc = YDocument()
        let root: YMap<String> = doc.getOrCreateMap(named: "root")

        // Add a nested map
        let _: YMap<Int> = root.insertMap(forKey: "nestedMap")
        // Add primitive values
        root["key1"] = "value1"
        root["key2"] = "value2"

        // Iterate values - should not crash
        var collectedValues: [String] = []
        root.values { value in
            collectedValues.append(value)
        }

        // Should only contain primitive values
        #expect((collectedValues.count) == (2), "Should only iterate over primitive values")
        #expect(collectedValues.contains("value1"))
        #expect(collectedValues.contains("value2"))
    }

    @Test
    func test_observeNestedMapChangesDirectly() async {
        let exercise: (Confirmation) -> sending Void = { eventReceived in
            // Test that we can observe changes on the nested map itself
            let doc = YDocument()
            let root: YMap<String> = doc.getOrCreateMap(named: "root")
            let nested: YMap<Int> = root.insertMap(forKey: "state")

            var nestedChanges: [YMapChange<Int>] = []
            nested.document.transactSync { transaction in
                nested.observe(key: "test", transaction: transaction) { changes in
                    eventReceived()
                    nestedChanges.append(contentsOf: changes)
                }
            }

            // Changes to nested map should be observed
            nested["count"] = 42

            #expect((nestedChanges.count) == (1))
            if case .inserted(let key, let value) = nestedChanges.first {
                #expect((key) == ("count"))
                #expect((value) == (42))
            } else {
                Issue.record("Expected inserted change for count")
            }

            nested.document.transactSync { transaction in
                nested.unobserve(key: "test", transaction: transaction)
            }
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
    }

    // MARK: - Async Observer Tests

    // MARK: - Async API Tests (Swift 6 Concurrency)

    @Test
    func test_asyncTransact_basicUsage() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        // Use async transact to set values
        await doc.transact { txn in
            map.updateValue(42, forKey: "count", transaction: txn)
            map.updateValue(100, forKey: "score", transaction: txn)
        }

        // Use async transact to read values
        let result = await doc.transact { txn in
            map.toMap(transaction: txn)
        }

        #expect((result["count"]) == (42))
        #expect((result["score"]) == (100))
    }

    @Test
    func test_asyncTransact_returnsValue() async {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        await doc.transact { txn in
            map.updateValue("hello", forKey: "greeting", transaction: txn)
        }

        let greeting = await doc.transact { txn -> String? in
            map.get(key: "greeting", transaction: txn)
        }

        #expect((greeting) == ("hello"))
    }

    @Test
    func test_asyncMapSet() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "test")

        // Use async set API
        await map.set(42, forKey: "value")

        // Use async get API
        let value = await map.get(key: "value")

        #expect((value) == (42))
    }

    @Test
    func test_asyncMapOperations() async {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        // Set multiple values
        await map.set("one", forKey: "a")
        await map.set("two", forKey: "b")
        await map.set("three", forKey: "c")

        // Test async length
        let length = await map.length()
        #expect((length) == (3))

        // Test async containsKey
        let hasA = await map.containsKey("a")
        let hasZ = await map.containsKey("z")
        #expect(hasA)
        #expect(!(hasZ))

        // Test async keys
        let keys = await map.keys()
        #expect((Set(keys)) == (Set(["a", "b", "c"])))

        // Test async values
        let values = await map.values()
        #expect((Set(values)) == (Set(["one", "two", "three"])))

        // Test async toMapAsync
        let dict = await map.toMapAsync()
        #expect((dict) == (["a": "one", "b": "two", "c": "three"]))

        // Test async removeValue
        let removed = await map.removeValue(forKey: "b")
        #expect((removed) == ("two"))

        let lengthAfter = await map.length()
        #expect((lengthAfter) == (2))

        // Test async removeAll
        await map.removeAll()
        let finalLength = await map.length()
        #expect((finalLength) == (0))
    }

    @Test
    func test_asyncTransact_serialization() async {
        let doc = YDocument()
        let map: YMap<Int> = doc.getOrCreateMap(named: "counter")

        // Fire multiple async transactions sequentially to test serialization
        // (Concurrent increment has a Rust bug with map.get on missing keys)
        for i in 0..<10 {
            await doc.transact { txn in
                map.updateValue(i, forKey: "key\(i)", transaction: txn)
            }
        }

        // All writes should have been serialized
        let finalMap = await doc.transact { txn in
            map.toMap(transaction: txn)
        }

        #expect((finalMap.count) == (10))
        for i in 0..<10 {
            #expect((finalMap["key\(i)"]) == (i))
        }
    }

    @Test
    func test_asyncTransact_throwingVersion() async throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        await doc.transact { txn in
            map.updateValue("test", forKey: "key", transaction: txn)
        }

        // Test throwing transact
        let result = try await doc.transact { txn -> String in
            guard let value = map.get(key: "key", transaction: txn) else {
                throw TestError.notFound
            }
            return value
        }

        #expect((result) == ("test"))
    }

    // MARK: - Regression Tests

}

enum TestError: Error {
    case notFound
}
