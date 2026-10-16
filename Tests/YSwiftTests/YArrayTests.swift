import Foundation
import Testing
@testable import YSwift

@Suite
final class YArrayTests {
    var document: YDocument!
    var array: YArray<TestType>!

    init() {
        document = YDocument()
        array = document.getOrCreateArray(named: "test")
    }

    @Test
    func test_subscripts() {
        let aidar = TestType(name: "Aidar", age: 24)
        let kevin = TestType(name: "Kevin", age: 100)
        let joe = TestType(name: "Joe", age: 55)
        let bart = TestType(name: "Bart", age: 200)

        array.insertArray(at: 0, values: [aidar, kevin, joe])

        array[0] = bart
        array.remove(at: 1)

        #expect((array.count) == (2))
        #expect((array[0]) == (bart))
        #expect((array[1]) == (joe))
    }

    @Test
    func test_HOFs() {
        let aidar = TestType(name: "Aidar", age: 24)
        let joe = TestType(name: "Joe", age: 55)
        array.insertArray(at: 0, values: [aidar, joe])

        #expect((array.filter { $0.name == "Aidar" }) == ([aidar]))

        #expect((array.map { TestType(name: "Mr. " + $0.name, age: 100) }) == ([TestType(name: "Mr. Aidar", age: 100), TestType(name: "Mr. Joe", age: 100)]))

        #expect((array.reduce(into: 0) { sum, current in
                sum += current.age
            }) == (79))
    }

    @Test
    func test_insert() {
        let initialInstance = TestType(name: "Aidar", age: 24)

        array.insert(at: 0, value: initialInstance)

        #expect((array[0]) == (initialInstance))
    }

    @Test
    func test_getIndexOutOfBounds() {
        let initialInstance = TestType(name: "Aidar", age: 24)

        array.insert(at: 0, value: initialInstance)

        #expect((array.get(index: 1)) == (nil))
    }

    @Test
    func test_insertArray() {
        let arrayToInsert = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]

        array.insertArray(at: 0, values: arrayToInsert)

        #expect((array.toArray()) == (arrayToInsert))
    }

    @Test
    func test_length() {
        array.insert(at: 0, value: TestType(name: "Aidar", age: 24))
        #expect((array.length()) == (1))
    }

    @Test
    func test_pushBack_and_pushFront() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        #expect((array.toArray()) == ([front, initial, back]))
    }

    @Test
    func test_remove() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        #expect((array.toArray()) == ([front, initial, back]))

        array.remove(at: 1)

        #expect((array.toArray()) == ([front, back]))
    }

    @Test
    func test_removeRange() {
        let initial = TestType(name: "Middleton", age: 77)
        let front = TestType(name: "Aidar", age: 24)
        let back = TestType(name: "Joe", age: 55)

        array.insert(at: 0, value: initial)
        array.append(back)
        array.prepend(front)

        #expect((array.toArray()) == ([front, initial, back]))

        array.removeRange(start: 0, length: 3)

        #expect((array.length()) == (0))
    }

    @Test
    func test_forEach() {
        let arrayToInsert = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]
        var collectedArray: [TestType] = []

        array.insertArray(at: 0, values: arrayToInsert)

        array.each {
            collectedArray.append($0)
        }

        #expect((arrayToInsert) == (collectedArray))
    }

    @Test
    func test_transaction_IsNotLeaking() {
        weak var weakLocalArray: YArray<TestType>?
        weak var weakLocalDocument: YDocument?
        do {
            let localDocument = YDocument()
            let localArray: YArray<TestType> = localDocument.getOrCreateArray(named: "test")

            var object = NSObject()
            weak var weakObject = object

            localDocument.transactSync { [object] txn in
                _ = object
                localArray.insert(at: 0, value: .init(name: "Aidar", age: 24), transaction: txn)
            }

            object = NSObject()
            #expect(weakObject == nil)
            weakLocalArray = localArray
            weakLocalDocument = localDocument
        }
        #expect(weakLocalArray == nil)
        #expect(weakLocalDocument == nil)
    }

    @Test
    func test_observation_closure() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let insertedElements = [TestType(name: "Aidar", age: 24), TestType(name: "Joe", age: 55)]
            var receivedElements: [TestType] = []

            self.array.document.transactSync { transaction in
                self.array.observe(key: "test", transaction: transaction) { changes in
                    eventReceived()
                    changes.forEach {
                        switch $0 {
                        case let .added(elements):
                            receivedElements = elements
                        default: break
                        }
                    }
                }
            }

            array.insertArray(at: 0, values: insertedElements)

            self.array.document.transactSync { transaction in
                self.array.unobserve(key: "test", transaction: transaction)
            }

            #expect((insertedElements) == (receivedElements))
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
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

        self.array.document.transactSync { transaction in
            self.array.observe(key: "test", transaction: transaction) { [object] changes in
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
        
        self.array.document.transactSync { transaction in
            self.array.unobserve(key: "test", transaction: transaction)
        }
    }

    @Test
    func test_observation_closure_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        self.array.document.transactSync { transaction in
            self.array.observe(key: "test", transaction: transaction) { [object] changes in
                // Capture the object in the closure (note that we need to use
                // a capture list like [object] above in order for the object
                // to be captured by reference instead of by pointer value)
                _ = object
                changes.forEach { _ in }
            }
        }
        
        // Explicit unobserving, to prevent leaking
        self.array.document.transactSync { transaction in
            self.array.unobserve(key: "test", transaction: transaction)
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
    func test_insertAndGetNestedMap() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested map at index 0
        let nested: YMap<String> = arr.insertMap(at: 0)
        nested["key"] = "value"

        // Retrieve it and verify
        let retrieved: YMap<String>? = arr.getMap(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?["key"]) == ("value"))
    }

    @Test
    func test_insertAndGetNestedArray() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested array at index 0
        let nested: YArray<Int> = arr.insertArray(at: 0)
        nested.append(1)
        nested.append(2)
        nested.append(3)

        // Retrieve it and verify
        let retrieved: YArray<Int>? = arr.getArray(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?.toArray()) == ([1, 2, 3]))
    }

    @Test
    func test_insertAndGetNestedText() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Insert a nested text at index 0
        let nested = arr.insertText(at: 0)
        nested.append("Hello, World!")

        // Retrieve it and verify
        let retrieved = arr.getText(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?.getString()) == ("Hello, World!"))
    }

    @Test
    func test_pushNestedMap() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested map
        let nested: YMap<String> = arr.pushMap()
        nested["foo"] = "bar"

        #expect((arr.count) == (1))
        let retrieved: YMap<String>? = arr.getMap(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?["foo"]) == ("bar"))
    }

    @Test
    func test_pushNestedArray() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested array
        let nested: YArray<Int> = arr.pushArray()
        nested.append(42)

        #expect((arr.count) == (1))
        let retrieved: YArray<Int>? = arr.getArray(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?.toArray()) == ([42]))
    }

    @Test
    func test_pushNestedText() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")

        // Push a nested text
        let nested = arr.pushText()
        nested.append("pushed text")

        #expect((arr.count) == (1))
        let retrieved = arr.getText(at: 0)
        #expect(retrieved != nil)
        #expect((retrieved?.getString()) == ("pushed text"))
    }

    @Test
    func test_isUndefined() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")
        arr.append("hello")

        // Regular value should not be undefined
        #expect(!(arr.isUndefined(at: 0)))
    }

    @Test
    func test_nestedTypesInArray_returnsNilForJsonValue() {
        let arr: YArray<String> = document.getOrCreateArray(named: "testArr")
        arr.append("hello")

        // JSON string value should return nil for nested type getters
        #expect(arr.getMap(at: 0) as YMap<String>? == nil)
        #expect(arr.getArray(at: 0) as YArray<Int>? == nil)
        #expect(arr.getText(at: 0) == nil)
    }

    // MARK: - Async API Tests

    @Test
    func test_asyncAppend() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.append(1)
        await arr.append(2)
        await arr.append(3)

        let result = await arr.toArrayAsync()
        #expect((result) == ([1, 2, 3]))
    }

    @Test
    func test_asyncInsert() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.append("first")
        await arr.append("third")
        await arr.insert(at: 1, value: "second")

        let result = await arr.toArrayAsync()
        #expect((result) == (["first", "second", "third"]))
    }

    @Test
    func test_asyncInsertArray() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        let result = await arr.toArrayAsync()
        #expect((result) == ([1, 2, 3, 4, 5]))
    }

    @Test
    func test_asyncPrepend() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.append("second")
        await arr.prepend("first")

        let result = await arr.toArrayAsync()
        #expect((result) == (["first", "second"]))
    }

    @Test
    func test_asyncRemove() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3])
        await arr.remove(at: 1)

        let result = await arr.toArrayAsync()
        #expect((result) == ([1, 3]))
    }

    @Test
    func test_asyncRemoveRange() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])
        await arr.removeRange(start: 1, length: 3)

        let result = await arr.toArrayAsync()
        #expect((result) == ([1, 5]))
    }

    @Test
    func test_asyncLength() async {
        let doc = YDocument()
        let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: [1, 2, 3, 4, 5])

        let length = await arr.lengthAsync()
        #expect((length) == (5))
    }

    @Test
    func test_asyncGet() async {
        let doc = YDocument()
        let arr: YArray<String> = doc.getOrCreateArray(named: "test")

        await arr.insertArray(at: 0, values: ["a", "b", "c"])

        let value = await arr.get(index: 1)
        #expect((value) == ("b"))

        let outOfBounds = await arr.get(index: 10)
        #expect(outOfBounds == nil)
    }

    @Test
    func test_asyncObserveStream_exists() async {
        await confirmation("Cancelled before receiving an event", expectedCount: 0) { eventReceived in
            let doc = YDocument()
            let arr: YArray<Int> = doc.getOrCreateArray(named: "test")

            // Test that observeAsync returns an AsyncStream
            let stream = await arr.observeAsync()

            // Create a task that will consume from the stream
            let task = Task {
                for await _ in stream {
                    eventReceived()
                    break
                }
            }

            // Cancel immediately - we just want to verify the API exists and is usable
            task.cancel()
            await task.value
        }
    }

    @Test
    func test_asyncToArray() async {
        let doc = YDocument()
        let arr: YArray<TestType> = doc.getOrCreateArray(named: "test")

        let aidar = TestType(name: "Aidar", age: 24)
        let joe = TestType(name: "Joe", age: 55)

        await arr.append(aidar)
        await arr.append(joe)

        let result = await arr.toArrayAsync()
        #expect((result) == ([aidar, joe]))
    }
}
