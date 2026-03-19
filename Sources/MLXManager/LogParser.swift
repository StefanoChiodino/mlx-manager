/// Events that can be extracted from a single MLX server log line.
public enum LogEvent: Equatable {
    case progress(current: Int, total: Int, percentage: Double)
    case kvCaches(gpuGB: Double, tokens: Int)
    case httpCompletion
}

/// Pure log-line classifier. No state, no I/O.
public enum LogParser {
    public static func parse(line: String) -> LogEvent? {
        return nil
    }
}
