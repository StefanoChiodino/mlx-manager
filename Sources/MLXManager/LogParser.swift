import Foundation

/// Events that can be extracted from a single MLX server log line.
public enum LogEvent: Equatable {
    case progress(current: Int, total: Int, percentage: Double, timestamp: Date)
    case kvCaches(gpuGB: Double, tokens: Int)
    case httpCompletion

    // Equality ignores timestamp so LogTailer tests can compare parsed events
    // without needing to match the exact capture time.
    public static func == (lhs: LogEvent, rhs: LogEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.progress(lc, lt, lp, _), .progress(rc, rt, rp, _)):
            return lc == rc && lt == rt && lp == rp
        case let (.kvCaches(lg, lk), .kvCaches(rg, rk)):
            return lg == rg && lk == rk
        case (.httpCompletion, .httpCompletion):
            return true
        default:
            return false
        }
    }
}

public enum LogLineKind: Equatable {
    case progress, kvCaches, httpCompletion, warning, other

    public init(_ event: LogEvent) {
        switch event {
        case .progress:       self = .progress
        case .kvCaches:       self = .kvCaches
        case .httpCompletion: self = .httpCompletion
        }
    }
}

/// Pure log-line classifier. No state, no I/O.
public enum LogParser {

    // MARK: - Pre-compiled patterns

    private static let progressRE = try! NSRegularExpression(
        pattern: #"Prompt processing progress:\s*(\d+)/(\d+)"#
    )
    private static let kvCachesRE = try! NSRegularExpression(
        pattern: #"KV Caches:.*?([\d.]+)\s+GB,.*?(\d+)\s+tokens"#
    )
    private static let httpCompletionRE = try! NSRegularExpression(
        pattern: #"POST /v1/chat/completions HTTP/1\.1" 200"#
    )
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return f
    }()

    // MARK: - Public API

    public static func parse(line: String) -> LogEvent? {
        let range = NSRange(line.startIndex..., in: line)

        if let m = progressRE.firstMatch(in: line, range: range),
           let r1 = Range(m.range(at: 1), in: line),
           let r2 = Range(m.range(at: 2), in: line),
           let current = Int(line[r1]),
           let total = Int(line[r2]),
           let timestamp = timestampFormatter.date(from: String(line.prefix(23))) {
            return .progress(
                current: current,
                total: total,
                percentage: (Double(current) / Double(total)) * 100,
                timestamp: timestamp
            )
        }

        if let m = kvCachesRE.firstMatch(in: line, range: range),
           let r1 = Range(m.range(at: 1), in: line),
           let r2 = Range(m.range(at: 2), in: line),
           let gpuGB = Double(line[r1]),
           let tokens = Int(line[r2]) {
            return .kvCaches(gpuGB: gpuGB, tokens: tokens)
        }

        if httpCompletionRE.firstMatch(in: line, range: range) != nil {
            return .httpCompletion
        }

        return nil
    }
}
