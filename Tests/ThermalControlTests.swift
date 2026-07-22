import Foundation

@main
struct ThermalControlTests {
    static func main() {
        testReducesAboveCPU()
        testReducesAboveGPU()
        testEmergencyClamp()
        testEmergencyOverridesHighMinimum()
        testRecoveryIsSlow()
        testSensorLossDoesNotRelease()
        testSustainedHeatConverges()
        testInstantMaximumIsNeverAveragedDown()
        testPowerAnticipatesThermalLimit()
        testPowerAnticipationCanBeDisabled()
        testInvalidPowerIsIgnored()
        testIntegralDetectsSustainedSmallExcess()
        testBeta6GoldenRisingTrace()
        testBeta6GoldenSensorLossTrace()
        testBeta6GoldenRecoveryTrace()
        testBeta6GoldenPowerTrace()
        testBeta6GoldenCriticalTrace()
        testAudioSafeLimiterAvoidsLongPauses()
        testAudioSafeLimiterPreservesRequestedRatio()
        testExecutableTargetValidation()
        testExactExecutableWinsAmongMultipleCandidates()
        testExactExecutableAllowsTemporarilyHiddenBottle()
        testDetectedWrongBottleIsRejected()
        testUnambiguousStrongExecutableRecovery()
        testAmbiguousStrongExecutableRecoveryAcrossBottles()
        testB1RampsBeforeCrossingTarget()
        testB1CPUAndGPUDominance()
        testB1OutlierSlopeLimited()
        testB1StaleSensorFloors()
        testB1ThermalStateEscalation()
        testB1AntiWindupAndSlowRelease()
        print("ThermalControlTests: OK")
    }

