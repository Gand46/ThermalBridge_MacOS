import Foundation

enum B1ThermalSensorQuality: String, Codable, Equatable {
    case fresh
    case hold
    case stale
    case lost
}

struct ThermalSignalSnapshot: Equatable {
    let date: Date
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let thermalState: ThermalLabel
    let sampleAgeSeconds: TimeInterval?
    let source: String
    let quality: B1ThermalSensorQuality
    let cpuSensorCount: Int
    let gpuSensorCount: Int
    let cpuMaximumSensor: String?
    let gpuMaximumSensor: String?
    let lastError: String?

    var hasNumericTemperature: Bool { cpuTemperature != nil || gpuTemperature != nil }
    var sensorFreshForControl: Bool { quality == .fresh }
}

struct B1PredictiveThermalConfiguration: Codable, Equatable {
    var normalPeriodSeconds = 1.0
    var alpha = 0.25
    var slopeWindowSeconds = 8.0
    var predictionHorizonSeconds = 8.0
    var maximumPlausibleSlopeCelsiusPerSecond = 4.0
    var outlierLimitCelsiusPerSecond = 6.0
    var proportionalGain = 0.075
    var integralGain = 0.010
    var integralMaximum = 40.0
    var integralDecayPerSecond = 3.0
    var normalRestrictionRisePerSecond = 0.08
    var fastRestrictionRisePerSecond = 0.20
    var restrictionReleasePerSecond = 0.02
    var criticalSlopeCelsiusPerSecond = 0.65
    var minimumStateDwellSeconds = 8.0
    var releaseMarginCelsius = 2.0
    var releaseStableSeconds = 10.0
    var emergencyRecoverySeconds = 30.0

    static let b1Default = B1PredictiveThermalConfiguration()
}

enum B1GovernorState: String, Codable, CaseIterable, Comparable {
    case observation = "observacion"
    case gentle = "suave"
    case balanced = "equilibrado"
    case strong = "fuerte"
    case emergency = "emergencia"

    var thermalRank: Int {
        switch self {
        case .observation: return 0
        case .gentle: return 1
        case .balanced: return 2
        case .strong: return 3
        case .emergency: return 4
        }
    }

    static func < (lhs: B1GovernorState, rhs: B1GovernorState) -> Bool { lhs.thermalRank < rhs.thermalRank }

    static func from(controlLevel: Double) -> B1GovernorState {
        switch controlLevel {
        case ..<0.15: return .observation
        case ..<0.40: return .gentle
        case ..<0.70: return .balanced
        case ..<0.90: return .strong
        default: return .emergency
        }
    }

    var minimumControlLevel: Double {
        switch self {
        case .observation: return 0
        case .gentle: return 0.15
        case .balanced: return 0.40
        case .strong: return 0.70
        case .emergency: return 0.90
        }
    }
}

struct B1GovernorDecision: Equatable {
    let requestedControlLevel: Double
    let appliedControlLevel: Double
    let state: B1GovernorState
    let emergency: Bool
    let reason: String
    let cpuFiltered: Double?
    let gpuFiltered: Double?
    let cpuPredicted: Double?
    let gpuPredicted: Double?
    let cpuSlope: Double?
    let gpuSlope: Double?
    let sensorQuality: B1ThermalSensorQuality
    let sampleAgeSeconds: TimeInterval?
    let actuator: String
    let actuatorResult: String
    let transitionReason: String?

    var activityPercentShadow: Int {
        Int((100.0 - 65.0 * appliedControlLevel).rounded())
    }
}

final class B1PredictiveThermalGovernor {
    private struct Sample { let date: Date; let value: Double }

    let configuration: B1PredictiveThermalConfiguration
    private var cpuFiltered: Double?
    private var gpuFiltered: Double?
    private var cpuSamples: [Sample] = []
    private var gpuSamples: [Sample] = []
    private var integral = 0.0
    private var appliedControlLevel = 0.0
    private var previousDate: Date?
    private var state: B1GovernorState = .observation
    private var stateEnteredAt: Date?
    private var recoveryStartedAt: Date?
    private var emergencyRecoveryStartedAt: Date?
    private var lastThermalState: ThermalLabel = .nominal

    init(configuration: B1PredictiveThermalConfiguration = .b1Default) {
        self.configuration = configuration
    }

    func reset() {
        cpuFiltered = nil; gpuFiltered = nil
        cpuSamples.removeAll(); gpuSamples.removeAll()
        integral = 0; appliedControlLevel = 0
        previousDate = nil; state = .observation; stateEnteredAt = nil
        recoveryStartedAt = nil; emergencyRecoveryStartedAt = nil
        lastThermalState = .nominal
    }

