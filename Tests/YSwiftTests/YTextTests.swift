import Foundation
import Testing
@testable import YSwift

@Suite
final class YTextTests {
    var document: YDocument!
    var text: YText!

    init() {
        document = YDocument()
        text = document.getOrCreateText(named: "test")
    }

    @Test
    func test_append() {
        text.append("hello, world!")

        #expect((String(text)) == ("hello, world!"))
    }

    @Test
    func test_appendAndInsert() throws {
        text.append("trailing text")
        text.insert("leading text, ", at: 0)

        #expect((String(text)) == ("leading text, trailing text"))
    }

    @Test
    func test_format() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let expectedAttributes = ["weight": "bold"]
            var actualAttributes: [String: String] = [:]

            self.text.document.transactSync { transaction in
                self.text.observe(key: "test", transaction: transaction) { deltas in
                    eventReceived()
                    deltas.forEach {
                        switch $0 {
                        case let .retained(_, attrs):
                            actualAttributes = Dictionary(
                                uniqueKeysWithValues: attrs.map {
                                    ($0, $1 as! String)
                                }
                            )
                        default: break
                        }
                    }
                }
            }

            text.append("abc")
            text.format(at: 0, length: 3, attributes: expectedAttributes)

            self.text.document.transactSync { transaction in
                self.text.unobserve(key: "test", transaction: transaction)
            }

