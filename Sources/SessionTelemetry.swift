import Foundation

/// Evento JSONL de observación. No contiene rutas, argumentos de procesos,
/// nombres de usuario ni contenido visual.
struct SessionTelemetryEvent: Codable, Equatable {
    static let currentSchemaVersion = 2

    enum Kind: String, Codable, Equatable {
        case sessionStarted = "session_started"
        case configurationChanged = "configuration_changed"
        case decision
        case safetyEvent = "safety_event"
        case sessionStopped = "session_stopped"
    }

    struct Configuration: Codable, Equatable {
        let cpuTargetCelsius: Int
        let gpuTargetCelsius: Int
        let hysteresisCelsius: Int
        let minimumActivityPercent: Int
        let maximumActivityPercent: Int
        let aggressiveness: String
        let powerAnticipationEnabled: Bool
        let audioProtectionEnabled: Bool
        let requestedQoSClamp: String?
    }

    let schemaVersion: Int
    let sessionID: UUID
    let kind: Kind
    let wallTime: Date
    let monotonicNanoseconds: UInt64
    let configuration: Configuration?
    let cpuTemperatureCelsius: Double?
    let gpuTemperatureCelsius: Double?
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let sensorFresh: Bool?
    let sensorSource: String?
    let thermalState: String?
    let requestedActivityPercent: Int?
    let appliedActivityPercent: Int?
    let pulseMode: String?
    let emergency: Bool?
    let reason: String?
    let treeProcessCount: Int?
    let sampledProcessCount: Int?
    let rusageVersion: Int?
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
    let qosEvidenceState: String?
    let requestedQoSClass: String?
    let dominantQoSClass: String?
    let observedRequestedQoSCPUTimeNS: UInt64?
    let safetyOperation: String?
    let safetyStatus: String?
    let cpuFilteredCelsius: Double?
    let gpuFilteredCelsius: Double?
    let cpuPredictedCelsius: Double?
    let gpuPredictedCelsius: Double?
    let cpuSlopeCelsiusPerSecond: Double?
    let gpuSlopeCelsiusPerSecond: Double?
    let sensorAgeSeconds: Double?
    let sensorQuality: String?
    let controlLevelRequested: Double?
    let controlLevelApplied: Double?
    let governorState: String?
    let actuator: String?
    let actuatorResult: String?
    let transitionReason: String?
    let ephemeralProcessStartID: UInt64?
    let frameTimeP50MS: Double?
    let frameTimeP95MS: Double?
    let frameTimeP99MS: Double?
    let onePercentLowFPS: Double?
    let frameTimeOver50MSPerMinute: Double?
    let frameTimeOver100MSPerMinute: Double?
    let suspensionCount: Int?
    let suspensionDurationSeconds: Double?