    func update(signal: ThermalSignalSnapshot,
                targetCPU: Int,
                targetGPU: Int,
                force: Bool = false) -> B1GovernorDecision {
        let dt = max(0.25, min(signal.date.timeIntervalSince(previousDate ?? signal.date), 5.0))
        previousDate = signal.date
        cpuFiltered = updateFilter(previous: cpuFiltered, samples: &cpuSamples, value: signal.cpuTemperature, date: signal.date, dt: dt)
        gpuFiltered = updateFilter(previous: gpuFiltered, samples: &gpuSamples, value: signal.gpuTemperature, date: signal.date, dt: dt)
        let cpuSlope = robustSlope(samples: cpuSamples)
        let gpuSlope = robustSlope(samples: gpuSamples)
        let cpuPredicted = cpuFiltered.map { $0 + configuration.predictionHorizonSeconds * max(cpuSlope ?? 0, 0) }
        let gpuPredicted = gpuFiltered.map { $0 + configuration.predictionHorizonSeconds * max(gpuSlope ?? 0, 0) }
        let cpuError = cpuPredicted.map { $0 - Double(targetCPU) }
        let gpuError = gpuPredicted.map { $0 - Double(targetGPU) }
        let predictiveError = [cpuError, gpuError].compactMap { $0 }.max() ?? 0

        if predictiveError > 0 {
            integral = clamp(integral + predictiveError * dt, 0, configuration.integralMaximum)
        } else {
            integral = max(0, integral - configuration.integralDecayPerSecond * dt)
        }
        var requested = clamp(configuration.proportionalGain * max(predictiveError, 0) + configuration.integralGain * integral, 0, 1)
        let safety = safetyFloor(signal: signal)
        requested = max(requested, safety.level)

        let realCPUExcess = signal.cpuTemperature.map { $0 - Double(targetCPU) } ?? -Double.infinity
        let realGPUExcess = signal.gpuTemperature.map { $0 - Double(targetGPU) } ?? -Double.infinity
        let thermalStateIncreased = signal.thermalState.thermalRank > lastThermalState.thermalRank
        let criticalSlope = max(cpuSlope ?? 0, gpuSlope ?? 0) >= configuration.criticalSlopeCelsiusPerSecond
        lastThermalState = signal.thermalState

        let emergencyOverride = signal.thermalState == .critical || safety.state == .emergency
        let maxRise = (realCPUExcess > 3 || realGPUExcess > 3 || criticalSlope || thermalStateIncreased)
            ? configuration.fastRestrictionRisePerSecond : configuration.normalRestrictionRisePerSecond
        if emergencyOverride {
            appliedControlLevel = max(appliedControlLevel, 0.90, requested)
        } else if requested > appliedControlLevel {
            appliedControlLevel = min(requested, appliedControlLevel + maxRise * dt)
        } else {
            appliedControlLevel = max(requested, appliedControlLevel - configuration.restrictionReleasePerSecond * dt)
        }
        appliedControlLevel = clamp(appliedControlLevel, safety.level, 1)

        let naturalState = max(B1GovernorState.from(controlLevel: appliedControlLevel), safety.state)
        let nextState = applyStateRules(candidate: naturalState,
                                       signal: signal,
                                       cpuSlope: cpuSlope,
                                       gpuSlope: gpuSlope,
                                       targetCPU: targetCPU,
                                       targetGPU: targetGPU)
        state = nextState
        appliedControlLevel = max(appliedControlLevel, nextState.minimumControlLevel)
        let reason = buildReason(error: predictiveError, safety: safety.reason, state: nextState)
        return B1GovernorDecision(requestedControlLevel: requested,
                                  appliedControlLevel: appliedControlLevel,
                                  state: nextState,
                                  emergency: nextState == .emergency,
                                  reason: reason,
                                  cpuFiltered: cpuFiltered,
                                  gpuFiltered: gpuFiltered,
                                  cpuPredicted: cpuPredicted,
                                  gpuPredicted: gpuPredicted,
                                  cpuSlope: cpuSlope,
                                  gpuSlope: gpuSlope,
                                  sensorQuality: signal.quality,
                                  sampleAgeSeconds: signal.sampleAgeSeconds,
                                  actuator: nextState == .emergency ? "generic_emergency_limiter" : "shadow_governor",
                                  actuatorResult: nextState == .emergency ? "emergency_only" : "observed_only_no_sigstop",
                                  transitionReason: safety.reason)
    }

    private func updateFilter(previous: Double?, samples: inout [Sample], value: Double?, date: Date, dt: TimeInterval) -> Double? {
        guard var value, value.isFinite else { return previous }
        if let previous {
            let limit = configuration.outlierLimitCelsiusPerSecond * max(dt, configuration.normalPeriodSeconds)
            value = clamp(value, previous - limit, previous + limit)
        }
        let filtered = previous.map { $0 + configuration.alpha * (value - $0) } ?? value
        samples.append(Sample(date: date, value: filtered))
        samples.removeAll { date.timeIntervalSince($0.date) > configuration.slopeWindowSeconds }
        return filtered
    }

