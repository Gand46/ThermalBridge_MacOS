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
            )
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
        precondition(events[2].safetyOperation == "policy_restore")

        print("SessionTelemetryTests: OK")
    }
}
