/// Serializes document transactions and multi-document undo as synchronous actor work.
/// Observer callbacks receive Sendable values and must await this actor to mutate documents.
@globalActor
public actor YSwiftActor {
    public static let shared = YSwiftActor()
}
