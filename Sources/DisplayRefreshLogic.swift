import Foundation

enum DisplayRefreshAction: String, Equatable {
    case hold
    case reduce
    case restore
}

/// Decide únicamente la palanca opcional de pantalla. No modifica ni participa
/// en ThermalControlEngine, su integral, histéresis o porcentaje de actividad.
struct DisplayRefreshPlanner {
    static func action(enabled: Bool,
                       sensorFresh: Bool,
                       cpuTemperature: Double?,
                       gpuTemperature: Double?,
                       cpuTarget: Int,
                       gpuTarget: Int,
                       hysteresis: Int,
                       currentlyReduced: Bool) -> DisplayRefreshAction {
        guard enabled, sensorFresh, let gpuTemperature,
              gpuTemperature.isFinite else {
            return currentlyReduced ? .restore : .hold
        }

        let gpuError = gpuTemperature - Double(gpuTarget)
        if currentlyReduced {
            return gpuError <= -Double(max(1, hysteresis)) ? .restore : .hold
        }

        let cpuError = cpuTemperature.map { $0 - Double(cpuTarget) }
            ?? -Double.greatestFiniteMagnitude
        return gpuError >= 0 && gpuError >= cpuError ? .reduce : .hold
    }
}
