import Testing
@testable import MLXManager

@Suite("ServerState")
struct ServerStateTests {

    // MARK: - Initial state

    @Test("Initial state is offline")
    func initialStateIsOffline() {
        let state = ServerState()
        #expect(state.status == .offline)
        #expect(state.progress == nil)
        #expect(state.gpuGB == nil)
        #expect(state.tokens == nil)
    }

    // MARK: - Offline → Idle transition

    @Test("serverStarted transitions offline → idle")
    func serverStartedTransition() {
        var state = ServerState()
        state.serverStarted()
        #expect(state.status == .idle)
    }

    // MARK: - Idle → Offline transition

    @Test("serverStopped transitions idle → offline")
    func serverStoppedFromIdle() {
        var state = ServerState()
        state.serverStarted()
        state.serverStopped()
        #expect(state.status == .offline)
    }

    // MARK: - Processing → Offline transition

    @Test("serverStopped transitions processing → offline and clears progress")
    func serverStoppedFromProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 1000, percentage: 10.0))
        state.serverStopped()
        #expect(state.status == .offline)
        #expect(state.progress == nil)
    }

    // MARK: - Idle → Processing transition (progress event)

    @Test("Progress event transitions idle → processing")
    func progressTransitionsToProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        #expect(state.status == .processing)
        #expect(state.progress?.current == 4096)
        #expect(state.progress?.total == 41061)
        #expect(state.progress?.percentage != nil)
    }

    // MARK: - Processing stays processing on more progress

    @Test("Subsequent progress events update progress values")
    func subsequentProgressUpdates() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        state.handle(.progress(current: 8192, total: 41061, percentage: 19.95))
        #expect(state.status == .processing)
        #expect(state.progress?.current == 8192)
    }

    // MARK: - Near-complete stays processing

    @Test("Near-complete progress stays processing until completion signal")
    func nearCompleteStaysProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 41056, total: 41061, percentage: 99.99))
        #expect(state.status == .processing)
    }

    // MARK: - KV Caches completes request → idle

    @Test("KV Caches event transitions processing → idle")
    func kvCachesCompletesRequest() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 41056, total: 41061, percentage: 99.99))
        state.handle(.kvCaches(gpuGB: 1.75, tokens: 25724))
        #expect(state.status == .idle)
        #expect(state.progress == nil)
        #expect(state.gpuGB == 1.75)
        #expect(state.tokens == 25724)
    }

    // MARK: - HTTP completion completes request → idle

    @Test("HTTP completion event transitions processing → idle")
    func httpCompletionCompletesRequest() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97))
        state.handle(.httpCompletion)
        #expect(state.status == .idle)
        #expect(state.progress == nil)
    }

    // MARK: - KV Caches while idle updates GPU info

    @Test("KV Caches while idle updates GPU info and stays idle")
    func kvCachesWhileIdleUpdatesInfo() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.kvCaches(gpuGB: 0.0, tokens: 0))
        #expect(state.status == .idle)
        #expect(state.gpuGB == 0.0)
        #expect(state.tokens == 0)
    }

    // MARK: - Events ignored while offline

    @Test("Events are ignored while offline")
    func eventsIgnoredWhileOffline() {
        var state = ServerState()
        state.handle(.progress(current: 100, total: 1000, percentage: 10.0))
        #expect(state.status == .offline)
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 500))
        #expect(state.status == .offline)
        state.handle(.httpCompletion)
        #expect(state.status == .offline)
    }

    // MARK: - HTTP completion while idle stays idle

    @Test("HTTP completion while idle stays idle")
    func httpCompletionWhileIdleStaysIdle() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.httpCompletion)
        #expect(state.status == .idle)
    }
}
