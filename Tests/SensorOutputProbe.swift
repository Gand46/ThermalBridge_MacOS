import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct SensorOutputProbe {
    private static func fail(_ message: String, code: Int32 = 2) -> Never {
        fputs("SensorOutputProbe: ERROR: \(message)\n", stderr)
        exit(code)
    }

    private static func isNumberOrNull(_ value: Any?) -> Bool {
        value is NSNumber || value is NSNull
    }

    private static func isStringOrNull(_ value: Any?) -> Bool {
        value is String || value is NSNull
    }

    static func main() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else {
            fail("la salida del sensor está vacía")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<datos no UTF-8>"
            fail("JSON inválido: \(error.localizedDescription). Salida: \(raw)")
        }

        guard let payload = object as? [String: Any] else {
            fail("la raíz JSON no es un objeto")
        }

        let requiredKeys: Set<String> = [
            "timestamp_epoch",
            "cpu_temp_max",
            "gpu_temp_max",
            "cpu_temp_avg",
            "gpu_temp_avg",
            "cpu_max_sensor",
            "gpu_max_sensor",
            "cpu_sensor_count",
            "gpu_sensor_count"
        ]
        let missing = requiredKeys.subtracting(payload.keys)
        guard missing.isEmpty else {
            fail("faltan campos: \(missing.sorted().joined(separator: ", "))")
        }

        guard payload["timestamp_epoch"] is NSNumber else {
            fail("timestamp_epoch no es numérico")
        }
        for key in ["cpu_temp_max", "gpu_temp_max", "cpu_temp_avg", "gpu_temp_avg"] {
            guard isNumberOrNull(payload[key]) else {
                fail("\(key) no es número ni null")
            }
        }
        for key in ["cpu_max_sensor", "gpu_max_sensor"] {
            guard isStringOrNull(payload[key]) else {
                fail("\(key) no es texto ni null")
            }
        }
        guard let cpuCount = payload["cpu_sensor_count"] as? NSNumber,
              let gpuCount = payload["gpu_sensor_count"] as? NSNumber else {
            fail("los conteos de sensores no son numéricos")
        }
        guard cpuCount.intValue >= 0, gpuCount.intValue >= 0 else {
            fail("los conteos de sensores no pueden ser negativos")
        }
        guard cpuCount.intValue > 0 || gpuCount.intValue > 0 else {
            fail("la muestra no contiene sensores CPU ni GPU")
        }
        guard payload["iohid_available"] is Bool else {
            fail("iohid_available no es booleano")
        }

        let cpu = payload["cpu_temp_max"] as? NSNumber
        let gpu = payload["gpu_temp_max"] as? NSNumber
        let cpuText = cpu.map { String(format: "%.3f", $0.doubleValue) } ?? "null"
        let gpuText = gpu.map { String(format: "%.3f", $0.doubleValue) } ?? "null"
        print("SensorOutputProbe: OK (CPU max=\(cpuText), GPU max=\(gpuText), sensores=\(cpuCount)+\(gpuCount))")
    }
}
