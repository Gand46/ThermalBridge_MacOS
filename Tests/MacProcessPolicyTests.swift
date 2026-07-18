import Foundation

@main
struct MacProcessPolicyTests {
    static func main() {
        precondition(MacLaunchQoSClamp.utility.rawValue == 1)
        precondition(MacLaunchQoSClamp.background.rawValue == 2)
        precondition(MacLaunchQoSClamp.maintenance.rawValue == 3)

        let normal = MacApplicationPolicyPlanner.plan(
            cpuTemperature: 70,
            gpuTemperature: 65,
            cpuTarget: 90,
            gpuTarget: 85,
            hysteresis: 3,
            sensorFresh: true,
            thermalState: .nominal,
            currentLevel: .normal
        )
        precondition(normal.level == .normal)
        precondition(normal.throughputTier == -1 && normal.latencyTier == -1)

        let near = MacApplicationPolicyPlanner.plan(
            cpuTemperature: 89.5,
            gpuTemperature: 80,
            cpuTarget: 90,
            gpuTarget: 85,
            hysteresis: 3,
            sensorFresh: true,
            thermalState: .nominal,
            currentLevel: .normal
        )
        precondition(near.level == .efficiency)
        precondition(near.throughputTier == 4 && near.latencyTier == 4)

        let constrained = MacApplicationPolicyPlanner.plan(
            cpuTemperature: 95,
            gpuTemperature: 86,
            cpuTarget: 90,
            gpuTarget: 85,
            hysteresis: 3,
            sensorFresh: true,
            thermalState: .nominal,
            currentLevel: .efficiency
        )
        precondition(constrained.level == .constrained)

        let emergency = MacApplicationPolicyPlanner.plan(
            cpuTemperature: 99,
            gpuTemperature: 87,
            cpuTarget: 90,
            gpuTarget: 85,
            hysteresis: 3,
            sensorFresh: true,
            thermalState: .nominal,
            currentLevel: .constrained
        )
        precondition(emergency.level == .emergency)
        precondition(emergency.throughputTier == 5 && emergency.latencyTier == 5)

        let systemEmergency = MacApplicationPolicyPlanner.plan(
            cpuTemperature: 80,
            gpuTemperature: 70,
            cpuTarget: 90,
            gpuTarget: 85,
            hysteresis: 3,
            sensorFresh: true,
            thermalState: .serious,
            currentLevel: .normal
        )
        precondition(systemEmergency.level == .emergency)

        print("MacProcessPolicyTests: OK")
    }
}
