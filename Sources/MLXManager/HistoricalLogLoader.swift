import Foundation

public struct HistoricalLogResult {
    public let lines: [(String, LogLineKind)]
    public let records: [RequestRecord]
}

public enum HistoricalLogLoader {

    public static func load(from content: String, maxLines: Int) -> HistoricalLogResult {
        let allLines = content.components(separatedBy: "\n")
        let tail = allLines.suffix(maxLines)

        var lines: [(String, LogLineKind)] = []
        var records: [RequestRecord] = []
        var state = ServerState()
        state.serverStarted()

        for line in tail where !line.isEmpty {
            if let event = LogParser.parse(line: line) {
                lines.append((line, LogLineKind(event)))
                state.handle(event)
                if let record = state.completedRequest {
                    records.append(record)
                    state.clearCompletedRequest()
                }
            } else {
                lines.append((line, .other))
            }
        }

        return HistoricalLogResult(lines: lines, records: records)
    }
}
