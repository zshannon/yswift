import Yniffi

@YSwiftActor
protocol Transactable {
    var document: YDocument { get }
}

extension Transactable {
    func withTransaction<T>(_ transaction: YrsTransaction? = nil, changes: (YrsTransaction) -> T) -> T {
        if let transaction { return changes(transaction) }
        return document.transactSync(changes)
    }
}
