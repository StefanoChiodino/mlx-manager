import Foundation

/// Abstraction over file reading for testability.
public protocol FileHandleReading: AnyObject {
    @discardableResult
    func seekToEnd() -> UInt64
    func seek(toFileOffset offset: UInt64)
    func readDataToEndOfFile() -> Data
    var offsetInFile: UInt64 { get }
    var inode: UInt64 { get }
}

/// Abstraction over file system watching for testability.
public protocol FileWatcher: AnyObject {
    func startWatching(path: String, handler: @escaping () -> Void) -> Bool
    func stopWatching()
}


/// Tails a log file and emits parsed LogEvents via a callback.
public final class LogTailer {
    public typealias EventHandler = (LogEvent) -> Void

    private let path: String
    private let fileHandleFactory: (String) -> FileHandleReading?
    private let watcher: FileWatcher
    private let onEvent: EventHandler
    private let inodeReader: (String) -> UInt64?
    private var fileHandle: FileHandleReading?
    private var lastOffset: UInt64 = 0
    private var lineBuffer: String = ""

    public init(
        path: String,
        fileHandleFactory: @escaping (String) -> FileHandleReading?,
        watcher: FileWatcher,
        onEvent: @escaping EventHandler,
        inodeReader: @escaping (String) -> UInt64? = { p in var s = stat(); return stat(p, &s) == 0 ? UInt64(s.st_ino) : nil }
    ) {
        self.path = path
        self.fileHandleFactory = fileHandleFactory
        self.watcher = watcher
        self.onEvent = onEvent
        self.inodeReader = inodeReader
    }

    /// Start tailing from the current end of file.
    public func start() {
        guard let handle = fileHandleFactory(path) else { return }
        fileHandle = handle
        lastOffset = handle.seekToEnd()
        _ = watcher.startWatching(path: path) { [weak self] in
            self?.readNewContent()
        }
    }

    /// Stop tailing and release resources.
    public func stop() {
        watcher.stopWatching()
        fileHandle = nil
        lineBuffer = ""
    }

    private func readNewContent() {
        // Detect log rotation: on-disk inode differs from our open handle's inode
        if let diskInode = inodeReader(path), let handle = fileHandle, diskInode != handle.inode {
            reopenFile()
            return
        }

        guard let handle = fileHandle else { return }

        // Detect truncation: file is shorter than our last read position
        let currentSize = handle.seekToEnd()
        if currentSize < lastOffset {
            lastOffset = 0
            lineBuffer = ""
        }

        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        lastOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8) else { return }
        lineBuffer += text

        // Process complete lines (those ending with \n)
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

            if let event = LogParser.parse(line: line) {
                onEvent(event)
            }
        }
    }

    private func reopenFile() {
        watcher.stopWatching()
        fileHandle = nil
        lastOffset = 0
        lineBuffer = ""

        guard let handle = fileHandleFactory(path) else { return }
        fileHandle = handle
        lastOffset = 0
        _ = watcher.startWatching(path: path) { [weak self] in
            self?.readNewContent()
        }
        // Read any content already in the new file from the start
        readNewContent()
    }
}
