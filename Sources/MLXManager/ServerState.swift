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

    public init() {}

    public mutating func serverStarted() {
        status = .idle
    }

    public mutating func serverStopped() {
        status = .offline
        progress = nil
    }

    public mutating func handle(_ event: LogEvent) {
        guard status != .offline else { return }

        switch event {
        case let .progress(current, total, percentage):
            status = .processing
            progress = ProgressInfo(current: current, total: total, percentage: percentage)

        case let .kvCaches(gpu, tok):
            gpuGB = gpu
            tokens = tok
            if status == .processing {
                status = .idle
                progress = nil
            }

        case .httpCompletion:
            if status == .processing {
                status = .idle
                progress = nil
            }
        }
    }
}
