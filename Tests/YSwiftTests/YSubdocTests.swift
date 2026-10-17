import Foundation
import Testing
import Synchronization
@testable import YSwift

@YSwiftActor
@Suite
final class YSubdocTests {

    // MARK: - Basic Creation Tests

    @Test
    func test_subdocBasicCreation() {
        let parentDoc = YDocument()
        let subdoc = YDocument(options: YDocumentOptions(guid: "test-subdoc"))

        #expect((subdoc.guid) == ("test-subdoc"))
        #expect(subdoc.parentDocument == nil)

        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")
        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // After insertion, we should be able to retrieve it
        let retrieved = parentDoc.transactSync { txn in
            array.getSubdoc(at: 0, transaction: txn)
        }

        #expect(retrieved != nil)
        #expect((retrieved?.guid) == ("test-subdoc"))
    }

    @Test
    func test_subdocWithOptions() {
        let options = YDocumentOptions(
            autoLoad: true,
            clientId: 12345,
            guid: "custom-guid",
            shouldLoad: true
        )
        let doc = YDocument(options: options)

        #expect((doc.autoLoad) == (true))
        #expect((doc.clientId) == (12345))
        #expect((doc.guid) == ("custom-guid"))
        #expect((doc.shouldLoad) == (true))
    }

    // MARK: - Parent Relationship Tests

    @Test
    func test_subdocParentRelationship() {
        let parentDoc = YDocument()
        let subdoc = YDocument(options: YDocumentOptions(guid: "child"))
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "subdocs")

        // Before insertion, subdoc has no parent
        #expect(subdoc.parentDocument == nil)

        // Insert subdoc
        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // The inserted subdoc should have a parent
        #expect(inserted.parentDocument != nil)
        #expect(inserted.parentDocument!.isSame(as: parentDoc))
    }

    // MARK: - Array Insertion Tests

    @Test
    func test_subdocArrayInsertion() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "doc-1"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "doc-2"))

        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
        }

        let retrieved1 = array.getSubdoc(at: 0)
        let retrieved2 = array.getSubdoc(at: 1)

        #expect(retrieved1 != nil)
        #expect(retrieved2 != nil)
        #expect((retrieved1?.guid) == ("doc-1"))
        #expect((retrieved2?.guid) == ("doc-2"))
    }

    // MARK: - Map Insertion Tests

    @Test
    func test_subdocMapInsertion() {
        let parentDoc = YDocument()
        let map: YMap<String> = parentDoc.getOrCreateMap(named: "docs")

        let subdoc = YDocument(options: YDocumentOptions(guid: "mapped-doc"))

        parentDoc.transactSync { txn in
            map.insertSubdoc(subdoc, forKey: "myDoc", transaction: txn)
        }

        let retrieved = map.getSubdoc(forKey: "myDoc")

        #expect(retrieved != nil)
        #expect((retrieved?.guid) == ("mapped-doc"))
    }

    // MARK: - Subdocs Iterator Tests

    @Test
    func test_subdocsIterator() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        let subdoc1 = YDocument(options: YDocumentOptions(guid: "iter-doc-1"))
        let subdoc2 = YDocument(options: YDocumentOptions(guid: "iter-doc-2"))

        parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc1, transaction: txn)
            array.insertSubdoc(at: 1, subdoc2, transaction: txn)
        }

        // Get subdoc GUIDs
        let guids = parentDoc.subdocGuids()
        #expect((guids.count) == (2))
        #expect(guids.contains("iter-doc-1"))
        #expect(guids.contains("iter-doc-2"))

        // Get subdocs
        let subdocs = parentDoc.subdocs()
        #expect((subdocs.count) == (2))
    }

    // MARK: - GUID Preservation Tests

    @Test
    func test_subdocGuid() {
        let customGuid = "my-unique-guid-12345"
        let doc = YDocument(options: YDocumentOptions(guid: customGuid))

        #expect((doc.guid) == (customGuid))
    }

    // MARK: - Reference Equality Tests

    @Test
    func test_subdocPtrEq() {
        let doc1 = YDocument()
        let doc2 = YDocument()

        // Different documents should not be equal
        #expect(!(doc1.isSame(as: doc2)))

        // Same document should be equal to itself
        #expect(doc1.isSame(as: doc1))

        // Inserted and retrieved subdocs should be equal
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")
        let subdoc = YDocument(options: YDocumentOptions(guid: "ptr-test"))

        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        let retrieved = array.getSubdoc(at: 0)!

        #expect(inserted.isSame(as: retrieved))
    }

    // MARK: - Observation Tests

    @Test
    func test_observeSubdocs() async throws {
        try await confirmation("Receives the added subdocument") { received in
            let parent = YDocument()
            let array: YArray<String> = parent.getOrCreateArray(named: "docs")
            var events = await parent.observeSubdocsAsync().makeAsyncIterator()
            let child = YDocument(options: YDocumentOptions(guid: "observed-doc"))
            parent.transactSync { array.insertSubdoc(at: 0, child, transaction: $0) }
            let event = try #require(await events.next())
            received()
            #expect(event.added.map(\.guid) == ["observed-doc"])
        }
    }

    // MARK: - Subdoc Data Tests

    @Test
    func test_subdocWithData() {
        let parentDoc = YDocument()
        let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

        // Create subdoc with its own data
        let subdoc = YDocument(options: YDocumentOptions(guid: "data-doc"))
        let subdocText = subdoc.getOrCreateText(named: "content")
        subdoc.transactSync { txn in
            subdocText.append("Hello from subdoc!", in: txn)
        }

        // Insert subdoc into parent
        let inserted = parentDoc.transactSync { txn in
            array.insertSubdoc(at: 0, subdoc, transaction: txn)
        }

        // Retrieve and verify content
        let retrievedText = inserted.getOrCreateText(named: "content")
        let content = inserted.transactSync { txn in
            retrievedText.getString(in: txn)
        }

        #expect((content) == ("Hello from subdoc!"))
    }

    // MARK: - Memory Leak Tests

    @Test
    func test_subdocMemoryLeaks() {
        weak var weakParentDoc: YDocument?
        weak var weakSubdoc: YDocument?
        weak var weakArray: YArray<String>?
        do {
            let parentDoc = YDocument()
            let subdoc = YDocument(options: YDocumentOptions(guid: "leak-test"))
            let array: YArray<String> = parentDoc.getOrCreateArray(named: "docs")

            parentDoc.transactSync { txn in
                array.insertSubdoc(at: 0, subdoc, transaction: txn)
            }

            weakParentDoc = parentDoc
            weakSubdoc = subdoc
            weakArray = array
        }
        #expect(weakParentDoc == nil)
        #expect(weakSubdoc == nil)
        #expect(weakArray == nil)
    }
}
