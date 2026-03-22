import Foundation

/// Strips known log prefixes and truncates lines for display in the menu bar.
public enum LogLineStripper {

    private static let maxLength = 70

    /// Strip known prefixes from `line`, then truncate to 70 Swift Characters.
    /// Rules applied in order (first match wins):
    ///   1. `YYYY-MM-DD HH:MM:SS,mmm - INFO - ` (mlx_lm.server format)
    ///   2. `INFO: ` followed by one or more spaces (uvicorn/vision format)
    /// Lines matching no rule are returned as-is (before truncation).
    public static func strip(_ line: String) -> String {
        let stripped = stripped(line)
        return truncated(stripped)
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
