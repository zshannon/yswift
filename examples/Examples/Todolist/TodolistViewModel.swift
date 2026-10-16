import Observation
import MultipeerConnectivity
import SwiftUI
import YSwift

enum ConnectionState: String {
    case connecting = "Connecting..."
    case connected = "Connected"
    case notConnected = "Offline"

    init?(_ sessionState: MCSessionState) {
        switch sessionState {
        case .notConnected:
            self = .notConnected
        case .connecting:
            self = .connecting
        case .connected:
            self = .connected
        @unknown default:
            return nil
        }
    }
}

@MainActor
@Observable
final class TodolistViewModel {
    var connectionState: ConnectionState?
    private(set) var items: [TodoItem]

    private let sharedItems: YArray<TodoItem>

    private let connectionManager: ConnectionManager
    private let document: YDocument

    init(connectionManager: ConnectionManager, document: YDocument) {
        self.connectionManager = connectionManager
        self.document = document
        sharedItems = document.getOrCreateArray(named: "TodoItem")
        items = sharedItems.toArray()

        connectionManager.onUpdatesReceived = { [weak self] in
            Task { @MainActor in
                self?.reloadUI()
            }
        }

        connectionManager.onConnectionStateChanged = { [weak self] sessionState in
            Task { @MainActor in
                self?.connectionState = .init(sessionState)
            }
        }
    }

    func disconnect() {
        connectionManager.disconnect()
    }

    func connect() {
        connectionManager.connect()
    }

    func toggleItem(_ item: TodoItem) {
        var newItem = item
        newItem.isCompleted.toggle()

        let update: Buffer = document.transactSync { [weak self] txn in
            guard let self = self else { return [] }
            guard let index = sharedItems.toArray(transaction: txn).firstIndex(of: item) else { return [] }
            self.sharedItems.remove(at: index, transaction: txn)
            self.sharedItems.insert(at: index, value: newItem, transaction: txn)
            return txn.transactionEncodeUpdate()
        }

        propagateUpdate(update)
    }

    func addItem(_ item: TodoItem) {
        let update: Buffer = document.transactSync { [weak self] txn in
            guard let self = self else { return [] }
            self.sharedItems.append(item, transaction: txn)
            return txn.transactionEncodeUpdate()
        }
        propagateUpdate(update)
    }

    func removeItem(_ item: TodoItem) {
        let update: Buffer = document.transactSync { [weak self] txn in
            guard let self = self else { return [] }
            guard let index = sharedItems.toArray(transaction: txn).firstIndex(of: item) else { return [] }
            self.sharedItems.remove(at: index, transaction: txn)
            return txn.transactionEncodeUpdate()
        }
        propagateUpdate(update)
    }

    private func propagateUpdate(_ update: Buffer) {
        guard !update.isEmpty else { return }
        reloadUI()
        connectionManager.sendEveryone(.init(kind: .UPDATE, buffer: update))
    }

    private func reloadUI() {
        withAnimation(.default) {
            items = sharedItems.toArray()
        }
    }
}
