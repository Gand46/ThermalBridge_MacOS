import Foundation

@main
struct SensorParsingTests {
    static func main() {
        testMaximumSensorPayload()
        testMacMonFallbackPayload()
        print("SensorParsingTests: OK")
    }

    static func testMaximumSensorPayload() {
        let json = #"""
        {
          "timestamp_epoch":1783984695.427569,
          "cpu_temp_max":96.50,
          "gpu_temp_max":88.25,
          "cpu_temp_avg":82.75,
          "gpu_temp_avg":78.25,
          "cpu_max_sensor":"Tp09",
          "gpu_max_sensor":"Tg0f",
          "cpu_sensor_count":14,
          "gpu_sensor_count":4
        }
        """#
        guard let reading = MacMonTemperatureSensor.decodeMaximumReading(
            from: json,
            cpuPowerWatts: 8.42,
            gpuPowerWatts: 4.10,
            cpuEffectiveUsage: 0.51,
            gpuEffectiveUsage: 0.73
        ) else {
            preconditionFailure("No se pudo decodificar la muestra máxima")
        }
        precondition(reading.cpuMaximumCelsius == 96.50)
        precondition(reading.gpuMaximumCelsius == 88.25)
        precondition(reading.cpuControlCelsius == 96.50)
        precondition(reading.gpuControlCelsius == 88.25)
        precondition(reading.cpuAverageCelsius == 82.75)
        precondition(reading.cpuMaximumSensor == "Tp09")
        precondition(reading.gpuMaximumSensor == "Tg0f")
        precondition(reading.cpuSensorCount == 14)
        precondition(reading.gpuSensorCount == 4)
        precondition(reading.cpuPowerWatts == 8.42)
        precondition(reading.gpuEffectiveUsage == 0.73)
    }

    static func testMacMonFallbackPayload() {
        let json = #"""
        {
          "timestamp":"2026-07-13T20:38:15.427569+00:00",
          "temp":{"cpu_temp_avg":82.75,"gpu_temp_avg":78.25},
          "cpu_power":8.42,
          "gpu_power":4.10,
          "cpu_usage_pct":0.51,
          "gpu_usage":[950,0.73]
        }
        """#
        guard let reading = MacMonTemperatureSensor.decodeReading(from: json) else {
            preconditionFailure("No se pudo decodificar la muestra macmon")
        }
        precondition(reading.cpuAverageCelsius == 82.75)
        precondition(reading.gpuAverageCelsius == 78.25)
        precondition(reading.cpuControlCelsius == 82.75)
        precondition(reading.gpuControlCelsius == 78.25)
        precondition(reading.source == "macmon-average-fallback")
        precondition(MacMonTemperatureSensor.decodeReading(from: "{}") == nil)
        precondition(MacMonTemperatureSensor.decodeMaximumReading(from: "{}") == nil)
    }
}
