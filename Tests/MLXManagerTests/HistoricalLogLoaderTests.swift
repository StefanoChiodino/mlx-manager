import Testing
@testable import MLXManager

@Suite("HistoricalLogLoader")
struct HistoricalLogLoaderTests {

    @Test("parses last N lines from file content")
    func parsesLastNLines() {
        let content = """
        some irrelevant line
        Prompt processing progress: 5/10
        KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens
        POST /v1/chat/completions HTTP/1.1" 200
        another irrelevant line
        """
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.lines.count == 5)
        #expect(result.lines[0].1 == .other)
        #expect(result.lines[1].1 == .progress)
        #expect(result.lines[2].1 == .kvCaches)
        #expect(result.lines[3].1 == .httpCompletion)
        #expect(result.lines[4].1 == .other)
    }

    @Test("extracts request records from complete sequences")
    func extractsRequestRecords() {
        let content = """
        Prompt processing progress: 5/10
        KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens
        """
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.records.count == 1)
        #expect(result.records[0].tokens == 100)
    }

    @Test("limits to last N lines")
    func limitsToLastNLines() {
        let lines = (1...200).map { "line \($0)" }
        let content = lines.joined(separator: "\n")
        let result = HistoricalLogLoader.load(from: content, maxLines: 50)
        #expect(result.lines.count == 50)
        #expect(result.lines[0].0 == "line 151")
    }

    @Test("incomplete request sequence produces no records")
    func incompleteSequenceNoRecords() {
        let content = "KV Caches: 1 seq, 2.50 GB, latest user cache 100 tokens"
        let result = HistoricalLogLoader.load(from: content, maxLines: 100)
        #expect(result.records.isEmpty)
    }

    @Test("empty content returns empty results")
    func emptyContent() {
        let result = HistoricalLogLoader.load(from: "", maxLines: 100)
        #expect(result.lines.isEmpty)
        #expect(result.records.isEmpty)
    }
}
