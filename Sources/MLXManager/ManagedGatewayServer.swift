import Foundation
import Network

/// Errors from the managed gateway listener.
public enum ManagedGatewayServerError: Error {
    case invalidPort(Int)
}

/// Lightweight HTTP proxy that owns the public endpoint and forwards to a hidden backend port.
public final class ManagedGatewayServer {
    private let upstreamClient: GatewayUpstreamClient
    private let queue = DispatchQueue(label: "com.mlx-manager.gateway")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: ManagedGatewayConnectionSession] = [:]

    public var onError: ((Error) -> Void)?

    public init(upstreamClient: GatewayUpstreamClient = URLSessionGatewayUpstreamClient()) {
        self.upstreamClient = upstreamClient
    }

    public func start(routing: ManagedGatewayRouting) throws {
        stop()

        guard let port = NWEndpoint.Port(rawValue: UInt16(routing.publicPort)) else {
            throw ManagedGatewayServerError.invalidPort(routing.publicPort)
        }

        let listener = try NWListener(using: .tcp, on: port)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case let .failed(error) = state {
                self.onError?(error)
                self.stop()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection, routing: routing)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        let currentSessions = sessions.values
        sessions.removeAll()
        for session in currentSessions {
            session.cancel()
        }
    }

    private func accept(connection: NWConnection, routing: ManagedGatewayRouting) {
        let session = ManagedGatewayConnectionSession(
            connection: connection,
            processor: ManagedGatewayRequestProcessor(routing: routing, upstreamClient: upstreamClient),
            queue: queue
        ) { [weak self] session in
            self?.sessions.removeValue(forKey: ObjectIdentifier(session))
        }
        sessions[ObjectIdentifier(session)] = session
        session.start()
    }
}

private final class ManagedGatewayConnectionSession {
    private let connection: NWConnection
    private let processor: ManagedGatewayRequestProcessor
    private let queue: DispatchQueue
    private let onFinish: (ManagedGatewayConnectionSession) -> Void
    private var buffer = Data()
    private var finished = false

    init(
        connection: NWConnection,
        processor: ManagedGatewayRequestProcessor,
        queue: DispatchQueue,
        onFinish: @escaping (ManagedGatewayConnectionSession) -> Void
    ) {
        self.connection = connection
        self.processor = processor
        self.queue = queue
        self.onFinish = onFinish
    }

    func start() {
        connection.start(queue: queue)
        receiveNextChunk()
    }

    func cancel() {
        finish()
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }

            if let data, !data.isEmpty {
                self.buffer.append(data)
            }

            if error != nil {
                self.sendCurrentBufferAndFinish()
                return
            }

            if GatewayHTTPCodec.parseRequest(from: self.buffer) != nil || isComplete {
                self.sendCurrentBufferAndFinish()
                return
            }

            self.receiveNextChunk()
        }
    }

    private func sendCurrentBufferAndFinish() {
        let rawRequest = buffer
        Task { [weak self] in
            guard let self else { return }
            let response = await processor.process(rawRequest: rawRequest)
            await self.sendAndFinish(response)
        }
    }

    private func sendAndFinish(_ data: Data) async {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onFinish(self)
    }
}
