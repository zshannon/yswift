import Foundation
import Testing
import Synchronization
import Yniffi
@testable import YSwift

@YSwiftActor
@Suite
final class YJsonPathTests {

    // MARK: - Basic Query Tests

    @Test
    func test_queryRootMap() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "user")
        doc.transactSync { txn in
            map.updateValue("Alice", forKey: "name", transaction: txn)
        }

        let results = try doc.query("$.user")
        #expect((results.count) == (1))
        // The result should be a JSON object with name: "Alice"
        #expect(results[0].contains("Alice"))
    }

    @Test
    func test_queryMapField() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "user")
        doc.transactSync { txn in
            map.updateValue("Bob", forKey: "name", transaction: txn)
            map.updateValue("30", forKey: "age", transaction: txn)
        }

        let results = try doc.query("$.user.name")
        #expect((results.count) == (1))
        #expect((results[0]) == ("\"Bob\""))
    }

    @Test
    func test_queryArray() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("first", transaction: txn)
            array.append("second", transaction: txn)
            array.append("third", transaction: txn)
        }

        // Query using wildcard to get individual elements instead of the array itself
        let results = try doc.query("$.items[*]")
        #expect((results.count) == (3))
        // Each result is a JSON-encoded string
        #expect((results[0]) == ("\"first\""))
        #expect((results[1]) == ("\"second\""))
        #expect((results[2]) == ("\"third\""))
    }

    @Test
    func test_queryArrayIndex() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("apple", transaction: txn)
            array.append("banana", transaction: txn)
            array.append("cherry", transaction: txn)
        }

        let results = try doc.query("$.items[1]")
        #expect((results.count) == (1))
        #expect((results[0]) == ("\"banana\""))
    }

    @Test
    func test_queryArrayWildcard() throws {
        let doc = YDocument()
        let array: YArray<String> = doc.getOrCreateArray(named: "items")
        doc.transactSync { txn in
            array.append("one", transaction: txn)
            array.append("two", transaction: txn)
            array.append("three", transaction: txn)
        }

        let results = try doc.query("$.items[*]")
        #expect((results.count) == (3))
        #expect((results[0]) == ("\"one\""))
        #expect((results[1]) == ("\"two\""))
        #expect((results[2]) == ("\"three\""))
    }

    // MARK: - Text Query Tests

    @Test
    func test_queryText() throws {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "content")
        doc.transactSync { txn in
            text.append("Hello, World!", in: txn)
        }

        let results = try doc.query("$.content")
        #expect((results.count) == (1))
        #expect((results[0]) == ("\"Hello, World!\""))
    }

    // MARK: - Nested Query Tests

    @Test
    func test_queryNestedStructure() throws {
        let doc = YDocument()
        let users: YArray<String> = doc.getOrCreateArray(named: "users")

        // Create JSON objects for users
        doc.transactSync { txn in
            users.append("{\"name\":\"Alice\",\"age\":30}", transaction: txn)
            users.append("{\"name\":\"Bob\",\"age\":25}", transaction: txn)
        }

        let results = try doc.query("$.users[*]")
        #expect((results.count) == (2))
    }

    // MARK: - Error Handling Tests

    @Test
    func test_invalidPathThrows() {
        let doc = YDocument()
        let _: YMap<String> = doc.getOrCreateMap(named: "test")

        #expect(throws: YrsJsonPathError.self) {
            try doc.query("invalid path syntax!!!")
        }
    }

    @Test
    func test_emptyPathReturnsEmpty() throws {
        let doc = YDocument()

        // Empty path is technically valid but returns no results
        let results = try doc.query("")
        #expect((results.count) == (0))
    }

    // MARK: - Empty Results Tests

    @Test
    func test_queryNonExistentPath() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "data")
        doc.transactSync { txn in
            map.updateValue("value", forKey: "key", transaction: txn)
        }

        let results = try doc.query("$.nonexistent")
        #expect((results.count) == (0))
    }

    // MARK: - Transaction Tests

    @Test
    func test_queryWithExplicitTransaction() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "test")

        let results = doc.transactSync { txn in
            map.updateValue("hello", forKey: "greeting", transaction: txn)
            return try? doc.query("$.test.greeting", transaction: txn)
        }

        #expect(results != nil)
        #expect((results?.count) == (1))
        #expect((results?[0]) == ("\"hello\""))
    }

    // MARK: - Array Slice Tests

    @Test
    func test_queryArraySlice() throws {
        let doc = YDocument()
        let array: YArray<Int> = doc.getOrCreateArray(named: "numbers")
        doc.transactSync { txn in
            array.append(1, transaction: txn)
            array.append(2, transaction: txn)
            array.append(3, transaction: txn)
            array.append(4, transaction: txn)
            array.append(5, transaction: txn)
        }

        let results = try doc.query("$.numbers[1:3]")
        #expect((results.count) == (2))
        #expect((results[0]) == ("2"))
        #expect((results[1]) == ("3"))
    }

    // MARK: - Recursive Descent Tests

    @Test
    func test_queryRecursiveDescent() throws {
        let doc = YDocument()
        let map: YMap<String> = doc.getOrCreateMap(named: "data")
        doc.transactSync { txn in
            map.updateValue("outer", forKey: "name", transaction: txn)
        }

        // This should find "name" at any depth
        let results = try doc.query("$..name")
        #expect((results.count) >= (1))
    }
}
