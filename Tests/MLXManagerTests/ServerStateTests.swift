import Foundation
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
        state.handle(.progress(current: 100, total: 1000, percentage: 10.0, timestamp: Date()))
        state.serverStopped()
        #expect(state.status == .offline)
        #expect(state.progress == nil)
    }

    @Test("serverCrashed transitions processing → failed and clears progress")
    func serverCrashedFromProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 1000, percentage: 10.0, timestamp: Date()))
        state.serverCrashed()
        #expect(state.status == .failed)
        #expect(state.progress == nil)
    }

    // MARK: - Idle → Processing transition (progress event)

    @Test("Progress event transitions idle → processing")
    func progressTransitionsToProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97, timestamp: Date()))
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
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97, timestamp: Date()))
        state.handle(.progress(current: 8192, total: 41061, percentage: 19.95, timestamp: Date()))
        #expect(state.status == .processing)
        #expect(state.progress?.current == 8192)
    }

    // MARK: - Near-complete stays processing

    @Test("Near-complete progress stays processing until completion signal")
    func nearCompleteStaysProcessing() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 41056, total: 41061, percentage: 99.99, timestamp: Date()))
        #expect(state.status == .processing)
    }

    // MARK: - KV Caches completes request → idle

    @Test("KV Caches event transitions processing → idle")
    func kvCachesCompletesRequest() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 41056, total: 41061, percentage: 99.99, timestamp: Date()))
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
        state.handle(.progress(current: 4096, total: 41061, percentage: 9.97, timestamp: Date()))
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
        state.handle(.progress(current: 100, total: 1000, percentage: 10.0, timestamp: Date()))
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

    // MARK: - HTTP completion while idle does not emit a record

    @Test("HTTP completion while idle does not emit a completed request record")
    func httpCompletionWhileIdleDoesNotEmitRecord() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.httpCompletion)
        #expect(state.completedRequest == nil)
    }

    // MARK: - Prefill TPS accumulator

    @Test("Two consecutive progress events produce prefillTPS in completed record")
    func twoConsecutiveProgressLines_producesPrefillTPS() {
        var state = ServerState()
        state.serverStarted()
        let t1 = Date()
        let t2 = t1.addingTimeInterval(1.0)
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
        state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t2))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
        let tps = state.completedRequest?.prefillTPS
        #expect(tps != nil)
        #expect(abs(tps! - 2000.0) < 1.0)
    }

    @Test("Single progress line produces nil prefillTPS")
    func singleProgressLine_nilPrefillTPS() {
        var state = ServerState()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
        #expect(state.completedRequest?.prefillTPS == nil)
    }

    @Test("Interrupted progress batch produces nil prefillTPS")
    func interruptedProgressBatch_nilPrefillTPS() {
        var state = ServerState()
        state.serverStarted()
        let t1 = Date()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 1000))
        state.clearCompletedRequest()
        let t2 = t1.addingTimeInterval(2.0)
        state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t2))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
        #expect(state.completedRequest?.prefillTPS == nil)
    }

    @Test("Elapsed less than 0.1s does not update pendingPrefillTPS")
    func tooShortElapsed_doesNotUpdatePrefillTPS() {
        var state = ServerState()
        state.serverStarted()
        let t = Date()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t))
        state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t.addingTimeInterval(0.05)))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
        #expect(state.completedRequest?.prefillTPS == nil)
    }

    @Test("pendingPrefillTPS persists across non-qualifying request")
    func pendingPrefillTPS_persistsAcrossNonQualifyingRequest() {
        var state = ServerState()
        state.serverStarted()
        let t1 = Date()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
        state.handle(.progress(current: 2000, total: 5000, percentage: 40.0, timestamp: t1.addingTimeInterval(1.0)))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 2000))
        let firstTPS = state.completedRequest?.prefillTPS
        state.clearCompletedRequest()
        #expect(firstTPS != nil)
        state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
        #expect(state.completedRequest?.prefillTPS == firstTPS)
    }

    @Test("Accumulator resets on serverStopped")
    func accumulatorResetsOnServerStopped() {
        var state = ServerState()
        state.serverStarted()
        let t1 = Date()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
        state.serverStopped()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
        #expect(state.completedRequest?.prefillTPS == nil)
    }

    @Test("Accumulator resets on serverCrashed")
    func accumulatorResetsOnServerCrashed() {
        var state = ServerState()
        state.serverStarted()
        let t1 = Date()
        state.handle(.progress(current: 1000, total: 5000, percentage: 20.0, timestamp: t1))
        state.serverCrashed()
        state.serverStarted()
        state.handle(.progress(current: 100, total: 200, percentage: 50.0, timestamp: Date()))
        state.handle(.kvCaches(gpuGB: 1.0, tokens: 100))
        #expect(state.completedRequest?.prefillTPS == nil)
    }
}
