import Foundation

struct ProcessResourceDelta: Equatable {
    let rusageVersion: Int
    let directEnergyNJ: UInt64?
    let billedEnergyNJ: UInt64?
    let servicedEnergyNJ: UInt64?
    let qosDefaultNS: UInt64?
    let qosMaintenanceNS: UInt64?
    let qosBackgroundNS: UInt64?
    let qosUtilityNS: UInt64?
    let qosLegacyNS: UInt64?
    let qosUserInitiatedNS: UInt64?
    let qosUserInteractiveNS: UInt64?

    var qosTotalNS: UInt64? {
        let values = [qosDefaultNS, qosMaintenanceNS, qosBackgroundNS,
                      qosUtilityNS, qosLegacyNS, qosUserInitiatedNS,
                      qosUserInteractiveNS].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, &+)
    }
}

/// Calcula deltas únicamente dentro de una identidad PID+fecha de inicio. Los
/// contadores que retroceden se descartan en vez de fabricar actividad.
struct ProcessResourceObservationCache {
    private var previousByIdentity: [ProcessIdentity: ProcessResourceCounters] = [:]

    mutating func update(_ snapshots: [ProcessSnapshot]) -> [ProcessIdentity: ProcessResourceDelta] {
        var next: [ProcessIdentity: ProcessResourceCounters] = [:]
        var result: [ProcessIdentity: ProcessResourceDelta] = [:]

        for snapshot in snapshots {
            guard let current = snapshot.resourceCounters else { continue }
            next[snapshot.identity] = current
            guard let previous = previousByIdentity[snapshot.identity] else { continue }
            result[snapshot.identity] = ProcessResourceDelta(
                rusageVersion: current.rusageVersion,
                directEnergyNJ: delta(current.directEnergyNJ, previous.directEnergyNJ),
                billedEnergyNJ: delta(current.billedEnergyNJ, previous.billedEnergyNJ),
                servicedEnergyNJ: delta(current.servicedEnergyNJ, previous.servicedEnergyNJ),
                qosDefaultNS: delta(current.qosDefaultNS, previous.qosDefaultNS),
                qosMaintenanceNS: delta(current.qosMaintenanceNS, previous.qosMaintenanceNS),
                qosBackgroundNS: delta(current.qosBackgroundNS, previous.qosBackgroundNS),
                qosUtilityNS: delta(current.qosUtilityNS, previous.qosUtilityNS),
                qosLegacyNS: delta(current.qosLegacyNS, previous.qosLegacyNS),
                qosUserInitiatedNS: delta(current.qosUserInitiatedNS, previous.qosUserInitiatedNS),
                qosUserInteractiveNS: delta(current.qosUserInteractiveNS, previous.qosUserInteractiveNS)
            )
        }
        previousByIdentity = next
        return result
    }

    private func delta(_ current: UInt64?, _ previous: UInt64?) -> UInt64? {
        guard let current, let previous, current >= previous else { return nil }
        return current - previous
    }
}

struct ProcessTreeResourceMetrics: Equatable {
    let processCount: Int
    let sampledProcessCount: Int
    let qosSampledProcessCount: Int
    let directEnergySampledProcessCount: Int
    let maximumRusageVersion: Int?
    let directEnergyNJ: UInt64?
    let billedEnergyNJ: UInt64?
    let servicedEnergyNJ: UInt64?
    let qosDefaultNS: UInt64?
    let qosMaintenanceNS: UInt64?
    let qosBackgroundNS: UInt64?
    let qosUtilityNS: UInt64?
    let qosLegacyNS: UInt64?
    let qosUserInitiatedNS: UInt64?
    let qosUserInteractiveNS: UInt64?

    static func aggregate(tree: [ProcessSnapshot],
                          deltas: [ProcessIdentity: ProcessResourceDelta]) -> Self {
        let values = tree.compactMap { deltas[$0.identity] }
        return Self(
            processCount: tree.count,
            sampledProcessCount: values.count,
            qosSampledProcessCount: values.filter { $0.qosTotalNS != nil }.count,
            directEnergySampledProcessCount: values.filter { $0.directEnergyNJ != nil }.count,
            maximumRusageVersion: values.map(\.rusageVersion).max(),
            directEnergyNJ: sum(values.map(\.directEnergyNJ)),
            billedEnergyNJ: sum(values.map(\.billedEnergyNJ)),
            servicedEnergyNJ: sum(values.map(\.servicedEnergyNJ)),
            qosDefaultNS: sum(values.map(\.qosDefaultNS)),
            qosMaintenanceNS: sum(values.map(\.qosMaintenanceNS)),
            qosBackgroundNS: sum(values.map(\.qosBackgroundNS)),
            qosUtilityNS: sum(values.map(\.qosUtilityNS)),
            qosLegacyNS: sum(values.map(\.qosLegacyNS)),
            qosUserInitiatedNS: sum(values.map(\.qosUserInitiatedNS)),
            qosUserInteractiveNS: sum(values.map(\.qosUserInteractiveNS))
        )
    }