    init(sessionID: UUID,
         kind: Kind,
         wallTime: Date = Date(),
         monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
         configuration: Configuration? = nil,
         cpuTemperatureCelsius: Double? = nil,
         gpuTemperatureCelsius: Double? = nil,
         cpuPowerWatts: Double? = nil,
         gpuPowerWatts: Double? = nil,
         sensorFresh: Bool? = nil,
         sensorSource: String? = nil,
         thermalState: String? = nil,
         requestedActivityPercent: Int? = nil,
         appliedActivityPercent: Int? = nil,
         pulseMode: String? = nil,
         emergency: Bool? = nil,
         reason: String? = nil,
         treeProcessCount: Int? = nil,
         sampledProcessCount: Int? = nil,
         rusageVersion: Int? = nil,
         directEnergyNJ: UInt64? = nil,
         billedEnergyNJ: UInt64? = nil,
         servicedEnergyNJ: UInt64? = nil,
         qosDefaultNS: UInt64? = nil,
         qosMaintenanceNS: UInt64? = nil,
         qosBackgroundNS: UInt64? = nil,
         qosUtilityNS: UInt64? = nil,
         qosLegacyNS: UInt64? = nil,
         qosUserInitiatedNS: UInt64? = nil,
         qosUserInteractiveNS: UInt64? = nil,
         qosEvidenceState: String? = nil,
         requestedQoSClass: String? = nil,
         dominantQoSClass: String? = nil,
         observedRequestedQoSCPUTimeNS: UInt64? = nil,
         safetyOperation: String? = nil,
         safetyStatus: String? = nil,
         cpuFilteredCelsius: Double? = nil,
         gpuFilteredCelsius: Double? = nil,
         cpuPredictedCelsius: Double? = nil,
         gpuPredictedCelsius: Double? = nil,
         cpuSlopeCelsiusPerSecond: Double? = nil,
         gpuSlopeCelsiusPerSecond: Double? = nil,
         sensorAgeSeconds: Double? = nil,
         sensorQuality: String? = nil,
         controlLevelRequested: Double? = nil,
         controlLevelApplied: Double? = nil,
         governorState: String? = nil,
         actuator: String? = nil,
         actuatorResult: String? = nil,
         transitionReason: String? = nil,
         ephemeralProcessStartID: UInt64? = nil,
         frameTimeP50MS: Double? = nil,
         frameTimeP95MS: Double? = nil,
         frameTimeP99MS: Double? = nil,
         onePercentLowFPS: Double? = nil,
         frameTimeOver50MSPerMinute: Double? = nil,
         frameTimeOver100MSPerMinute: Double? = nil,
         suspensionCount: Int? = nil,
         suspensionDurationSeconds: Double? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionID = sessionID
        self.kind = kind
        self.wallTime = wallTime
        self.monotonicNanoseconds = monotonicNanoseconds
        self.configuration = configuration
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.cpuPowerWatts = cpuPowerWatts
        self.gpuPowerWatts = gpuPowerWatts
        self.sensorFresh = sensorFresh
        self.sensorSource = sensorSource
        self.thermalState = thermalState
        self.requestedActivityPercent = requestedActivityPercent
        self.appliedActivityPercent = appliedActivityPercent
        self.pulseMode = pulseMode
        self.emergency = emergency
        self.reason = reason
        self.treeProcessCount = treeProcessCount
        self.sampledProcessCount = sampledProcessCount
        self.rusageVersion = rusageVersion
        self.directEnergyNJ = directEnergyNJ
        self.billedEnergyNJ = billedEnergyNJ
        self.servicedEnergyNJ = servicedEnergyNJ
        self.qosDefaultNS = qosDefaultNS
        self.qosMaintenanceNS = qosMaintenanceNS
        self.qosBackgroundNS = qosBackgroundNS
        self.qosUtilityNS = qosUtilityNS
        self.qosLegacyNS = qosLegacyNS
        self.qosUserInitiatedNS = qosUserInitiatedNS
        self.qosUserInteractiveNS = qosUserInteractiveNS
        self.qosEvidenceState = qosEvidenceState
        self.requestedQoSClass = requestedQoSClass
        self.dominantQoSClass = dominantQoSClass
        self.observedRequestedQoSCPUTimeNS = observedRequestedQoSCPUTimeNS
        self.safetyOperation = safetyOperation
        self.safetyStatus = safetyStatus
        self.cpuFilteredCelsius = cpuFilteredCelsius
        self.gpuFilteredCelsius = gpuFilteredCelsius
        self.cpuPredictedCelsius = cpuPredictedCelsius
        self.gpuPredictedCelsius = gpuPredictedCelsius
        self.cpuSlopeCelsiusPerSecond = cpuSlopeCelsiusPerSecond
        self.gpuSlopeCelsiusPerSecond = gpuSlopeCelsiusPerSecond
        self.sensorAgeSeconds = sensorAgeSeconds
        self.sensorQuality = sensorQuality
        self.controlLevelRequested = controlLevelRequested
        self.controlLevelApplied = controlLevelApplied
        self.governorState = governorState
        self.actuator = actuator
        self.actuatorResult = actuatorResult
        self.transitionReason = transitionReason
        self.ephemeralProcessStartID = ephemeralProcessStartID
        self.frameTimeP50MS = frameTimeP50MS
        self.frameTimeP95MS = frameTimeP95MS
        self.frameTimeP99MS = frameTimeP99MS
        self.onePercentLowFPS = onePercentLowFPS
        self.frameTimeOver50MSPerMinute = frameTimeOver50MSPerMinute
        self.frameTimeOver100MSPerMinute = frameTimeOver100MSPerMinute
        self.suspensionCount = suspensionCount
        self.suspensionDurationSeconds = suspensionDurationSeconds
    }
}

