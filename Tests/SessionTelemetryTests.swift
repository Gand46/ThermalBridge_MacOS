import Foundation

@main
struct SessionTelemetryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThermalBridgeTelemetryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = SessionTelemetryWriter(directoryURL: directory, maximumRetainedSessions: 3)
        let configuration = SessionTelemetryEvent.Configuration(
            cpuTargetCelsius: 90,
            gpuTargetCelsius: 85,
            hysteresisCelsius: 3,
            minimumActivityPercent: 35,
            maximumActivityPercent: 100,
            aggressiveness: "balanced",
            powerAnticipationEnabled: true,
            audioProtectionEnabled: true,
            requestedQoSClamp: "maintenance"
        )
        guard let file = writer.start(configuration: configuration) else {
            preconditionFailure("No se creó la sesión JSONL")
        }
        let b1Signal = ThermalSignalSnapshot(date: Date(),
                                             cpuTemperature: 91.5,
                                             gpuTemperature: 82,
                                             thermalState: .nominal,
                                             sampleAgeSeconds: 0.5,
                                             source: "SMC",
                                             quality: .fresh,
                                             cpuSensorCount: 4,
                                             gpuSensorCount: 2,
                                             cpuMaximumSensor: "TC0P",
                                             gpuMaximumSensor: "Tg0P",
                                             lastError: nil)
        let b1Decision = B1GovernorDecision(requestedControlLevel: 0.25,
                                            appliedControlLevel: 0.20,
                                            state: .gentle,
                                            emergency: false,
                                            reason: "B1 suave",
                                            cpuFiltered: 90.5,
                                            gpuFiltered: 81.0,
                                            cpuPredicted: 92.0,
                                            gpuPredicted: 83.0,
                                            cpuSlope: 0.2,
                                            gpuSlope: 0.1,
                                            sensorQuality: .fresh,
                                            sampleAgeSeconds: 0.5,
                                            actuator: "shadow_governor",
                                            actuatorResult: "observed_only_no_sigstop",
                                            transitionReason: "test")
        writer.recordDecision(
            cpuTemperatureCelsius: 91.5,
            gpuTemperatureCelsius: 82,
            cpuPowerWatts: 12,
            gpuPowerWatts: 8,
            sensorFresh: true,
            sensorSource: "SMC",
            thermalState: "nominal",
            requestedActivityPercent: 95,
            appliedActivityPercent: 95,
            pulseMode: "audio_safe",
            emergency: false,
            reason: "CPU máxima supera el objetivo",
            resourceMetrics: ProcessTreeResourceMetrics(
                processCount: 2,
                sampledProcessCount: 2,
                qosSampledProcessCount: 2,
                directEnergySampledProcessCount: 2,
                maximumRusageVersion: 6,
                directEnergyNJ: 500,
                billedEnergyNJ: 30,
                servicedEnergyNJ: 10,
                qosDefaultNS: 0,
                qosMaintenanceNS: 200,
                qosBackgroundNS: 0,
                qosUtilityNS: 20,
                qosLegacyNS: 0,
                qosUserInitiatedNS: 0,
                qosUserInteractiveNS: 0
            ),
            qosEvidence: QoSEvidence(
                state: .confirmed,
                requestedClass: .maintenance,
                dominantClass: .maintenance,
                observedRequestedCPUTimeNS: 200
            ),
            b1Decision: b1Decision,
            signal: b1Signal,
            ephemeralProcessStartID: 123456
        )
        writer.recordSafetyEvent(operation: "policy_restore", status: "restored", reason: "test")
        writer.stop(reason: "test_completed")

        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n")
        precondition(lines.count == 4)
        precondition(!text.contains("/Users/"))
        precondition(!text.contains("commandLine"))
        precondition(!text.contains("\"path\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try lines.map { line in
            try decoder.decode(SessionTelemetryEvent.self, from: Data(line.utf8))
        }
        precondition(events.map(\.kind) == [.sessionStarted, .decision, .safetyEvent, .sessionStopped])
        precondition(events.allSatisfy { $0.schemaVersion == 2 })
        precondition(events[1].appliedActivityPercent == 95)
        precondition(events[1].sensorSource == "SMC")
        precondition(events[1].directEnergyNJ == 500)
        precondition(events[1].qosEvidenceState == "confirmed")
        precondition(events[1].controlLevelApplied == 0.20)
        precondition(events[1].governorState == "suave")
        precondition(events[1].ephemeralProcessStartID == 123456)
        let legacySchema2 = #"{"schemaVersion":2,"sessionID":"00000000-0000-0000-0000-000000000001","kind":"decision","wallTime":"2026-07-18T00:00:00Z","monotonicNanoseconds":1}"#
        let legacyEvent = try decoder.decode(SessionTelemetryEvent.self, from: Data(legacySchema2.utf8))
        precondition(legacyEvent.schemaVersion == 2)
        precondition(legacyEvent.controlLevelApplied == nil)
        precondition(events[2].safetyOperation == "policy_restore")

        print("SessionTelemetryTests: OK")
    }
}