    var qosTotalNS: UInt64? {
        Self.sum([qosDefaultNS, qosMaintenanceNS, qosBackgroundNS,
                  qosUtilityNS, qosLegacyNS, qosUserInitiatedNS,
                  qosUserInteractiveNS])
    }

    private static func sum(_ values: [UInt64?]) -> UInt64? {
        let available = values.compactMap { $0 }
        guard !available.isEmpty else { return nil }
        return available.reduce(0, &+)
    }
}

enum EffectiveQoSClass: String, Codable, CaseIterable {
    case `default`
    case maintenance
    case background
    case utility
    case legacy
    case userInitiated = "user_initiated"
    case userInteractive = "user_interactive"
}

enum QoSEvidenceState: String, Codable {
    case confirmed
    case inferred
    case notObserved = "not_observed"
    case unavailable
    case failed
}

struct QoSEvidence: Equatable {
    let state: QoSEvidenceState
    let requestedClass: EffectiveQoSClass?
    let dominantClass: EffectiveQoSClass?
    let observedRequestedCPUTimeNS: UInt64?

    static func evaluate(requestedClass: EffectiveQoSClass?,
                         requestAccepted: Bool,
                         requestFailed: Bool,
                         metrics: ProcessTreeResourceMetrics?) -> Self {
        guard !requestFailed else {
            return Self(state: .failed, requestedClass: requestedClass,
                        dominantClass: dominantClass(in: metrics),
                        observedRequestedCPUTimeNS: nil)
        }
        guard let requestedClass, let metrics,
              metrics.qosSampledProcessCount > 0 else {
            return Self(state: .unavailable, requestedClass: requestedClass,
                        dominantClass: dominantClass(in: metrics),
                        observedRequestedCPUTimeNS: nil)
        }
        let observed = value(for: requestedClass, in: metrics)
        if let observed, observed > 0 {
            return Self(state: .confirmed, requestedClass: requestedClass,
                        dominantClass: dominantClass(in: metrics),
                        observedRequestedCPUTimeNS: observed)
        }
        if (metrics.qosTotalNS ?? 0) > 0 {
            return Self(state: .notObserved, requestedClass: requestedClass,
                        dominantClass: dominantClass(in: metrics),
                        observedRequestedCPUTimeNS: observed)
        }
        return Self(state: requestAccepted ? .inferred : .notObserved,
                    requestedClass: requestedClass,
                    dominantClass: dominantClass(in: metrics),
                    observedRequestedCPUTimeNS: observed)
    }

    private static func dominantClass(in metrics: ProcessTreeResourceMetrics?) -> EffectiveQoSClass? {
        guard let metrics else { return nil }
        let pairs: [(EffectiveQoSClass, UInt64?)] = [
            (.default, metrics.qosDefaultNS),
            (.maintenance, metrics.qosMaintenanceNS),
            (.background, metrics.qosBackgroundNS),
            (.utility, metrics.qosUtilityNS),
            (.legacy, metrics.qosLegacyNS),
            (.userInitiated, metrics.qosUserInitiatedNS),
            (.userInteractive, metrics.qosUserInteractiveNS)
        ]
        let observedPairs: [(EffectiveQoSClass, UInt64)] = pairs.compactMap {
            pair -> (EffectiveQoSClass, UInt64)? in
            guard let value = pair.1, value > 0 else { return nil }
            return (pair.0, value)
        }
        return observedPairs.max(by: {
            lhs, rhs in lhs.1 < rhs.1
        })?.0
    }

    private static func value(for qos: EffectiveQoSClass,
                              in metrics: ProcessTreeResourceMetrics) -> UInt64? {
        switch qos {
        case .default: return metrics.qosDefaultNS
        case .maintenance: return metrics.qosMaintenanceNS
        case .background: return metrics.qosBackgroundNS
        case .utility: return metrics.qosUtilityNS
        case .legacy: return metrics.qosLegacyNS
        case .userInitiated: return metrics.qosUserInitiatedNS
        case .userInteractive: return metrics.qosUserInteractiveNS
        }
    }
}
