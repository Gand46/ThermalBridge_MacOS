import Foundation

enum ThermalControlAggressiveness: String, Codable, CaseIterable, Identifiable {
    case smooth
    case balanced
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return "Suave"
        case .balanced: return "Equilibrada"
        case .fast: return "Rápida"
        }
    }

    var explanation: String {
        switch self {
        case .smooth: return "Menos cambios y recuperación lenta; prioriza estabilidad de imagen."
        case .balanced: return "Respuesta progresiva con buen equilibrio entre temperatura y fluidez."
        case .fast: return "Reduce actividad con mayor rapidez cuando la temperatura sube."
        }
    }

    var controlInterval: TimeInterval {
        switch self {
        case .smooth: return 2.0
        case .balanced: return 1.0
        case .fast: return 0.75
        }
    }

    var baseDownStep: Int {
        switch self {
        case .smooth: return 3
        case .balanced: return 5
        case .fast: return 8
        }
    }

    var recoveryStep: Int {
        switch self {
        case .smooth: return 1
        case .balanced: return 2
        case .fast: return 3
        }
    }

    var recoverySamples: Int {
        switch self {
        case .smooth: return 12
        case .balanced: return 8
        case .fast: return 6
        }
    }
}



enum ActivityLimiterPulseMode: Int, Codable, CaseIterable, Identifiable, Comparable {
    case burst = 0
    case audioSafe = 1

    var id: Int { rawValue }

    static func < (lhs: ActivityLimiterPulseMode, rhs: ActivityLimiterPulseMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .burst: return "Freno por bloques"
        case .audioSafe: return "Audio protegido"
        }
    }

    var explanation: String {
        switch self {
        case .burst:
            return "Usa la ventana completa configurada. Reduce con fuerza, pero puede interrumpir audio, red y presentación de fotogramas."
        case .audioSafe:
            return "Distribuye la pausa en pulsos de hasta 2 ms y actúa solo sobre el host principal para evitar silencios largos y no detener ayudantes de audio o red."
        }
    }
}

/// Matemática compartida por las pruebas Swift y el helper C. El modo protegido
/// nunca deja al proceso detenido durante decenas de milisegundos: distribuye la
/// reducción en ventanas cortas. No elimina el riesgo inherente a SIGSTOP, pero
/// reduce de forma drástica la duración de cada interrupción.
struct AudioSafeLimiterTiming: Equatable {
    let runMicroseconds: Int
    let stopMicroseconds: Int

    static func make(activityPercent: Int) -> AudioSafeLimiterTiming? {
        let activity = min(max(activityPercent, 25), 100)
        guard activity < 100 else { return nil }
        let stop = 2_000
        let denominator = max(1, 100 - activity)
        let calculatedRun = (stop * activity) / denominator
        return AudioSafeLimiterTiming(
            runMicroseconds: min(max(calculatedRun, 250), 40_000),
            stopMicroseconds: stop
        )
    }
}

struct AutomaticThermalConfiguration: Codable, Equatable {
    var executableContains = ""
    var bottleName = ""
    var autoAttach = true

    // El control usa el máximo instantáneo entre todos los sensores térmicos
    // clasificados como CPU y GPU, no el promedio del conjunto.
    var cpuTargetCelsius = 90
    var gpuTargetCelsius = 85
    var hysteresisCelsius = 3
    var minimumActivityPercent = 35
    var maximumActivityPercent = 100
    var aggressiveness: ThermalControlAggressiveness = .balanced

    var optimizeLaunchers = true
    var launcherActivityPercent = 55
    var launcherBackground = true

    var hasTarget: Bool {
        normalizedExecutableNeedle.hasSuffix(".exe")
    }

    var normalizedExecutableNeedle: String {
        executableContains
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    func matchScore(for process: ProcessSnapshot) -> Int? {
        guard hasTarget else { return nil }
        let needle = normalizedExecutableNeedle
        let scoreEvidence = process.windowsExecutableEvidenceScore(named: needle)
        var score: Int
        if let scoreEvidence {
            score = scoreEvidence
        } else if process.displayName.lowercased() == needle {
            score = 900
        } else {
            return nil
        }

        let bottle = bottleName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bottle.isEmpty {
            if let detected = process.crossOverBottleName?.lowercased() {
                guard detected == bottle else { return nil }
                score += 500
            } else {
                let token = "/bottles/\(bottle)/"
                if process.path.lowercased().contains(token)
                    || process.commandLine.lowercased().contains(token) {
                    score += 250
                } else {
                    // Un .exe exacto es evidencia suficiente aunque CrossOver
                    // oculte WINEPREFIX en esta muestra. Una botella detectada
                    // y diferente continúa rechazándose arriba.
                    score += 25
                }
            }
        }
        return score
    }

    mutating func clamp() {
        cpuTargetCelsius = min(max(cpuTargetCelsius, 60), 105)
        gpuTargetCelsius = min(max(gpuTargetCelsius, 55), 105)
        hysteresisCelsius = min(max(hysteresisCelsius, 1), 8)
        minimumActivityPercent = min(max(minimumActivityPercent, 20), 80)
        maximumActivityPercent = min(max(maximumActivityPercent, minimumActivityPercent), 100)
        launcherActivityPercent = min(max(launcherActivityPercent, 20), 100)
    }
}

enum CrossOverExecutableResolver {
    static func strongMatches(target: String,
                              among processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
        processes.filter { process in
            guard let evidence = process.windowsExecutableEvidenceScore(named: target) else {
                return false
            }
            return evidence >= 1_100
        }
    }

