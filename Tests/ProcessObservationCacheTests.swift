import Foundation

private func snapshot(pid: Int32, command: String = "") -> ProcessSnapshot {
    ProcessSnapshot(identity: ProcessIdentity(pid: pid, startID: UInt64(pid) * 10),
                    parentPID: 1,
                    name: "wine64-preloader",
                    path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/wine64-preloader",
                    commandLine: command,
                    cpuPercent: 42,
                    memoryBytes: 1024,
                    niceValue: 0)
}

@main
private enum ProcessObservationCacheTests {
    static func main() {
        var cache = ProcessObservationCache()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let original = snapshot(pid: 501, command: "PRAGMATA.exe")

        let first = cache.merge(current: [original], now: t0, graceInterval: 3, shouldRetain: { _ in true }) { _ in true }
        precondition(first.count == 1)
        precondition(first[0].cpuPercent == 42)

        let retained = cache.merge(current: [], now: t0.addingTimeInterval(1), graceInterval: 3, shouldRetain: { _ in true }) { _ in true }
        precondition(retained.count == 1)
        precondition(retained[0].commandLine == "PRAGMATA.exe")
        precondition(retained[0].cpuPercent == 0)

        let dead = cache.merge(current: [], now: t0.addingTimeInterval(2), graceInterval: 3, shouldRetain: { _ in true }) { _ in false }
        precondition(dead.isEmpty)

        var expiryCache = ProcessObservationCache()
        _ = expiryCache.merge(current: [original], now: t0, graceInterval: 3, shouldRetain: { _ in true }) { _ in true }
        let expired = expiryCache.merge(current: [], now: t0.addingTimeInterval(4), graceInterval: 3, shouldRetain: { _ in true }) { _ in true }
        precondition(expired.isEmpty)

        print("ProcessObservationCacheTests: OK")
    }
}
