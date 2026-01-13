import Combine
import XCTest
@testable import YSwift

final class YMapTests: XCTestCase {
    var document: YDocument!
    var map: YMap<TestType>!

    override func setUp() {
        document = YDocument()
        map = document.getOrCreateMap(named: "test")
    }

    override func tearDown() {
        document = nil
        map = nil
    }

    func test_insert() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        let finalInstance = map.get(key: initialInstance.name)

        XCTAssertEqual(initialInstance, finalInstance)

        let contains = map.containsKey(secondInstance.name)
        XCTAssertTrue(contains)
    }

    func test_remove() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        XCTAssertEqual(map.length(), 2)
        map.removeValue(forKey: secondInstance.name)
        XCTAssertEqual(map.length(), 1)
    }

    func test_removeAll() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance

        XCTAssertEqual(map.length(), 2)
        map.removeAll()
        XCTAssertEqual(map.length(), 0)
    }

    func test_keys() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedKeys: [String] = []
        map.keys { collectedKeys.append($0) }

        XCTAssertEqual(collectedKeys.sorted(), ["Aidar", "Joe"])
    }

    func test_values() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedValues: [TestType] = []
        map.values {
            collectedValues.append($0)
        }

        XCTAssertTrue(collectedValues.contains(initialInstance))
        XCTAssertTrue(collectedValues.contains(secondInstance))
    }

    func test_each() {
        let initialInstance = TestType(name: "Aidar", age: 24)
        let secondInstance = TestType(name: "Joe", age: 55)

        XCTAssertEqual(map.length(), 0)
        map[initialInstance.name] = initialInstance
        map[secondInstance.name] = secondInstance
        XCTAssertEqual(map.length(), 2)

        var collectedValues: [String: TestType] = [:]
        map.each { key, value in
            collectedValues[key] = value
        }

        XCTAssertTrue(collectedValues.keys.contains("Aidar"))
        XCTAssertTrue(collectedValues.keys.contains("Joe"))

        XCTAssertTrue(collectedValues.values.contains(initialInstance))
        XCTAssertTrue(collectedValues.values.contains(secondInstance))
    }

    func test_observation_closure() {
        let first = TestType(name: "Aidar", age: 24)
        let second = TestType(name: "Joe", age: 55)
        let updatedSecond = TestType(name: "Joe", age: 101)

        var actualChanges: [YMapChange<TestType>] = []

        let subscription = map.observe { changes in
            changes.forEach { change in
                actualChanges.append(change)
            }
        }

        map[first.name] = first
        map[second.name] = second

        map[first.name] = nil
        map[second.name] = updatedSecond

        subscription.cancel()

        // Use set here, to compare two arrays by the composition not by order
        XCTAssertEqual(
            Set(actualChanges),
            Set([
                .inserted(key: first.name, value: first),
                .inserted(key: second.name, value: second),
                .removed(key: first.name, value: first),
                .updated(key: second.name, oldValue: second, newValue: updatedSecond),
            ])
        )
    }

    /*
     https://www.swiftbysundell.com/articles/using-unit-tests-to-identify-avoid-memory-leaks-in-swift/
     https://alisoftware.github.io/swift/closures/2016/07/25/closure-capture-1/
     */

    func test_observation_closure_IsLeakingWithoutUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = map.observe { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        XCTAssertNotNil(weakObject)
        
        subscription.cancel()
    }

    func test_observation_closure_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let subscription = map.observe { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // Explicit unobserving, to prevent leaking
        subscription.cancel()

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        XCTAssertNil(weakObject)
    }

    func test_observation_publisher() {
        let first = TestType(name: "Aidar", age: 24)
        let second = TestType(name: "Joe", age: 55)
        let updatedSecond = TestType(name: "Joe", age: 101)

        var actualChanges: [YMapChange<TestType>] = []

        let cancellable = map.observe().sink { changes in
            changes.forEach { change in
                actualChanges.append(change)
            }
        }

        map[first.name] = first
        map[second.name] = second

        map[first.name] = nil
        map[second.name] = updatedSecond

        cancellable.cancel()

        // Use set here, to compare two arrays by the composition not by order
        XCTAssertEqual(
            Set(actualChanges),
            Set([
                .inserted(key: first.name, value: first),
                .inserted(key: second.name, value: second),
                .removed(key: first.name, value: first),
                .updated(key: second.name, oldValue: second, newValue: updatedSecond),
            ])
        )
    }

    func test_observation_publisher_IsLeakingWithoutCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = map.observe().sink { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // this is to just silence the "unused variable" warning regading `cancellable` variable above
        // remove below two lines to see the warning; it cannot be replace with `_`, because Combine
        // automatically cancells the subscription in that case
        var bag = Set<AnyCancellable>()
        cancellable.store(in: &bag)

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        XCTAssertNotNil(weakObject)
    }

    func test_observation_publisher_IsNotLeakingAfterCancelling() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        let cancellable = map.observe().sink { [object] changes in
            // Capture the object in the closure (note that we need to use
            // a capture list like [object] above in order for the object
            // to be captured by reference instead of by pointer value)
            _ = object
            changes.forEach { _ in }
        }

        // Explicit cancelling, to prevent leaking
        cancellable.cancel()

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        XCTAssertNil(weakObject)
    }

    // MARK: - Nested Shared Type Tests

    func test_getNestedText_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["name"] = "hello"
        XCTAssertNil(root.getText(forKey: "name"))
        XCTAssertNil(root.getText(forKey: "nonexistent"))
    }

    func test_getNestedArray_returnsNilForJsonValue() {
        let root: YMap<[Int]> = document.getOrCreateMap(named: "root")
        root["numbers"] = [1, 2, 3]
        let arr: YArray<Int>? = root.getArray(forKey: "numbers")
        XCTAssertNil(arr)
    }

    func test_getNestedMap_returnsNilForJsonValue() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["key"] = "value"
        let nested: YMap<String>? = root.getMap(forKey: "key")
        XCTAssertNil(nested)
    }

    func test_isUndefined() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        XCTAssertFalse(root.isUndefined(forKey: "nonexistent"))
        root["name"] = "test"
        XCTAssertFalse(root.isUndefined(forKey: "name"))
    }

    // MARK: - Insert and Retrieve Nested Types

    func test_insertAndGetNestedMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested map
        let nested: YMap<String> = root.insertMap(forKey: "state")
        nested["foo"] = "bar"

        // Retrieve it and verify
        let retrieved: YMap<String>? = root.getMap(forKey: "state")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?["foo"], "bar")
    }

    func test_insertAndGetNestedArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested array
        let nested: YArray<Int> = root.insertArray(forKey: "numbers")
        nested.append(1)
        nested.append(2)
        nested.append(3)

        // Retrieve it and verify
        let retrieved: YArray<Int>? = root.getArray(forKey: "numbers")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.toArray(), [1, 2, 3])
    }

    func test_insertAndGetNestedText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Insert a nested text
        let nested = root.insertText(forKey: "content")
        nested.append("Hello, World!")

        // Retrieve it and verify
        let retrieved = root.getText(forKey: "content")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.getString(), "Hello, World!")
    }

    func test_getOrInsertMap() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the map
        let first: YMap<String> = root.getOrInsertMap(forKey: "state")
        first["key1"] = "value1"

        // Second call retrieves same map
        let second: YMap<String> = root.getOrInsertMap(forKey: "state")
        XCTAssertEqual(second["key1"], "value1")

        // Modifications to second affect first (same map)
        second["key2"] = "value2"
        XCTAssertEqual(first["key2"], "value2")
    }

    func test_getOrInsertArray() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the array
        let first: YArray<Int> = root.getOrInsertArray(forKey: "items")
        first.append(1)

        // Second call retrieves same array
        let second: YArray<Int> = root.getOrInsertArray(forKey: "items")
        XCTAssertEqual(second.toArray(), [1])

        // Modifications to second affect first (same array)
        second.append(2)
        XCTAssertEqual(first.toArray(), [1, 2])
    }

    func test_getOrInsertText() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // First call creates the text
        let first = root.getOrInsertText(forKey: "content")
        first.append("Hello")

        // Second call retrieves same text
        let second = root.getOrInsertText(forKey: "content")
        XCTAssertEqual(second.getString(), "Hello")

        // Modifications to second affect first (same text)
        second.append(" World")
        XCTAssertEqual(first.getString(), "Hello World")
    }

    func test_tryUpdate_existingKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")
        root["existing"] = "oldValue"

        let updated = root.tryUpdate("newValue", forKey: "existing")
        XCTAssertTrue(updated)
        XCTAssertEqual(root["existing"], "newValue")
    }

    func test_tryUpdate_nonExistentKey() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Note: try_update in yrs actually inserts the value even for non-existent keys
        // and returns true. This is the actual behavior.
        let updated = root.tryUpdate("value", forKey: "nonexistent")
        XCTAssertTrue(updated)
        XCTAssertEqual(root["nonexistent"], "value")
    }

    func test_deeplyNestedStructure() {
        let root: YMap<String> = document.getOrCreateMap(named: "root")

        // Create nested structure: root -> level1 (map) -> level2 (map) -> content (text)
        let level1: YMap<String> = root.insertMap(forKey: "level1")
        let level2: YMap<String> = level1.insertMap(forKey: "level2")
        let content = level2.insertText(forKey: "content")
        content.append("Deep value")

        // Retrieve through the chain
        let retrievedL1: YMap<String>? = root.getMap(forKey: "level1")
        XCTAssertNotNil(retrievedL1)

        let retrievedL2: YMap<String>? = retrievedL1?.getMap(forKey: "level2")
        XCTAssertNotNil(retrievedL2)

        let retrievedContent = retrievedL2?.getText(forKey: "content")
        XCTAssertNotNil(retrievedContent)
        XCTAssertEqual(retrievedContent?.getString(), "Deep value")
    }
}
