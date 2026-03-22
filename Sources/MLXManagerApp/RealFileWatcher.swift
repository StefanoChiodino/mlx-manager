import Foundation
import MLXManager

/// Wraps Foundation's FileHandle to satisfy the non-throwing FileHandleReading protocol.
final class RealFileHandle: FileHandleReading {
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    @discardableResult
    func seekToEnd() -> UInt64 {
        (try? handle.seekToEnd()) ?? 0
    }

    func seek(toFileOffset offset: UInt64) {
        try? handle.seek(toOffset: offset)
    }

    func readDataToEndOfFile() -> Data {
        handle.availableData
    }

    var offsetInFile: UInt64 {
        (try? handle.offset()) ?? 0
    }

    var inode: UInt64 {
        var st = Darwin.stat()
        guard fstat(handle.fileDescriptor, &st) == 0 else { return 0 }
        return UInt64(st.st_ino)
    }
}

/// Production FileWatcher using GCD DispatchSource.
final class RealFileWatcher: FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func startWatching(path: String, handler: @escaping () -> Void) -> Bool {
        let fd = open(path, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return false }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { handler() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        return true
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}
