import Foundation

/// The three possible states of the MLX server.
public enum ServerStatus: Equatable {
    case offline
    case idle
    case processing
}

/// Progress info for an active request.
public struct ProgressInfo: Equatable {
    public let current: Int
    public let total: Int
    public let percentage: Double
}

/// State machine that tracks MLX server status by consuming LogEvents.
public struct ServerState: Equatable {
    public private(set) var status: ServerStatus = .offline
    public private(set) var progress: ProgressInfo? = nil
    public private(set) var gpuGB: Double? = nil
    public private(set) var tokens: Int? = nil

    /// Set when a request completes; caller should drain and call clearCompletedRequest().
    public private(set) var completedRequest: RequestRecord? = nil

    private var requestStartedAt: Date? = nil

    public init() {}

    public mutating func serverStarted() {
        status = .idle
    }

    public mutating func serverStopped() {
        status = .offline
        progress = nil
        requestStartedAt = nil
        completedRequest = nil
    }

    public mutating func clearCompletedRequest() {
        completedRequest = nil
    }

    public mutating func handle(_ event: LogEvent) {
        guard status != .offline else { return }

        switch event {
        case let .progress(current, total, percentage):
            if requestStartedAt == nil {
                requestStartedAt = Date()
            }
            status = .processing
            progress = ProgressInfo(current: current, total: total, percentage: percentage)

        case let .kvCaches(gpu, tok):
            gpuGB = gpu
            tokens = tok
            if status == .processing {
                emitRecord(tokens: tok)
                status = .idle
                progress = nil
            }

        case .httpCompletion:
            if status == .processing {
                emitRecord(tokens: tokens ?? 0)
                status = .idle
                progress = nil
            }
        }
    }

    // MARK: - Private

    private mutating func emitRecord(tokens: Int) {
        guard let start = requestStartedAt else { return }
        completedRequest = RequestRecord(startedAt: start, completedAt: Date(), tokens: tokens)
        requestStartedAt = nil
    }
}