    /// La recuperación de una botella guardada incorrectamente solo es segura
    /// cuando existe un único proceso o todos los procesos que publican botella
    /// coinciden en el mismo nombre. Dos hosts sin botella siguen siendo ambiguos.
    static func isUnambiguousRecoverySet(_ matches: [ProcessSnapshot]) -> Bool {
        guard !matches.isEmpty else { return false }
        if matches.count == 1 { return true }
        let bottles = Set(matches.compactMap { $0.crossOverBottleName?.lowercased() })
        return bottles.count == 1
    }
}

struct TemperatureReading: Equatable {
    let date: Date
    let cpuMaximumCelsius: Double?
    let gpuMaximumCelsius: Double?
    let cpuAverageCelsius: Double?
    let gpuAverageCelsius: Double?
    let cpuMaximumSensor: String?
    let gpuMaximumSensor: String?
    let cpuSensorCount: Int
    let gpuSensorCount: Int
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let cpuEffectiveUsage: Double?
    let gpuEffectiveUsage: Double?
    let source: String

    var hasTemperature: Bool {
        cpuMaximumCelsius != nil || gpuMaximumCelsius != nil
            || cpuAverageCelsius != nil || gpuAverageCelsius != nil
    }

    var cpuControlCelsius: Double? {
        cpuMaximumCelsius ?? cpuAverageCelsius
    }

    var gpuControlCelsius: Double? {
        gpuMaximumCelsius ?? gpuAverageCelsius
    }
}

struct ThermalControlInput {
    let date: Date
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let powerAnticipationEnabled: Bool
    let sensorFresh: Bool
    let systemThermalState: ThermalLabel

    init(date: Date,
         cpuTemperature: Double?,
         gpuTemperature: Double?,
         cpuPowerWatts: Double? = nil,
         gpuPowerWatts: Double? = nil,
         powerAnticipationEnabled: Bool = true,
         sensorFresh: Bool,
         systemThermalState: ThermalLabel) {
        self.date = date
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.cpuPowerWatts = cpuPowerWatts
        self.gpuPowerWatts = gpuPowerWatts
        self.powerAnticipationEnabled = powerAnticipationEnabled
        self.sensorFresh = sensorFresh
        self.systemThermalState = systemThermalState
    }
}

struct ThermalControlDecision: Equatable {
    let activityPercent: Int
    let reason: String
    let emergency: Bool
    let cpuSmoothed: Double?
    let gpuSmoothed: Double?
}

/// Controlador térmico determinista. No modifica frecuencias directamente: regula
/// el tiempo activo del árbol del juego, que reduce trabajo enviado a CPU y GPU.
final class ThermalControlEngine {
    private(set) var currentActivityPercent = 100
    private var smoothedCPU: Double?
    private var smoothedGPU: Double?
    private var previousCPU: Double?
    private var previousGPU: Double?
    private var smoothedCPUPower: Double?
    private var smoothedGPUPower: Double?
    private var previousCPUPower: Double?
    private var previousGPUPower: Double?
    private var positiveErrorIntegral = 0.0
    private var previousDate: Date?
    private var belowTargetSamples = 0
    private var lastDecisionDate = Date.distantPast

    func reset(activityPercent: Int = 100) {
        currentActivityPercent = min(max(activityPercent, 10), 100)
        smoothedCPU = nil
        smoothedGPU = nil
        previousCPU = nil
        previousGPU = nil
        smoothedCPUPower = nil
        smoothedGPUPower = nil
        previousCPUPower = nil
        previousGPUPower = nil
        positiveErrorIntegral = 0
        previousDate = nil
        belowTargetSamples = 0
        lastDecisionDate = .distantPast
    }

