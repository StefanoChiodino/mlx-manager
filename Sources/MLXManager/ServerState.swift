import Foundation

/// The three possible states of the MLX server.
public enum ServerStatus: Equatable {
    case offline
    case idle
    case processing
    case failed
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
    private var firstProgressAt: Date? = nil
    private var lastProgressAt: Date? = nil
    private var lastProgressTokens: Int = 0
    private var progressCount: Int = 0
    private var pendingPrefillTPS: Double? = nil

    public init() {}

    public mutating func serverStarted() {
        status = .idle
    }

    public mutating func serverStopped() {
        status = .offline
        progress = nil
        requestStartedAt = nil
        completedRequest = nil
        firstProgressAt = nil
        lastProgressAt = nil
        lastProgressTokens = 0
        progressCount = 0
        pendingPrefillTPS = nil
    }

    public mutating func serverCrashed() {
        status = .failed
        progress = nil
        requestStartedAt = nil
        completedRequest = nil
        firstProgressAt = nil
        lastProgressAt = nil
        lastProgressTokens = 0
        progressCount = 0
        pendingPrefillTPS = nil
    }

    public mutating func clearCompletedRequest() {
        completedRequest = nil
    }

    public mutating func handle(_ event: LogEvent) {
        guard status != .offline else { return }

        switch event {
        case let .progress(current, total, percentage, timestamp):
            if requestStartedAt == nil {
                requestStartedAt = Date()
            }
            if progressCount == 0 {
                firstProgressAt = timestamp
            }
            lastProgressAt = timestamp
            lastProgressTokens = current
            progressCount += 1
            status = .processing
            progress = ProgressInfo(current: current, total: total, percentage: percentage)

        case let .kvCaches(gpu, tok):
            flushPrefillAccumulator()
            gpuGB = gpu
            tokens = tok
            if status == .processing {
                emitRecord(tokens: tok)
                status = .idle
                progress = nil
            }

        case .httpCompletion:
            flushPrefillAccumulator()
            if status == .processing {
                emitRecord(tokens: tokens ?? 0)
                status = .idle
                progress = nil
            }
        }
    }

    // MARK: - Private

    private mutating func flushPrefillAccumulator() {
        if progressCount >= 2,
           let first = firstProgressAt,
           let last = lastProgressAt {
            let elapsed = last.timeIntervalSince(first)
            if elapsed >= 0.1 {
                pendingPrefillTPS = Double(lastProgressTokens) / elapsed
            }
        }
        firstProgressAt = nil
        lastProgressAt = nil
        lastProgressTokens = 0
        progressCount = 0
    }

    private mutating func emitRecord(tokens: Int) {
        guard let start = requestStartedAt else { return }
        completedRequest = RequestRecord(
            startedAt: start,
            completedAt: Date(),
            tokens: tokens,
            prefillTPS: pendingPrefillTPS
        )
        requestStartedAt = nil
    }
}