    static func testReducesAboveCPU() {
        let engine = ThermalControlEngine()
        let config = AutomaticThermalConfiguration(cpuTargetCelsius: 82, gpuTargetCelsius: 78)
        let decision = engine.update(input: .init(date: Date(),
                                                  cpuTemperature: 90,
                                                  gpuTemperature: 70,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent < 100)
        precondition(decision.reason.contains("CPU"))
    }

    static func testReducesAboveGPU() {
        let engine = ThermalControlEngine()
        let config = AutomaticThermalConfiguration(cpuTargetCelsius: 82, gpuTargetCelsius: 78)
        let decision = engine.update(input: .init(date: Date(),
                                                  cpuTemperature: 70,
                                                  gpuTemperature: 88,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent <= 88)
        precondition(decision.reason.contains("GPU"))
    }

    static func testEmergencyClamp() {
        let engine = ThermalControlEngine()
        let config = AutomaticThermalConfiguration()
        let decision = engine.update(input: .init(date: Date(),
                                                  cpuTemperature: nil,
                                                  gpuTemperature: nil,
                                                  sensorFresh: false,
                                                  systemThermalState: .critical),
                                     configuration: config,
                                     force: true)
        precondition(decision.emergency)
        precondition(decision.activityPercent <= 40)
    }


    static func testEmergencyOverridesHighMinimum() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.minimumActivityPercent = 80
        let decision = engine.update(input: .init(date: Date(),
                                                  cpuTemperature: 100,
                                                  gpuTemperature: 95,
                                                  sensorFresh: true,
                                                  systemThermalState: .critical),
                                     configuration: config,
                                     force: true)
        precondition(decision.emergency)
        precondition(decision.activityPercent <= 40)
    }

    static func testRecoveryIsSlow() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.aggressiveness = .balanced
        _ = engine.update(input: .init(date: Date(),
                                       cpuTemperature: 95,
                                       gpuTemperature: 90,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let reduced = engine.currentActivityPercent
        for index in 1...4 {
            _ = engine.update(input: .init(date: Date().addingTimeInterval(Double(index)),
                                           cpuTemperature: 60,
                                           gpuTemperature: 55,
                                           sensorFresh: true,
                                           systemThermalState: .nominal),
                              configuration: config,
                              force: true)
        }
        precondition(engine.currentActivityPercent <= reduced)
    }

    static func testSensorLossDoesNotRelease() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.minimumActivityPercent = 30
        _ = engine.update(input: .init(date: Date(),
                                       cpuTemperature: 95,
                                       gpuTemperature: 90,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let reduced = engine.currentActivityPercent
        let decision = engine.update(input: .init(date: Date().addingTimeInterval(2),
                                                  cpuTemperature: nil,
                                                  gpuTemperature: nil,
                                                  sensorFresh: false,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent <= reduced)
    }
    static func testSustainedHeatConverges() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 82
        config.gpuTargetCelsius = 78
        config.minimumActivityPercent = 25
        config.aggressiveness = .balanced

        var cpu = 55.0
        var gpu = 50.0
        let start = Date()
        for second in 0..<180 {
            let activity = Double(engine.currentActivityPercent) / 100.0
            let cpuSteadyState = 38.0 + (58.0 * activity)
            let gpuSteadyState = 35.0 + (55.0 * activity)
            cpu += (cpuSteadyState - cpu) * 0.09
            gpu += (gpuSteadyState - gpu) * 0.10
            _ = engine.update(input: .init(date: start.addingTimeInterval(Double(second)),
                                           cpuTemperature: cpu,
                                           gpuTemperature: gpu,
                                           sensorFresh: true,
                                           systemThermalState: .nominal),
                              configuration: config,
                              force: true)
        }

        precondition(cpu <= 85.0, "El controlador no estabilizó CPU: \(cpu)")
        precondition(gpu <= 81.0, "El controlador no estabilizó GPU: \(gpu)")
        precondition(engine.currentActivityPercent >= config.minimumActivityPercent)
    }

    static func testInstantMaximumIsNeverAveragedDown() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        config.aggressiveness = .balanced

        // Precalienta el promedio suavizado con una lectura baja.
        _ = engine.update(input: .init(date: Date(),
                                       cpuTemperature: 70,
                                       gpuTemperature: 65,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let before = engine.currentActivityPercent

        // Un único sensor CPU llega a 101 °C. Aunque el suavizado aún sea bajo,
        // la decisión debe reaccionar al máximo instantáneo de esta muestra.
        let decision = engine.update(input: .init(date: Date().addingTimeInterval(1),
                                                  cpuTemperature: 101,
                                                  gpuTemperature: 70,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent < before)
        precondition(decision.reason.contains("CPU máxima"))
    }

    static func testPowerAnticipatesThermalLimit() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85

        let start = Date()
        _ = engine.update(input: .init(date: start,
                                       cpuTemperature: 88,
                                       gpuTemperature: 83,
                                       cpuPowerWatts: 2,
                                       gpuPowerWatts: 2,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let before = engine.currentActivityPercent
        let decision = engine.update(input: .init(date: start.addingTimeInterval(1),
                                                  cpuTemperature: 89,
                                                  gpuTemperature: 84,
                                                  cpuPowerWatts: 10,
                                                  gpuPowerWatts: 8,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent < before)
        precondition(decision.reason.contains("Potencia"))
    }

    static func testPowerAnticipationCanBeDisabled() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85

        let start = Date()
        _ = engine.update(input: .init(date: start,
                                       cpuTemperature: 88,
                                       gpuTemperature: 83,
                                       cpuPowerWatts: 2,
                                       gpuPowerWatts: 2,
                                       powerAnticipationEnabled: false,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let before = engine.currentActivityPercent
        let decision = engine.update(input: .init(date: start.addingTimeInterval(1),
                                                  cpuTemperature: 89,
                                                  gpuTemperature: 84,
                                                  cpuPowerWatts: 10,
                                                  gpuPowerWatts: 8,
                                                  powerAnticipationEnabled: false,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent == before)
        precondition(!decision.reason.contains("Potencia"))
    }

    static func testInvalidPowerIsIgnored() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85

        let start = Date()
        _ = engine.update(input: .init(date: start,
                                       cpuTemperature: 88.8,
                                       gpuTemperature: 83.8,
                                       cpuPowerWatts: 2,
                                       gpuPowerWatts: 2,
                                       sensorFresh: true,
                                       systemThermalState: .nominal),
                          configuration: config,
                          force: true)
        let before = engine.currentActivityPercent
        let decision = engine.update(input: .init(date: start.addingTimeInterval(1),
                                                  cpuTemperature: 88.9,
                                                  gpuTemperature: 83.9,
                                                  cpuPowerWatts: 600,
                                                  gpuPowerWatts: .infinity,
                                                  sensorFresh: true,
                                                  systemThermalState: .nominal),
                                     configuration: config,
                                     force: true)
        precondition(decision.activityPercent == before)
        precondition(!decision.reason.contains("Potencia"))
    }

    static func testIntegralDetectsSustainedSmallExcess() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        config.minimumActivityPercent = 20
        config.aggressiveness = .balanced

        let start = Date()
        var last = engine.update(input: .init(date: start,
                                              cpuTemperature: 90.6,
                                              gpuTemperature: 80,
                                              sensorFresh: true,
                                              systemThermalState: .nominal),
                                 configuration: config,
                                 force: true)
        for second in 1...20 {
            last = engine.update(input: .init(date: start.addingTimeInterval(Double(second)),
                                              cpuTemperature: 90.6,
                                              gpuTemperature: 80,
                                              sensorFresh: true,
                                              systemThermalState: .nominal),
                                 configuration: config,
                                 force: true)
        }
        precondition(last.reason.contains("exceso sostenido"))
        precondition(last.activityPercent >= config.minimumActivityPercent)
    }

    /// Contrato de no regresión de Beta 6. Estas trazas fijan la secuencia de
    /// actividad, no solo el resultado final, para detectar entradas tardías o
    /// caídas concentradas como las introducidas por el experimento QoS-first.
    static func testBeta6GoldenRisingTrace() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        config.aggressiveness = .balanced
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cpuSequence = [88.0, 89.0, 91.0, 92.0, 94.0, 98.0, 99.0]
        let actual = cpuSequence.enumerated().map { index, cpu in
            engine.update(input: .init(
                date: start.addingTimeInterval(Double(index)),
                cpuTemperature: cpu,
                gpuTemperature: 80,
                sensorFresh: true,
                systemThermalState: .nominal
            ), configuration: config, force: true).activityPercent
        }
        precondition(actual == [100, 100, 98, 93, 85, 72, 57],
                     "Traza ascendente Beta 6 alterada: \(actual)")
    }

    static func testBeta6GoldenSensorLossTrace() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        config.aggressiveness = .balanced
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        var actual = [engine.update(input: .init(
            date: start,
            cpuTemperature: 98,
            gpuTemperature: 80,
            sensorFresh: true,
            systemThermalState: .nominal
        ), configuration: config, force: true).activityPercent]
        for second in 1...5 {
            actual.append(engine.update(input: .init(
                date: start.addingTimeInterval(Double(second)),
                cpuTemperature: nil,
                gpuTemperature: nil,
                sensorFresh: false,
                systemThermalState: .nominal
            ), configuration: config, force: true).activityPercent)
        }
        precondition(actual == [87, 82, 77, 72, 67, 67],
                     "Traza fail-safe Beta 6 alterada: \(actual)")
    }

    static func testBeta6GoldenRecoveryTrace() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        config.aggressiveness = .balanced
        let start = Date(timeIntervalSince1970: 1_700_000_200)
        var actual = [engine.update(input: .init(
            date: start,
            cpuTemperature: 98,
            gpuTemperature: 80,
            sensorFresh: true,
            systemThermalState: .nominal
        ), configuration: config, force: true).activityPercent]
        for second in 1...16 {
            actual.append(engine.update(input: .init(
                date: start.addingTimeInterval(Double(second)),
                cpuTemperature: 60,
                gpuTemperature: 55,
                sensorFresh: true,
                systemThermalState: .nominal
            ), configuration: config, force: true).activityPercent)
        }
        precondition(actual == [
            87, 87, 87, 87, 87, 87, 87, 87, 89,
            89, 89, 89, 89, 89, 89, 89, 91
        ], "Traza de recuperación Beta 6 alterada: \(actual)")
    }

    static func testBeta6GoldenPowerTrace() {
        let engine = ThermalControlEngine()
        var config = AutomaticThermalConfiguration()
        config.cpuTargetCelsius = 90
        config.gpuTargetCelsius = 85
        let start = Date(timeIntervalSince1970: 1_700_000_300)
        let first = engine.update(input: .init(
            date: start,
            cpuTemperature: 88,
            gpuTemperature: 83,
            cpuPowerWatts: 2,
            gpuPowerWatts: 2,
            sensorFresh: true,
            systemThermalState: .nominal
        ), configuration: config, force: true)
        let second = engine.update(input: .init(
            date: start.addingTimeInterval(1),
            cpuTemperature: 89,
            gpuTemperature: 84,
            cpuPowerWatts: 10,
            gpuPowerWatts: 8,
            sensorFresh: true,
            systemThermalState: .nominal
        ), configuration: config, force: true)
        precondition(first.activityPercent == 100 && second.activityPercent == 98)
        precondition(second.reason.contains("Potencia"))
    }

    static func testBeta6GoldenCriticalTrace() {
        let engine = ThermalControlEngine()
        let config = AutomaticThermalConfiguration()
        let start = Date(timeIntervalSince1970: 1_700_000_400)
        let first = engine.update(input: .init(
            date: start,
            cpuTemperature: nil,
            gpuTemperature: nil,
            sensorFresh: false,
            systemThermalState: .critical
        ), configuration: config, force: true)
        let second = engine.update(input: .init(
            date: start.addingTimeInterval(1),
            cpuTemperature: nil,
            gpuTemperature: nil,
            sensorFresh: false,
            systemThermalState: .critical
        ), configuration: config, force: true)
        precondition(first.activityPercent == 40 && second.activityPercent == 25)
        precondition(first.emergency && second.emergency)
    }


    static func testAudioSafeLimiterAvoidsLongPauses() {
        let timing = AudioSafeLimiterTiming.make(activityPercent: 35)
        precondition(timing != nil)
        precondition(timing!.stopMicroseconds <= 2_000)
        // El limitador anterior usaba ciclos de 40 ms: a 35 % detenía el
        // proceso 26 ms continuos, suficiente para vaciar buffers de audio.
        let previousBurstPauseMicroseconds = 40_000 * 65 / 100
        precondition(previousBurstPauseMicroseconds == 26_000)
        precondition(previousBurstPauseMicroseconds >= timing!.stopMicroseconds * 13)
    }

    static func testAudioSafeLimiterPreservesRequestedRatio() {
        for activity in [25, 35, 50, 65, 80, 95] {
            guard let timing = AudioSafeLimiterTiming.make(activityPercent: activity) else {
                preconditionFailure("Falta temporización para \(activity)%")
            }
            let total = Double(timing.runMicroseconds + timing.stopMicroseconds)
            let realized = Double(timing.runMicroseconds) / total * 100.0
            precondition(abs(realized - Double(activity)) < 0.35)
            precondition(timing.stopMicroseconds <= 2_000)
        }
        precondition(AudioSafeLimiterTiming.make(activityPercent: 100) == nil)
    }

    static func testExecutableTargetValidation() {
        var config = AutomaticThermalConfiguration()
        config.executableContains = "PRAGMATA"
        precondition(!config.hasTarget)
        config.executableContains = #"C:\Games\PRAGMATA.exe"#
        precondition(config.hasTarget)
        precondition(config.normalizedExecutableNeedle == "pragmata.exe")
    }

    static func matchingSnapshot(command: String, bottlePath: String = "") -> ProcessSnapshot {
        ProcessSnapshot(identity: ProcessIdentity(pid: 900, startID: 9_000),
                        parentPID: 100,
                        name: "wine64-preloader",
                        path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/" + bottlePath,
                        commandLine: command,
                        cpuPercent: 50,
                        memoryBytes: 1024,
                        niceValue: 0)
    }

    static func testExactExecutableWinsAmongMultipleCandidates() {
        var config = AutomaticThermalConfiguration()
        config.executableContains = "PRAGMATA.exe"
        let process = matchingSnapshot(command: #"wine64-preloader helper.exe "C:\Games\PRAGMATA.exe" updater.exe"#)
        precondition(config.matchScore(for: process) != nil)
    }

    static func testExactExecutableAllowsTemporarilyHiddenBottle() {
        var config = AutomaticThermalConfiguration()
        config.executableContains = "PRAGMATA.exe"
        config.bottleName = "Pragmata"
        let process = matchingSnapshot(command: #"wine64-preloader "C:\Games\PRAGMATA.exe""#)
        precondition(config.matchScore(for: process) != nil)
    }

    static func testDetectedWrongBottleIsRejected() {
        var config = AutomaticThermalConfiguration()
        config.executableContains = "PRAGMATA.exe"
        config.bottleName = "Pragmata"
        let process = matchingSnapshot(
            command: #"wine64-preloader "/Users/test/Library/Application Support/CrossOver/Bottles/Other/drive_c/PRAGMATA.exe""#
        )
        precondition(config.matchScore(for: process) == nil)
    }

    static func resolverSnapshot(pid: Int32,
                                 name: String,
                                 command: String) -> ProcessSnapshot {
        ProcessSnapshot(identity: ProcessIdentity(pid: pid, startID: UInt64(pid) * 100),
                        parentPID: 100,
                        name: name,
                        path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64-preloader",
                        commandLine: command,
                        cpuPercent: 50,
                        memoryBytes: 1024,
                        niceValue: 0)
    }

    static func testUnambiguousStrongExecutableRecovery() {
        let first = resolverSnapshot(
            pid: 501,
            name: "wine64-preloader",
            command: #"/Applications/CrossOver.app/wine64-preloader C:\Games\PRAGMATA.exe WINEPREFIX=/Users/test/Library/Application Support/CrossOver/Bottles/Pragmata"#
        )
        let second = resolverSnapshot(
            pid: 502,
            name: "PRAGMATA.exe",
            command: #"PRAGMATA.exe CX_BOTTLE=Pragmata"#
        )
        let matches = CrossOverExecutableResolver.strongMatches(
            target: "PRAGMATA.exe",
            among: [first, second]
        )
        precondition(matches.count == 2)
        precondition(CrossOverExecutableResolver.isUnambiguousRecoverySet(matches))
    }

    static func testAmbiguousStrongExecutableRecoveryAcrossBottles() {
        let first = resolverSnapshot(
            pid: 503,
            name: "PRAGMATA.exe",
            command: #"PRAGMATA.exe CX_BOTTLE=Pragmata"#
        )
        let second = resolverSnapshot(
            pid: 504,
            name: "PRAGMATA.exe",
            command: #"PRAGMATA.exe CX_BOTTLE=Pragmata-Test"#
        )
        let matches = CrossOverExecutableResolver.strongMatches(
            target: "PRAGMATA.exe",
            among: [first, second]
        )
        precondition(matches.count == 2)
        precondition(!CrossOverExecutableResolver.isUnambiguousRecoverySet(matches))
    }

    static func signal(_ seconds: TimeInterval,
                       cpu: Double?,
                       gpu: Double?,
                       state: ThermalLabel = .nominal,
                       age: TimeInterval? = 0) -> ThermalSignalSnapshot {
        ThermalSignalSnapshot(date: Date(timeIntervalSince1970: seconds),
                              cpuTemperature: cpu,
                              gpuTemperature: gpu,
                              thermalState: state,
                              sampleAgeSeconds: age,
                              source: "test",
                              quality: (age ?? 99) <= 2 ? .fresh : ((age ?? 99) <= 5 ? .hold : ((age ?? 99) <= 10 ? .stale : .lost)),
                              cpuSensorCount: cpu == nil ? 0 : 1,
                              gpuSensorCount: gpu == nil ? 0 : 1,
                              cpuMaximumSensor: "cpu-test",
                              gpuMaximumSensor: "gpu-test",
                              lastError: nil)
    }

    static func testB1RampsBeforeCrossingTarget() {
        let governor = B1PredictiveThermalGovernor()
        var decision: B1GovernorDecision?
        for i in 0...8 {
            decision = governor.update(signal: signal(Double(i), cpu: 80 + Double(i), gpu: 70), targetCPU: 90, targetGPU: 85)
        }
        precondition((decision?.cpuPredicted ?? 0) > 90)
        precondition((decision?.appliedControlLevel ?? 0) > 0)
        precondition(decision?.state != .emergency)
    }

    static func testB1CPUAndGPUDominance() {
        let cpuGovernor = B1PredictiveThermalGovernor()
        let gpuGovernor = B1PredictiveThermalGovernor()
        let cpuDecision = cpuGovernor.update(signal: signal(0, cpu: 96, gpu: 70), targetCPU: 90, targetGPU: 85, force: true)
        let gpuDecision = gpuGovernor.update(signal: signal(0, cpu: 70, gpu: 92), targetCPU: 90, targetGPU: 85, force: true)
        precondition(cpuDecision.requestedControlLevel > 0)
        precondition(gpuDecision.requestedControlLevel > 0)
    }

    static func testB1OutlierSlopeLimited() {
        let governor = B1PredictiveThermalGovernor()
        _ = governor.update(signal: signal(0, cpu: 70, gpu: nil), targetCPU: 90, targetGPU: 85, force: true)
        let decision = governor.update(signal: signal(1, cpu: 130, gpu: nil), targetCPU: 90, targetGPU: 85, force: true)
        precondition((decision.cpuSlope ?? 0) <= B1PredictiveThermalConfiguration.b1Default.maximumPlausibleSlopeCelsiusPerSecond)
        precondition((decision.cpuFiltered ?? 0) < 130)
    }

    static func testB1StaleSensorFloors() {
        let governor = B1PredictiveThermalGovernor()
        let hold = governor.update(signal: signal(3, cpu: 80, gpu: 70, age: 3), targetCPU: 90, targetGPU: 85, force: true)
        let stale = governor.update(signal: signal(6, cpu: 80, gpu: 70, age: 6), targetCPU: 90, targetGPU: 85, force: true)
        let lost = governor.update(signal: signal(11, cpu: 80, gpu: 70, age: 11), targetCPU: 90, targetGPU: 85, force: true)
        precondition(hold.appliedControlLevel >= 0)
        precondition(stale.state >= .balanced)
        precondition(lost.state >= .strong)
    }

    static func testB1ThermalStateEscalation() {
        let governor = B1PredictiveThermalGovernor()
        let fair = governor.update(signal: signal(0, cpu: 75, gpu: 70, state: .fair), targetCPU: 90, targetGPU: 85, force: true)
        let serious = governor.update(signal: signal(1, cpu: 75, gpu: 70, state: .serious), targetCPU: 90, targetGPU: 85, force: true)
        let critical = governor.update(signal: signal(2, cpu: 75, gpu: 70, state: .critical), targetCPU: 90, targetGPU: 85, force: true)
        precondition(fair.state >= .gentle)
        precondition(serious.state >= .strong)
        precondition(critical.state == .emergency)
    }

    static func testB1AntiWindupAndSlowRelease() {
        let governor = B1PredictiveThermalGovernor()
        var hot: B1GovernorDecision?
        for i in 0..<20 {
            hot = governor.update(signal: signal(Double(i), cpu: 100, gpu: 95), targetCPU: 90, targetGPU: 85)
        }
        let hotLevel = hot?.appliedControlLevel ?? 0
        let cool = governor.update(signal: signal(21, cpu: 80, gpu: 75), targetCPU: 90, targetGPU: 85)
        precondition(hotLevel > 0)
        precondition(cool.appliedControlLevel >= hotLevel - B1PredictiveThermalConfiguration.b1Default.restrictionReleasePerSecond * 2)
    }

}