    func update(input: ThermalControlInput,
                configuration original: AutomaticThermalConfiguration,
                force: Bool = false) -> ThermalControlDecision {
        var configuration = original
        configuration.clamp()
        // Cada entrada ya representa el sensor individual más caliente de CPU/GPU.
        // El pico instantáneo nunca se promedia hacia abajo para decidir una reducción.
        // El suavizado se usa únicamente para tendencia y recuperación estable.
        let alpha = 0.38
        smoothedCPU = exponentialAverage(previous: smoothedCPU, newValue: input.cpuTemperature, alpha: alpha)
        smoothedGPU = exponentialAverage(previous: smoothedGPU, newValue: input.gpuTemperature, alpha: alpha)

        let powerAlpha = 0.35
        smoothedCPUPower = exponentialAverage(previous: smoothedCPUPower,
                                              newValue: plausiblePower(input.cpuPowerWatts),
                                              alpha: powerAlpha)
        smoothedGPUPower = exponentialAverage(previous: smoothedGPUPower,
                                              newValue: plausiblePower(input.gpuPowerWatts),
                                              alpha: powerAlpha)

        let elapsed = input.date.timeIntervalSince(previousDate ?? input.date)
        let cpuSlope = slope(current: smoothedCPU, previous: previousCPU, elapsed: elapsed)
        let gpuSlope = slope(current: smoothedGPU, previous: previousGPU, elapsed: elapsed)
        let cpuPowerSlope = slope(current: smoothedCPUPower, previous: previousCPUPower, elapsed: elapsed)
        let gpuPowerSlope = slope(current: smoothedGPUPower, previous: previousGPUPower, elapsed: elapsed)
        previousCPU = smoothedCPU
        previousGPU = smoothedGPU
        previousCPUPower = smoothedCPUPower
        previousGPUPower = smoothedGPUPower
        previousDate = input.date

        let controlCPU = peakPreservingValue(raw: input.cpuTemperature, smoothed: smoothedCPU)
        let controlGPU = peakPreservingValue(raw: input.gpuTemperature, smoothed: smoothedGPU)

        guard force || input.date.timeIntervalSince(lastDecisionDate) >= configuration.aggressiveness.controlInterval else {
            return ThermalControlDecision(activityPercent: currentActivityPercent,
                                          reason: "Esperando la siguiente ventana de control",
                                          emergency: false,
                                          cpuSmoothed: smoothedCPU,
                                          gpuSmoothed: smoothedGPU)
        }
        lastDecisionDate = input.date

        let cpuError = controlCPU.map { $0 - Double(configuration.cpuTargetCelsius) }
        let gpuError = controlGPU.map { $0 - Double(configuration.gpuTargetCelsius) }
        let maxError = [cpuError, gpuError].compactMap { $0 }.max()
        let maxSlope = [cpuSlope, gpuSlope].compactMap { $0 }.max() ?? 0
        let maxPowerSlope = [cpuPowerSlope, gpuPowerSlope].compactMap { $0 }.max() ?? 0
        let integrationInterval = max(0.5, min(elapsed > 0 ? elapsed : configuration.aggressiveness.controlInterval, 3.0))
        if let maxError, maxError > 0 {
            positiveErrorIntegral = min(36.0,
                                        positiveErrorIntegral + maxError * integrationInterval)
        } else {
            // Anti-windup: el acumulador desaparece con rapidez cuando vuelve
            // a existir margen térmico y nunca empuja por debajo del mínimo.
            positiveErrorIntegral = max(0,
                                        positiveErrorIntegral - 2.5 * integrationInterval)
        }
        let minimum = configuration.minimumActivityPercent
        let maximum = configuration.maximumActivityPercent
        var desired = min(max(currentActivityPercent, minimum), maximum)
        var emergency = false
        var reason = "Temperaturas dentro del objetivo"

        if input.systemThermalState == .critical {
            emergency = true
            desired = max(25, min(desired - 15, 40))
            belowTargetSamples = 0
            reason = "macOS reporta estado térmico crítico; se anula temporalmente la actividad mínima"
        } else if input.systemThermalState == .serious {
            emergency = true
            desired = max(30, min(desired - 10, 55))
            belowTargetSamples = 0
            reason = "macOS reporta estado térmico serio; se permite reducir bajo el mínimo configurado"
        } else if !input.sensorFresh || maxError == nil {
            belowTargetSamples = 0
            let failSafeCeiling = 70
            if input.systemThermalState == .fair {
                desired = max(minimum, desired - configuration.aggressiveness.baseDownStep)
                reason = "Sensor sin lectura reciente; macOS reporta presión térmica"
            } else if desired > failSafeCeiling {
                desired = max(minimum,
                              desired - max(3, configuration.aggressiveness.baseDownStep))
                reason = "Sensor sin lectura reciente; activando límite preventivo"
            } else {
                reason = "Sensor sin lectura reciente; se conserva el límite preventivo"
            }
        } else if let error = maxError, error > 0 {
            belowTargetSamples = 0
            let base = configuration.aggressiveness.baseDownStep
            let step: Int
            switch error {
            case 8...: step = max(base * 2, 12)
            case 4..<8: step = max(base + 3, 8)
            case 1.5..<4: step = max(base, 5)
            default: step = max(2, base / 2)
            }
            let integralBoost = min(4, Int(positiveErrorIntegral / 8.0))
            desired = max(minimum, desired - step - integralBoost)
            let limiting = limitingSensor(cpuError: cpuError, gpuError: gpuError)
            reason = "\(limiting) máxima supera el objetivo por \(String(format: "%.1f", error)) °C"
            if integralBoost > 0 {
                reason += "; exceso sostenido"
            }
        } else {
            let hysteresis = Double(configuration.hysteresisCelsius)
            let cpuHasMargin = cpuError.map { $0 <= -hysteresis } ?? true
            let gpuHasMargin = gpuError.map { $0 <= -hysteresis } ?? true
            let nearTarget = [cpuError, gpuError].compactMap { $0 }.max().map { $0 > -hysteresis } ?? true

            let predictivePowerPressure = input.powerAnticipationEnabled
                && maxPowerSlope > 0.25
                && maxSlope > 0.08
                && nearTarget
            if predictivePowerPressure {
                belowTargetSamples = 0
                let predictiveStep = max(2, configuration.aggressiveness.baseDownStep / 2)
                desired = max(minimum, desired - predictiveStep)
                let domain = (cpuPowerSlope ?? -Double.infinity) >= (gpuPowerSlope ?? -Double.infinity)
                    ? "CPU" : "GPU"
                reason = "Potencia \(domain) y tendencia térmica anticipan el límite"
            } else if maxSlope > 0.65 && nearTarget {
                belowTargetSamples = 0
                desired = max(minimum, desired - max(2, configuration.aggressiveness.baseDownStep / 2))
                reason = "Temperatura subiendo rápidamente cerca del objetivo"
            } else if cpuHasMargin && gpuHasMargin {
                belowTargetSamples += 1
                if belowTargetSamples >= configuration.aggressiveness.recoverySamples {
                    desired = min(maximum, desired + configuration.aggressiveness.recoveryStep)
                    belowTargetSamples = 0
                    reason = desired == maximum
                        ? "Temperaturas estables; rendimiento liberado"
                        : "Margen térmico estable; recuperación gradual"
                } else {
                    reason = "Margen térmico; verificando estabilidad antes de recuperar"
                }
            } else {
                belowTargetSamples = 0
                reason = "Dentro de la banda de histéresis"
            }
        }

        let effectiveMinimum = emergency ? min(minimum, 25) : minimum
        desired = min(max(desired, effectiveMinimum), maximum)
        if !emergency, desired == minimum, let maxError, maxError > 0 {
            reason += "; actividad mínima alcanzada"
        }
        currentActivityPercent = desired
        return ThermalControlDecision(activityPercent: desired,
                                      reason: reason,
                                      emergency: emergency,
                                      cpuSmoothed: smoothedCPU,
                                      gpuSmoothed: smoothedGPU)
    }

    private func peakPreservingValue(raw: Double?, smoothed: Double?) -> Double? {
        switch (raw, smoothed) {
        case let (raw?, smoothed?): return max(raw, smoothed)
        case let (raw?, nil): return raw
        case let (nil, smoothed?): return smoothed
        default: return nil
        }
    }

    private func plausiblePower(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 500 else { return nil }
        return value
    }

    private func exponentialAverage(previous: Double?, newValue: Double?, alpha: Double) -> Double? {
        guard let newValue, newValue.isFinite else { return previous }
        guard let previous else { return newValue }
        return previous + alpha * (newValue - previous)
    }

    private func slope(current: Double?, previous: Double?, elapsed: TimeInterval) -> Double? {
        guard let current, let previous, elapsed > 0.2 else { return nil }
        return (current - previous) / elapsed
    }

    private func limitingSensor(cpuError: Double?, gpuError: Double?) -> String {
        switch (cpuError, gpuError) {
        case let (cpu?, gpu?): return cpu >= gpu ? "CPU" : "GPU"
        case (.some, .none): return "CPU"
        case (.none, .some): return "GPU"
        default: return "Temperatura"
        }
    }
}
