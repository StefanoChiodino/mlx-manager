import Foundation

/// A single RAM reading from the server process.
public struct RAMSample: Equatable {
    public let timestamp: Date
    public let gb: Double

    public init(timestamp: Date, gb: Double) {
        self.timestamp = timestamp
        self.gb = gb
    }
}

/// Abstraction over proc_pidinfo for testability.
public protocol PIDInfoProvider {
    func residentSetBytes(pid: Int32) -> UInt64
}

/// Real implementation using proc_pidinfo.
public final class RealPIDInfoProvider: PIDInfoProvider {
    public init() {}

    public func residentSetBytes(pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard ret == size else { return 0 }
        return info.pti_resident_size
    }
}

/// Polls a process's RAM usage at a fixed interval and emits RAMSample values.
public final class RAMPoller {
    public var onSample: ((RAMSample) -> Void)?

    private let pid: Int32
    private let interval: TimeInterval
    private let provider: PIDInfoProvider
    private var timer: DispatchSourceTimer?

    public init(pid: Int32, interval: TimeInterval, provider: PIDInfoProvider = RealPIDInfoProvider()) {
        self.pid = pid
        self.interval = interval
        self.provider = provider
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        let bytes = provider.residentSetBytes(pid: pid)
        let gb = Double(bytes) / 1_073_741_824
        let sample = RAMSample(timestamp: Date(), gb: gb)
        DispatchQueue.main.async { [weak self] in
            self?.onSample?(sample)
        }
    }
}
