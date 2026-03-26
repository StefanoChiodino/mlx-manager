import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.mlx-manager", category: "gateway")

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
    private var stopped = false

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
            switch state {
            case .ready:
                logger.info("gateway listener ready on port \(routing.publicPort)")
            case let .failed(error):
                logger.error("gateway listener failed: \(error)")
                self.onError?(error)
                self.stop()
            case .cancelled:
                logger.info("gateway listener cancelled")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection, routing: routing)
        }
        self.listener = listener
        stopped = false
        listener.start(queue: queue)
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        let sessionCount = sessions.count
        logger.info("gateway stopping — \(sessionCount) active session(s)")

        // Cancel sessions first so their connections are torn down cleanly
        // before the listener is cancelled.
        let currentSessions = sessions.values
        sessions.removeAll()
        for session in currentSessions {
            session.cancel()
        }

        listener?.cancel()
        listener = nil
    }

    private func accept(connection: NWConnection, routing: ManagedGatewayRouting) {
        let session = ManagedGatewayConnectionSession(
            connection: connection,
            processor: ManagedGatewayRequestProcessor(routing: routing, upstreamClient: upstreamClient),
            queue: queue
        ) { [weak self] session in
            let id = ObjectIdentifier(session)
            self?.sessions.removeValue(forKey: id)
            logger.debug("gateway session finished, \(self?.sessions.count ?? 0) remaining")
        }
        sessions[ObjectIdentifier(session)] = session
        logger.debug("gateway session accepted, \(self.sessions.count) active")
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
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case let .failed(error):
                logger.error("gateway connection failed: \(error)")
                self.finish()
            case .cancelled:
                logger.debug("gateway connection cancelled")
            default:
                break
            }
        }
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

            if let error {
                logger.warning("gateway receive error: \(error)")
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
        guard !finished else { return }
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