    private func robustSlope(samples: [Sample]) -> Double? {
        guard let first = samples.first, let last = samples.last, last.date > first.date else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed >= 0.5 else { return nil }
        return clamp((last.value - first.value) / elapsed,
                     -configuration.maximumPlausibleSlopeCelsiusPerSecond,
                     configuration.maximumPlausibleSlopeCelsiusPerSecond)
    }

    private func safetyFloor(signal: ThermalSignalSnapshot) -> (level: Double, state: B1GovernorState, reason: String?) {
        if signal.thermalState == .critical || (!signal.hasNumericTemperature && signal.quality == .lost) {
            return (0.90, .emergency, "critical o pérdida de ambas señales")
        }
        if signal.thermalState == .serious {
            return (0.70, .strong, "thermalState serious exige fuerte")
        }
        if signal.thermalState == .fair {
            return (0.15, .gentle, "thermalState fair exige suave y prohíbe burst")
        }
        guard let age = signal.sampleAgeSeconds else { return (0.40, .balanced, "sin edad de sensor") }
        if age > 10 { return (0.70, .strong, "sensor obsoleto >10 s") }
        if age > 5 { return (0.40, .balanced, "sensor obsoleto >5 s") }
        if age > 2 { return (appliedControlLevel, state, "sensor 2–5 s: mantener restricción") }
        return (0, .observation, nil)
    }

    private func applyStateRules(candidate: B1GovernorState,
                                 signal: ThermalSignalSnapshot,
                                 cpuSlope: Double?,
                                 gpuSlope: Double?,
                                 targetCPU: Int,
                                 targetGPU: Int) -> B1GovernorState {
        let now = signal.date
        if stateEnteredAt == nil { stateEnteredAt = now }
        if candidate > state {
            stateEnteredAt = now
            if candidate == .emergency { emergencyRecoveryStartedAt = nil }
            return candidate
        }
        if state == .emergency {
            let recovered = signal.sensorFreshForControl && signal.thermalState.thermalRank <= ThermalLabel.fair.thermalRank && belowRelease(signal: signal, cpuSlope: cpuSlope, gpuSlope: gpuSlope, targetCPU: targetCPU, targetGPU: targetGPU)
            if recovered {
                if emergencyRecoveryStartedAt == nil { emergencyRecoveryStartedAt = now }
                if now.timeIntervalSince(emergencyRecoveryStartedAt ?? now) >= configuration.emergencyRecoverySeconds {
                    stateEnteredAt = now; emergencyRecoveryStartedAt = nil; return max(candidate, .strong)
                }
            } else { emergencyRecoveryStartedAt = nil }
            return .emergency
        }
        let dwellMet = now.timeIntervalSince(stateEnteredAt ?? now) >= configuration.minimumStateDwellSeconds
        let releaseMet = belowRelease(signal: signal, cpuSlope: cpuSlope, gpuSlope: gpuSlope, targetCPU: targetCPU, targetGPU: targetGPU)
        if releaseMet {
            if recoveryStartedAt == nil { recoveryStartedAt = now }
        } else { recoveryStartedAt = nil }
        let recoveryMet = recoveryStartedAt.map { now.timeIntervalSince($0) >= configuration.releaseStableSeconds } ?? false
        if candidate < state && !(dwellMet && recoveryMet) { return state }
        if candidate != state { stateEnteredAt = now }
        return candidate
    }

    private func belowRelease(signal: ThermalSignalSnapshot, cpuSlope: Double?, gpuSlope: Double?, targetCPU: Int, targetGPU: Int) -> Bool {
        let cpuOK = signal.cpuTemperature.map { $0 <= Double(targetCPU) - configuration.releaseMarginCelsius } ?? true
        let gpuOK = signal.gpuTemperature.map { $0 <= Double(targetGPU) - configuration.releaseMarginCelsius } ?? true
        return cpuOK && gpuOK && (cpuSlope ?? 0) <= 0 && (gpuSlope ?? 0) <= 0
    }

    private func buildReason(error: Double, safety: String?, state: B1GovernorState) -> String {
        var parts = ["B1 \(state.rawValue): error predictivo \(String(format: "%.1f", max(error, 0))) °C"]
        if let safety { parts.append(safety) }
        return parts.joined(separator: "; ")
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double { min(max(value, lower), upper) }
}

private extension ThermalLabel {
    var thermalRank: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        case .unknown: return 0
        }
    }
}
