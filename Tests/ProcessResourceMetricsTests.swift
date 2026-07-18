import Foundation

private func counters(version: Int = 6,
                      energy: UInt64? = 0,
                      maintenance: UInt64? = 0,
                      utility: UInt64? = 0) -> ProcessResourceCounters {
    let hasQoSCounters = version >= 3
    let hasEnergyCounters = version >= 6
    return ProcessResourceCounters(
        rusageVersion: version,
        directEnergyNJ: hasEnergyCounters ? energy : nil,
        billedEnergyNJ: hasEnergyCounters ? energy : nil,
        servicedEnergyNJ: hasEnergyCounters ? energy : nil,
        qosDefaultNS: hasQoSCounters ? 0 : nil,
        qosMaintenanceNS: hasQoSCounters ? maintenance : nil,
        qosBackgroundNS: hasQoSCounters ? 0 : nil,
        qosUtilityNS: hasQoSCounters ? utility : nil,
        qosLegacyNS: hasQoSCounters ? 0 : nil,
        qosUserInitiatedNS: hasQoSCounters ? 0 : nil,
        qosUserInteractiveNS: hasQoSCounters ? 0 : nil
    )
}

private func snapshot(pid: Int32, start: UInt64,
                      counters: ProcessResourceCounters?) -> ProcessSnapshot {
    ProcessSnapshot(identity: ProcessIdentity(pid: pid, startID: start),
                    parentPID: 1, name: "game", path: "", commandLine: "",
                    cpuPercent: 0, memoryBytes: 0, niceValue: 0,
                    resourceCounters: counters)
}

@main
struct ProcessResourceMetricsTests {
    static func main() {
        var cache = ProcessResourceObservationCache()
        let first = snapshot(pid: 42, start: 100,
                             counters: counters(energy: 1_000, maintenance: 50))
        precondition(cache.update([first]).isEmpty)

        let second = snapshot(pid: 42, start: 100,
                              counters: counters(energy: 1_600, maintenance: 350, utility: 20))
        let deltas = cache.update([second])
        precondition(deltas[first.identity]?.directEnergyNJ == 600)
        precondition(deltas[first.identity]?.qosMaintenanceNS == 300)

        let metrics = ProcessTreeResourceMetrics.aggregate(tree: [second], deltas: deltas)
        precondition(metrics.directEnergyNJ == 600)
        precondition(metrics.qosMaintenanceNS == 300)
        let evidence = QoSEvidence.evaluate(requestedClass: .maintenance,
                                            requestAccepted: true,
                                            requestFailed: false,
                                            metrics: metrics)
        precondition(evidence.state == .confirmed)
        precondition(QoSEvidence.evaluate(requestedClass: .background,
                                          requestAccepted: true,
                                          requestFailed: false,
                                          metrics: metrics).state == .notObserved)
        let idleMetrics = ProcessTreeResourceMetrics(
            processCount: 1, sampledProcessCount: 1,
            qosSampledProcessCount: 1, directEnergySampledProcessCount: 0,
            maximumRusageVersion: 6, directEnergyNJ: nil,
            billedEnergyNJ: nil, servicedEnergyNJ: nil,
            qosDefaultNS: 0, qosMaintenanceNS: 0, qosBackgroundNS: 0,
            qosUtilityNS: 0, qosLegacyNS: 0, qosUserInitiatedNS: 0,
            qosUserInteractiveNS: 0
        )
        precondition(QoSEvidence.evaluate(requestedClass: .maintenance,
                                          requestAccepted: true,
                                          requestFailed: false,
                                          metrics: idleMetrics).state == .inferred)
        precondition(QoSEvidence.evaluate(requestedClass: .maintenance,
                                          requestAccepted: false,
                                          requestFailed: true,
                                          metrics: metrics).state == .failed)

        // El mismo PID con otra fecha de inicio debe comenzar una serie nueva.
        let reused = snapshot(pid: 42, start: 200,
                              counters: counters(energy: 9_000, maintenance: 9_000))
        precondition(cache.update([reused]).isEmpty)

        let v2 = snapshot(pid: 99, start: 300,
                          counters: counters(version: 2, energy: nil,
                                             maintenance: nil, utility: nil))
        _ = cache.update([v2])
        let v2Next = snapshot(pid: 99, start: 300,
                              counters: counters(version: 2, energy: nil,
                                                 maintenance: nil, utility: nil))
        let v2Metrics = ProcessTreeResourceMetrics.aggregate(
            tree: [v2Next], deltas: cache.update([v2Next])
        )
        precondition(QoSEvidence.evaluate(requestedClass: .utility,
                                          requestAccepted: true,
                                          requestFailed: false,
                                          metrics: v2Metrics).state == .unavailable,
                     "V2 no debe simular contadores QoS")

        // V3 publica QoS efectivo, pero no los campos de energía de V6.
        var v3Cache = ProcessResourceObservationCache()
        let v3First = snapshot(pid: 100, start: 400,
                               counters: counters(version: 3, maintenance: 10))
        let v3Next = snapshot(pid: 100, start: 400,
                              counters: counters(version: 3, maintenance: 40))
        _ = v3Cache.update([v3First])
        let v3Metrics = ProcessTreeResourceMetrics.aggregate(
            tree: [v3Next], deltas: v3Cache.update([v3Next])
        )
        precondition(v3Metrics.directEnergyNJ == nil,
                     "V3 no debe simular energía exclusiva de V6")
        precondition(v3Metrics.qosMaintenanceNS == 30,
                     "V3 debe conservar los deltas QoS")
        precondition(QoSEvidence.evaluate(requestedClass: .maintenance,
                                          requestAccepted: true,
                                          requestFailed: false,
                                          metrics: v3Metrics).state == .confirmed)
        print("ProcessResourceMetricsTests: OK")
    }
}
