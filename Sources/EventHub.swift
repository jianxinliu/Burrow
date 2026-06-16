//
//  EventHub.swift
//  Burrow
//
//  The fan-out behind the SSE /events stream (roadmap B.6). Holds the open
//  event-stream connections and broadcasts already-encoded SSE frames to them;
//  dead connections self-evict on the next failed write or keep-alive tick, so
//  there's no per-connection teardown plumbing to leak. Thread-safe.
//

import Foundation
import Network

final class EventHub {
    static let shared = EventHub()

    private let lock = NSLock()
    private var conns: [ObjectIdentifier: NWConnection] = [:]
    private var keepAlive: Timer?

    private init() {}

    func register(_ conn: NWConnection) {
        lock.lock(); conns[ObjectIdentifier(conn)] = conn; lock.unlock()
        startKeepAlive()
    }

    func deregister(_ conn: NWConnection) {
        lock.lock(); conns[ObjectIdentifier(conn)] = nil; lock.unlock()
    }

    /// Is this connection an active event stream? The query server uses this
    /// to exempt /events connections from its short idle-cancel timeout.
    func isStreaming(_ conn: NWConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return conns[ObjectIdentifier(conn)] != nil
    }

    /// Fan an SSE-encoded frame out to every open connection, evicting any that
    /// error on write.
    func broadcast(_ frame: String) {
        let data = Data(frame.utf8)
        lock.lock(); let all = conns; lock.unlock()
        for (id, c) in all {
            c.send(content: data, completion: .contentProcessed { [weak self] err in
                if err != nil { self?.deregisterID(id) }
            })
        }
    }

    private func deregisterID(_ id: ObjectIdentifier) {
        lock.lock(); conns[id] = nil; lock.unlock()
    }

    private func startKeepAlive() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.keepAlive == nil else { return }
            let t = Timer(timeInterval: 15, repeats: true) { _ in
                EventHub.shared.broadcast(SSE.comment("keep-alive"))
            }
            RunLoop.main.add(t, forMode: .common)
            self.keepAlive = t
        }
    }
}
