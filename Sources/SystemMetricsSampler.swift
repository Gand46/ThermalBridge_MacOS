import Foundation

struct SystemMetricsSample {
    let gpuUtilization: Double?
    let rendererUtilization: Double?
    let tilerUtilization: Double?
    let gpuMemoryBytes: UInt64?
    let source: String
}

final class SystemMetricsSampler {
    func sample() -> SystemMetricsSample {
        let candidates: [(String, [String])] = [
            ("AGXAccelerator", ["-r", "-c", "AGXAccelerator", "-l", "-w", "0"]),
            ("IOAccelerator", ["-r", "-c", "IOAccelerator", "-l", "-w", "0"])
        ]

        for (source, arguments) in candidates {
            guard let output = run(executable: "/usr/sbin/ioreg", arguments: arguments), !output.isEmpty else {
                continue
            }

            let gpu = firstNumber(in: output, keys: [
                "Device Utilization %",
                "GPU Utilization %",
                "GPU Activity(%)",
                "GPU Activity %",
                "GPU Busy %"
            ])
            let renderer = firstNumber(in: output, keys: ["Renderer Utilization %", "Renderer Utilization"])
            let tiler = firstNumber(in: output, keys: ["Tiler Utilization %", "Tiler Utilization"])
            let memory = firstUnsignedInteger(in: output, keys: [
                "In use system memory",
                "In Use System Memory",
                "Allocated system memory",
                "Alloc system memory"
            ])

            if gpu != nil || renderer != nil || tiler != nil || memory != nil {
                let inferredGPU = gpu ?? [renderer, tiler].compactMap { $0 }.max()
                return SystemMetricsSample(
                    gpuUtilization: normalizedPercent(inferredGPU),
                    rendererUtilization: normalizedPercent(renderer),
                    tilerUtilization: normalizedPercent(tiler),
                    gpuMemoryBytes: memory,
                    source: source
                )
            }
        }

        return SystemMetricsSample(
            gpuUtilization: nil,
            rendererUtilization: nil,
            tilerUtilization: nil,
            gpuMemoryBytes: nil,
            source: "No disponible"
        )
    }

    private func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }

    private func firstNumber(in text: String, keys: [String]) -> Double? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\\\"\(escaped)\\\"\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)",
                "\(escaped)\\s*[:=]\\s*([0-9]+(?:\\.[0-9]+)?)"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                if let value = Double(text[valueRange]) { return value }
            }
        }
        return nil
    }

    private func firstUnsignedInteger(in text: String, keys: [String]) -> UInt64? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\\\"\(escaped)\\\"\\s*=\\s*([0-9]+)",
                "\(escaped)\\s*[:=]\\s*([0-9]+)"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                if let value = UInt64(text[valueRange]) { return value }
            }
        }
        return nil
    }

    private func run(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct PowerMetricsSnapshot {
    let date: Date
    let cpuWatts: Double?
    let gpuWatts: Double?
    let aneWatts: Double?
    let totalWatts: Double?
    let rawReport: String
}

enum PowerMetricsError: LocalizedError {
    case unavailable(String)
    case cancelled
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return "powermetrics no está disponible: \(detail)"
        case .cancelled: return "La captura de potencia fue cancelada."
        case .invalidOutput: return "powermetrics no devolvió valores de potencia reconocibles."
        }
    }
}

final class PowerMetricsSampler {
    func capture() throws -> PowerMetricsSnapshot {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/powermetrics") else {
            throw PowerMetricsError.unavailable("no se encontró /usr/bin/powermetrics")
        }

        let help = runUnprivileged(executable: "/usr/bin/powermetrics", arguments: ["-h"]) ?? ""
        var samplers: [String] = []
        if help.localizedCaseInsensitiveContains("cpu_power") { samplers.append("cpu_power") }
        if help.localizedCaseInsensitiveContains("gpu_power") { samplers.append("gpu_power") }
        if help.localizedCaseInsensitiveContains("ane_power") { samplers.append("ane_power") }
        if samplers.isEmpty { samplers = ["cpu_power", "gpu_power"] }

        let arguments = ["-n", "1", "-i", "1000", "--samplers", samplers.joined(separator: ",")]

        let command = (["/usr/bin/powermetrics"] + arguments)
            .map(shellQuote)
            .joined(separator: " ") + " 2>&1"
        let script = "do shell script \"\(escapeAppleScript(command))\" with administrator privileges"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        do {
            try task.run()
        } catch {
            throw PowerMetricsError.unavailable(error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            if detail.localizedCaseInsensitiveContains("cancel") || detail.contains("-128") {
                throw PowerMetricsError.cancelled
            }
            throw PowerMetricsError.unavailable(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let report = String(data: data, encoding: .utf8), !report.isEmpty else {
            throw PowerMetricsError.invalidOutput
        }

        let cpu = powerValue(in: report, labels: ["CPU Power", "CPU power"])
        let gpu = powerValue(in: report, labels: ["GPU Power", "GPU power"])
        let ane = powerValue(in: report, labels: ["ANE Power", "ANE power"])
        let explicitTotal = powerValue(in: report, labels: [
            "Combined Power (CPU + GPU + ANE)",
            "Combined Power",
            "Package Power",
            "System Power"
        ])
        let componentTotal = [cpu, gpu, ane].compactMap { $0 }.reduce(0, +)
        let total = explicitTotal ?? (componentTotal > 0 ? componentTotal : nil)

        guard cpu != nil || gpu != nil || ane != nil || total != nil else {
            throw PowerMetricsError.invalidOutput
        }

        return PowerMetricsSnapshot(
            date: Date(),
            cpuWatts: cpu,
            gpuWatts: gpu,
            aneWatts: ane,
            totalWatts: total,
            rawReport: report
        )
    }

    private func powerValue(in text: String, labels: [String]) -> Double? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "\(escaped)\\s*[:=]\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(mW|W)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange]) else { continue }
            return text[unitRange].lowercased() == "mw" ? number / 1000.0 : number
        }
        return nil
    }

    private func runUnprivileged(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error
        do { try task.run() } catch { return nil }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: stdout + stderr, encoding: .utf8)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
