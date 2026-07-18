import Foundation

enum MacLaunchQoSClamp: Int, Codable, CaseIterable, Identifiable {
    case utility = 1
    case background = 2
    case maintenance = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .utility: return "Utilidad"
        case .background: return "Segundo plano"
        case .maintenance: return "Mantenimiento"
        }
    }

    var explanation: String {
        switch self {
        case .utility:
            return "Equilibra respuesta y eficiencia. Orienta al planificador, pero no fija el juego a E-cores."
        case .background:
            return "Más restrictiva; puede afectar audio, red o fluidez. Tampoco constituye afinidad de CPU."
        case .maintenance:
            return "Máximo ahorro orientativo; solo para pruebas. macOS conserva la decisión final de planificación."
        }
    }
}

enum MacApplicationPolicyLevel: Int, Codable, CaseIterable, Identifiable, Comparable {
    case normal = 0
    case efficiency = 1
    case constrained = 2
    case emergency = 3

    var id: Int { rawValue }

    static func < (lhs: MacApplicationPolicyLevel, rhs: MacApplicationPolicyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .efficiency: return "Eficiencia"
        case .constrained: return "Restringida"
        case .emergency: return "Emergencia"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "speedometer"
        case .efficiency: return "leaf"
        case .constrained: return "gauge.with.dots.needle.50percent"
        case .emergency: return "exclamationmark.shield"
        }
    }
}

struct MacApplicationPolicyPlan: Equatable {
    let level: MacApplicationPolicyLevel
    let throughputTier: Int
    let latencyTier: Int
    let reason: String

    static let normal = MacApplicationPolicyPlan(
        level: .normal,
        throughputTier: -1,
        latencyTier: -1,
        reason: "Políticas macOS sin restricción"
    )
}

/// Planifica únicamente políticas de proceso proporcionadas por macOS. No toca
/// Wine, D3DMetal, Metal, la botella ni la configuración interna del juego.
/// Los tiers 0...5 son los valores publicados por taskpolicy/XNU. El valor -1
/// se traduce al tier no especificado para retirar el override al finalizar.
struct MacApplicationPolicyPlanner {
    static func plan(cpuTemperature: Double?,
                     gpuTemperature: Double?,
                     cpuTarget: Int,
                     gpuTarget: Int,
                     hysteresis: Int,
                     sensorFresh: Bool,
                     thermalState: ThermalLabel,
                     currentLevel: MacApplicationPolicyLevel) -> MacApplicationPolicyPlan {
        if thermalState == .critical {
            return plan(for: .emergency,
                        reason: "macOS reporta presión térmica crítica")
        }
        if thermalState == .serious {
            return plan(for: .emergency,
                        reason: "macOS reporta presión térmica seria")
        }
        guard sensorFresh else {
            let level: MacApplicationPolicyLevel = thermalState == .fair ? .constrained : .efficiency
            return plan(for: level,
                        reason: "Lectura térmica no reciente; política preventiva")
        }

        let cpuError = cpuTemperature.map { $0 - Double(cpuTarget) }
        let gpuError = gpuTemperature.map { $0 - Double(gpuTarget) }
        guard let error = [cpuError, gpuError].compactMap({ $0 }).max() else {
            return plan(for: .efficiency,
                        reason: "Sin temperatura válida; política preventiva")
        }

        // Recuperación con histéresis: bajar un nivel requiere más margen que
        // subirlo. Esto evita ejecutar taskpolicy en cada oscilación de décimas.
        let recoveryBoundary = -Double(max(1, hysteresis))
        let requested: MacApplicationPolicyLevel
        if error >= 7 {
            requested = .emergency
        } else if error >= 3 {
            requested = .constrained
        } else if error >= -1 || thermalState == .fair {
            requested = .efficiency
        } else {
            requested = .normal
        }

        let effective: MacApplicationPolicyLevel
        if requested < currentLevel && error > recoveryBoundary {
            effective = MacApplicationPolicyLevel(rawValue: max(0, currentLevel.rawValue - 1)) ?? .normal
        } else {
            effective = requested
        }

        let dominant: String
        switch (cpuError, gpuError) {
        case let (cpu?, gpu?) where cpu >= gpu: dominant = "CPU"
        case (_?, _?): dominant = "GPU"
        case (_?, nil): dominant = "CPU"
        case (nil, _?): dominant = "GPU"
        default: dominant = "temperatura"
        }
        let formattedError = String(format: "%+.1f", error)
        return plan(for: effective,
                    reason: "Política por \(dominant): desviación máxima \(formattedError) °C")
    }

    static func plan(for level: MacApplicationPolicyLevel,
                     reason: String) -> MacApplicationPolicyPlan {
        switch level {
        case .normal:
            return MacApplicationPolicyPlan(level: .normal,
                                            throughputTier: -1,
                                            latencyTier: -1,
                                            reason: reason)
        case .efficiency:
            return MacApplicationPolicyPlan(level: .efficiency,
                                            throughputTier: 4,
                                            latencyTier: 4,
                                            reason: reason)
        case .constrained:
            return MacApplicationPolicyPlan(level: .constrained,
                                            throughputTier: 5,
                                            latencyTier: 5,
                                            reason: reason)
        case .emergency:
            return MacApplicationPolicyPlan(level: .emergency,
                                            throughputTier: 5,
                                            latencyTier: 5,
                                            reason: reason)
        }
    }
}
