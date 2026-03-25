import Foundation

/// Strips known log prefixes and formats lines for display in the menu bar.
///
/// - For `.progress` and `.kvCaches` events, returns a compact formatted string.
/// - For all other events (including `nil`), strips the timestamp prefix and truncates to 70 characters.
public enum LogLineStripper {

    private static let maxLength = 70

    /// Returns a compact string suitable for display in the status bar.
    ///
    /// - Parameters:
    ///   - line: The raw log line.
    ///   - event: The parsed event for this line, if any.
    public static func strip(_ line: String, event: LogEvent?) -> String {
        switch event {
        case .progress(let current, let total, _, _):
            return "\(current)/\(total)"
        case .kvCaches(let gpuGB, let tokens):
            return "\(String(format: "%.2f", gpuGB)) GB · \(tokens) tok"
        case .httpCompletion:
            return httpCompletionSummary(line)
        default:
            return truncated(stripped(line))
        }
    }

    // Extracts "POST /completions 200" from the access log line format:
    // 127.0.0.1 - - [date] "POST /v1/chat/completions HTTP/1.1" 200 -
    private static let httpSummaryRE = try! NSRegularExpression(
        pattern: #""?(POST|GET|PUT|DELETE|PATCH) (?:.*/)?([\w.]+) HTTP/[\d.]+"? (\d{3})"#
    )

    private static func httpCompletionSummary(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = httpSummaryRE.firstMatch(in: line, range: range),
              let r1 = Range(m.range(at: 1), in: line),
              let r2 = Range(m.range(at: 2), in: line),
              let r3 = Range(m.range(at: 3), in: line) else {
            return truncated(stripped(line))
        }
        return "\(line[r1]) /\(line[r2]) \(line[r3])"
    }

    private static func stripped(_ line: String) -> String {
        // Rule 1: datetime INFO prefix
        if let range = line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d+ - INFO - "#,
                                   options: .regularExpression) {
            return String(line[range.upperBound...])
        }
        // Rule 2: INFO: followed by one or more spaces
        if let range = line.range(of: #"^INFO:\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...])
        }
        return line
    }

    private static func truncated(_ s: String) -> String {
        guard s.count > maxLength else { return s }
        let end = s.index(s.startIndex, offsetBy: maxLength)
        return String(s[..<end]) + "…"
    }
}