/// Escribe una sesión por archivo y conserva únicamente las sesiones recientes.
/// La cola dedicada evita introducir I/O en la ruta de decisión térmica.
final class SessionTelemetryWriter {
    private let queue = DispatchQueue(label: "ThermalBridge.SessionTelemetry", qos: .utility)
    private let directoryURL: URL
    private let maximumRetainedSessions: Int
    private var fileHandle: FileHandle?
    private var sessionID: UUID?

    init(directoryURL: URL? = nil, maximumRetainedSessions: Int = 20) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("ThermalBridge", isDirectory: true)
                .appendingPathComponent("Telemetry", isDirectory: true)
        }
        self.maximumRetainedSessions = max(1, maximumRetainedSessions)
    }

    @discardableResult
    func start(configuration: SessionTelemetryEvent.Configuration) -> URL? {
        queue.sync {
            stopLocked(reason: "session_restarted")
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                pruneOldSessionsLocked()

                let identifier = UUID()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let name = "session-\(formatter.string(from: Date()))-\(identifier.uuidString).jsonl"
                let destination = directoryURL.appendingPathComponent(name)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    return nil
                }

                fileHandle = try FileHandle(forWritingTo: destination)
                sessionID = identifier
                appendLocked(SessionTelemetryEvent(
                    sessionID: identifier,
                    kind: .sessionStarted,
                    configuration: configuration
                ))
                return destination
            } catch {
                closeLocked()
                return nil
            }
        }
    }

    func recordConfiguration(_ configuration: SessionTelemetryEvent.Configuration) {
        queue.async { [weak self] in
            guard let self, let sessionID = self.sessionID else { return }
            self.appendLocked(SessionTelemetryEvent(
                sessionID: sessionID,
                kind: .configurationChanged,
                configuration: configuration
            ))
        }
    }

    func recordDecision(cpuTemperatureCelsius: Double?,
                        gpuTemperatureCelsius: Double?,
                        cpuPowerWatts: Double?,
                        gpuPowerWatts: Double?,
                        sensorFresh: Bool,
                        sensorSource: String,
                        thermalState: String,
                        requestedActivityPercent: Int,
                        appliedActivityPercent: Int,
                        pulseMode: String,
                        emergency: Bool,
                        reason: String,
                        resourceMetrics: ProcessTreeResourceMetrics? = nil,
                        qosEvidence: QoSEvidence? = nil,
                        b1Decision: B1GovernorDecision? = nil,
                        signal: ThermalSignalSnapshot? = nil,
                        ephemeralProcessStartID: UInt64? = nil) {
        queue.async { [weak self] in
            guard let self, let sessionID = self.sessionID else { return }
            self.appendLocked(SessionTelemetryEvent(
                sessionID: sessionID,
                kind: .decision,
                cpuTemperatureCelsius: cpuTemperatureCelsius,
                gpuTemperatureCelsius: gpuTemperatureCelsius,
                cpuPowerWatts: cpuPowerWatts,
                gpuPowerWatts: gpuPowerWatts,
                sensorFresh: sensorFresh,
                sensorSource: sensorSource,
                thermalState: thermalState,
                requestedActivityPercent: requestedActivityPercent,
                appliedActivityPercent: appliedActivityPercent,
                pulseMode: pulseMode,
                emergency: emergency,
                reason: reason,
                treeProcessCount: resourceMetrics?.processCount,
                sampledProcessCount: resourceMetrics?.sampledProcessCount,
                rusageVersion: resourceMetrics?.maximumRusageVersion,
                directEnergyNJ: resourceMetrics?.directEnergyNJ,
                billedEnergyNJ: resourceMetrics?.billedEnergyNJ,
                servicedEnergyNJ: resourceMetrics?.servicedEnergyNJ,
                qosDefaultNS: resourceMetrics?.qosDefaultNS,
                qosMaintenanceNS: resourceMetrics?.qosMaintenanceNS,
                qosBackgroundNS: resourceMetrics?.qosBackgroundNS,
                qosUtilityNS: resourceMetrics?.qosUtilityNS,
                qosLegacyNS: resourceMetrics?.qosLegacyNS,
                qosUserInitiatedNS: resourceMetrics?.qosUserInitiatedNS,
                qosUserInteractiveNS: resourceMetrics?.qosUserInteractiveNS,
                qosEvidenceState: qosEvidence?.state.rawValue,
                requestedQoSClass: qosEvidence?.requestedClass?.rawValue,
                dominantQoSClass: qosEvidence?.dominantClass?.rawValue,
                observedRequestedQoSCPUTimeNS: qosEvidence?.observedRequestedCPUTimeNS,
                cpuFilteredCelsius: b1Decision?.cpuFiltered,
                gpuFilteredCelsius: b1Decision?.gpuFiltered,
                cpuPredictedCelsius: b1Decision?.cpuPredicted,
                gpuPredictedCelsius: b1Decision?.gpuPredicted,
                cpuSlopeCelsiusPerSecond: b1Decision?.cpuSlope,
                gpuSlopeCelsiusPerSecond: b1Decision?.gpuSlope,
                sensorAgeSeconds: signal?.sampleAgeSeconds,
                sensorQuality: signal?.quality.rawValue,
                controlLevelRequested: b1Decision?.requestedControlLevel,
                controlLevelApplied: b1Decision?.appliedControlLevel,
                governorState: b1Decision?.state.rawValue,
                actuator: b1Decision?.actuator,
                actuatorResult: b1Decision?.actuatorResult,
                transitionReason: b1Decision?.transitionReason,
                ephemeralProcessStartID: ephemeralProcessStartID
            ))
        }
    }

    func recordSafetyEvent(operation: String, status: String, reason: String) {
        queue.async { [weak self] in
            guard let self, let sessionID = self.sessionID else { return }
            self.appendLocked(SessionTelemetryEvent(
                sessionID: sessionID,
                kind: .safetyEvent,
                reason: reason,
                safetyOperation: operation,
                safetyStatus: status
            ))
        }
    }

    func stop(reason: String) {
        queue.sync {
            stopLocked(reason: reason)
        }
    }

    private func stopLocked(reason: String) {
        if let sessionID {
            appendLocked(SessionTelemetryEvent(
                sessionID: sessionID,
                kind: .sessionStopped,
                reason: reason
            ))
        }
        closeLocked()
    }

    private func appendLocked(_ event: SessionTelemetryEvent) {
        guard let fileHandle else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            var data = try encoder.encode(event)
            data.append(0x0A)
            try fileHandle.write(contentsOf: data)
        } catch {
            closeLocked()
        }
    }

    private func closeLocked() {
        if let fileHandle {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
        fileHandle = nil
        sessionID = nil
    }

    private func pruneOldSessionsLocked() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let sessions = entries.filter {
            $0.lastPathComponent.hasPrefix("session-") && $0.pathExtension == "jsonl"
        }.sorted { lhs, rhs in
            let left = try? lhs.resourceValues(forKeys: keys).contentModificationDate
            let right = try? rhs.resourceValues(forKeys: keys).contentModificationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        }

        for old in sessions.dropFirst(maximumRetainedSessions - 1) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