            #expect((expectedAttributes) == (actualAttributes))
        }
        await confirmation("Receives each change", expectedCount: 2, exercise)
    }

    @Test
    func test_insertWithAttributes() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let expectedAttributes = ["weight": "bold"]
            var actualAttributes: [String: String] = [:]

            self.text.document.transactSync { transaction in
                self.text.observe(key: "test", transaction: transaction) { deltas in
                    eventReceived()
                    deltas.forEach {
                        switch $0 {
                        case let .inserted(_, attrs):
                            actualAttributes = Dictionary(
                                uniqueKeysWithValues: attrs.map {
                                    ($0, $1 as! String)
                                }
                            )
                        default: break
                        }
                    }
                }
            }

            text.insertWithAttributes("abc", attributes: expectedAttributes, at: 0)

            self.text.document.transactSync { transaction in
                self.text.unobserve(key: "test", transaction: transaction)
            }

            #expect((String(text)) == ("abc"))
            #expect((expectedAttributes) == (actualAttributes))
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
    }

    @Test
    func test_insertEmbed() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let embed = TestType(name: "Aidar", age: 24)
            var insertedEmbed: TestType?

            self.text.document.transactSync { transaction in
                self.text.observe(key: "test", transaction: transaction) { deltas in
                    eventReceived()
                    deltas.forEach {
                        switch $0 {
                        case let .inserted(value, _):
                            insertedEmbed = Coder.decoded(value)
                        default: break
                        }
                    }
                }
            }

            text.insertEmbed(embed, at: 0)

            self.text.document.transactSync { transaction in
                self.text.unobserve(key: "test", transaction: transaction)
            }

            #expect((embed) == (insertedEmbed))
            #expect((text.length()) == (1))
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
    }

    @Test
    func test_insertEmbedWithAttributes() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            let embed = TestType(name: "Aidar", age: 24)
            var insertedEmbed: TestType?

            let expectedAttributes = ["weight": "bold"]
            var actualAttributes: [String: String] = [:]

            self.text.document.transactSync { transaction in
                self.text.observe(key: "test", transaction: transaction) { deltas in
                    eventReceived()
                    deltas.forEach {
                        switch $0 {
                        case let .inserted(value, attrs):
                            insertedEmbed = Coder.decoded(value)
                            actualAttributes = Dictionary(
                                uniqueKeysWithValues: attrs.map {
                                    ($0, $1 as! String)
                                }
                            )
                        default: break
                        }
                    }
                }
            }

            text.insertEmbedWithAttributes(embed, attributes: expectedAttributes, at: 0)

            self.text.document.transactSync { transaction in
                self.text.unobserve(key: "test", transaction: transaction)
            }

            #expect((embed) == (insertedEmbed))
            #expect((expectedAttributes) == (actualAttributes))
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
    }

    @Test
    func test_length() throws {
        text.append("abcd")
        #expect((text.length()) == (4))
    }

    @Test
    func test_removeRange() throws {
        text.append("few apples")
        text.removeRange(start: 0, length: 4)

        #expect((String(text)) == ("apples"))
    }

    @Test
    func test_closure_observation() async {
        let exercise: (Confirmation) -> sending Void = { [self] eventReceived in
            var insertedValue = String()

            self.text.document.transactSync { transaction in
                self.text.observe(key: "test", transaction: transaction) { deltas in
                    eventReceived()
                    deltas.forEach {
                        switch $0 {
                        case let .inserted(value, _):
                            insertedValue = Coder.decoded(value)
                        default: break
                        }
                    }
                }
            }

            text.append("test")

            self.text.document.transactSync { transaction in
                self.text.unobserve(key: "test", transaction: transaction)
            }

            #expect((insertedValue) == ("test"))
        }
        await confirmation("Receives each change", expectedCount: 1, exercise)
    }

    /*
     https://www.swiftbysundell.com/articles/using-unit-tests-to-identify-avoid-memory-leaks-in-swift/
     https://alisoftware.github.io/swift/closures/2016/07/25/closure-capture-1/
     */

    @Test
    func test_closure_observation_IsLeakingwithoutUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        self.text.document.transactSync { transaction in
            self.text.observe(key: "test", transaction: transaction) { [object] deltas in
                // Capture the object in the closure (note that we need to use
                // a capture list like [object] above in order for the object
                // to be captured by reference instead of by pointer value)
                _ = object
                deltas.forEach { _ in }
            }
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should still persist.
        // Because we didn't explicitly unobserved/unsubscribed.
        object = NSObject()
        #expect(weakObject != nil)
        
        self.text.document.transactSync { transaction in
            self.text.unobserve(key: "test", transaction: transaction)
        }
    }

    @Test
    func test_closure_observation_IsNotLeakingAfterUnobserving() {
        // Create an object (it can be of any type), and hold both
        // a strong and a weak reference to it
        var object = NSObject()
        weak var weakObject = object

        self.text.document.transactSync { transaction in
            self.text.observe(key: "test", transaction: transaction) { [object] deltas in
                // Capture the object in the closure (note that we need to use
                // a capture list like [object] above in order for the object
                // to be captured by reference instead of by pointer value)
                _ = object
                deltas.forEach { _ in }
            }
        }

        // Explicit unobserving, to prevent leaking
        self.text.document.transactSync { transaction in
            self.text.unobserve(key: "test", transaction: transaction)
        }

        // When we re-assign our local strong reference to a new object the
        // weak reference should become nil, since the closure should
        // have been run and removed at this point
        // Because we did explicitly unobserve/unsubscribe at this point.
        object = NSObject()
        #expect(weakObject == nil)
    }

    // MARK: - Async API Tests

    @Test
    func test_asyncAppend() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello")
        await text.append(", world!")

        let result = await text.getStringAsync()
        #expect((result) == ("hello, world!"))
    }

    @Test
    func test_asyncInsert() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("world!")
        await text.insert("hello, ", at: 0)

        let result = await text.getStringAsync()
        #expect((result) == ("hello, world!"))
    }

    @Test
    func test_asyncRemoveRange() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello, world!")
        await text.removeRange(start: 5, length: 7)

        let result = await text.getStringAsync()
        #expect((result) == ("hello!"))
    }

    @Test
    func test_asyncLength() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello")
        let length = await text.lengthAsync()
        #expect((length) == (5))
    }

    @Test
    func test_asyncObserveStream_exists() async {
        await confirmation("Cancelled before receiving an event", expectedCount: 0) { eventReceived in
            let doc = YDocument()
            let text = doc.getOrCreateText(named: "test")

            // Test that observeAsync returns an AsyncStream
            let stream = await text.observeAsync()

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
    func test_asyncFormat() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("bold text")
        await text.format(at: 0, length: 4, attributes: ["weight": "bold"])

        let diff = await text.diffAsync()
        #expect(!(diff.isEmpty))
    }

    @Test
    func test_asyncInsertWithAttributes() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.insertWithAttributes("styled", attributes: ["color": "red"], at: 0)

        let result = await text.getStringAsync()
        #expect((result) == ("styled"))
    }

    @Test
    func test_asyncDiff() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        await text.append("hello world")

        let diff = await text.diffAsync()
        #expect((diff.count) == (1))
        if case .text(let value, _) = diff[0] {
            // The diff value is the raw text, not JSON
            #expect(value.contains("hello world"))
        } else {
            Issue.record("Expected text diff")
        }
    }

    @Test
    func test_asyncMultipleOperations() async {
        let doc = YDocument()
        let text = doc.getOrCreateText(named: "test")

        // Test multiple sequential async operations
        await text.append("hello")
        await text.insert(" world", at: 5)
        await text.removeRange(start: 0, length: 6)

        let result = await text.getStringAsync()
        #expect((result) == ("world"))
    }
}
