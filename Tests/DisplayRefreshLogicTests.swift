import Foundation

@main
struct DisplayRefreshLogicTests {
    static func main() {
        precondition(DisplayRefreshPlanner.action(
            enabled: false, sensorFresh: true,
            cpuTemperature: 80, gpuTemperature: 90,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: false
        ) == .hold)
        precondition(DisplayRefreshPlanner.action(
            enabled: false, sensorFresh: true,
            cpuTemperature: 80, gpuTemperature: 90,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: true
        ) == .restore)

        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: true,
            cpuTemperature: 84, gpuTemperature: 86,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: false
        ) == .reduce)

        // CPU dominante: la capa GPU no debe actuar.
        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: true,
            cpuTemperature: 96, gpuTemperature: 86,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: false
        ) == .hold)

        // Una vez aplicado se conserva hasta cruzar la histéresis de GPU.
        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: true,
            cpuTemperature: 80, gpuTemperature: 83,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: true
        ) == .hold)
        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: true,
            cpuTemperature: 80, gpuTemperature: 82,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: true
        ) == .restore)

        // Ante pérdida del sensor se restaura para no conservar una palanca
        // global sin evidencia reciente.
        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: false,
            cpuTemperature: nil, gpuTemperature: nil,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: true
        ) == .restore)
        precondition(DisplayRefreshPlanner.action(
            enabled: true, sensorFresh: true,
            cpuTemperature: 95, gpuTemperature: nil,
            cpuTarget: 90, gpuTarget: 85, hysteresis: 3,
            currentlyReduced: false
        ) == .hold)

        print("DisplayRefreshLogicTests: OK")
    }
}
