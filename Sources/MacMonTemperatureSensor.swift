@preconcurrency import Foundation

/// Coordinador térmico. Usa el helper integrado TBTemperatureSensor para leer
/// el valor máximo instantáneo entre sensores AppleSMC e IOHID de CPU y GPU.
/// La clasificación incluye la familia TC usada por MacThermal (por ejemplo
/// TCMb) y pACC/eACC/mACC/GPU HID. macmon queda como fuente opcional de
/// potencia/uso y como respaldo de promedio.
final class MacMonTemperatureSensor: @unchecked Sendable {
    enum SensorState: Equatable {
        case stopped
        case starting(String)
        case running(String)
        case unavailable(String)
        case failed(String)

        var description: String {
            switch self {
            case .stopped: return "Detenido"
            case .starting(let detail): return "Iniciando: \(detail)"
            case .running(let detail): return "Activo: \(detail)"
            case .unavailable(let detail): return "No disponible: \(detail)"
            case .failed(let detail): return "Error: \(detail)"
            }
        }
    }

    var onReading: ((TemperatureReading) -> Void)?
    var onStateChange: ((SensorState) -> Void)?

    private struct AuxiliaryMetrics {
        var cpuPowerWatts: Double?
        var gpuPowerWatts: Double?
        var cpuEffectiveUsage: Double?
        var gpuEffectiveUsage: Double?
    }

    private let queue = DispatchQueue(label: "ThermalBridge.MaximumTemperatureSensor", qos: .utility)
    private var temperatureTask: Process?
    private var metricsTask: Process?
    private var temperatureOutputBuffer = ""
    private var temperatureErrorBuffer = ""
    private var metricsOutputBuffer = ""
    private var metricsErrorBuffer = ""
    private var latestMetrics = AuxiliaryMetrics()
    private var latestMetricsDate: Date?
    private var primaryMaximumSensorRunning = false
    private var requestedStop = false

    var temperatureHelperPath: String? {
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/TBTemperatureSensor")
            .path
        if FileManager.default.isExecutableFile(atPath: bundleCandidate) {
            return bundleCandidate
        }

        // Permite ejecutar desde la carpeta del proyecto durante desarrollo.
        let localCandidates = [
            FileManager.default.currentDirectoryPath + "/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor",
            FileManager.default.currentDirectoryPath + "/.build/TBTemperatureSensor"
        ]
        return localCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    var macmonExecutablePath: String? {
        let candidates = [
            "/opt/homebrew/bin/macmon",
            "/usr/local/bin/macmon",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin/macmon"
        ]
        if let direct = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return direct
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["macmon"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// Compatibilidad con el código existente: el sensor primario es el helper
    /// máximo; macmon solo es obligatorio cuando se desean potencia y uso.
    var executablePath: String? {
        temperatureHelperPath ?? macmonExecutablePath
    }

    func start(intervalMilliseconds: Int = 1000) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked(notify: false)
            self.requestedStop = false
            self.latestMetrics = AuxiliaryMetrics()
            self.latestMetricsDate = nil
            self.temperatureOutputBuffer = ""
            self.temperatureErrorBuffer = ""
            self.metricsOutputBuffer = ""
            self.metricsErrorBuffer = ""
            self.primaryMaximumSensorRunning = false

            let interval = max(250, intervalMilliseconds)
            let helperPath = self.temperatureHelperPath
            let macmonPath = self.macmonExecutablePath

            guard helperPath != nil || macmonPath != nil else {
                self.notifyState(.unavailable("no se encontró el sensor integrado ni macmon"))
                return
            }

            self.notifyState(.starting(helperPath != nil
                                       ? "sensor máximo SMC"
                                       : "respaldo de promedio macmon"))

            if let helperPath {
                self.startMaximumSensor(path: helperPath, intervalMilliseconds: interval)
            }
            if let macmonPath {
                self.startMetricsSensor(path: macmonPath, intervalMilliseconds: interval)
            }

            if self.temperatureTask != nil {
                self.notifyState(.running(macmonPath == nil
                    ? "máximo instantáneo SMC"
                    : "máximo instantáneo SMC + potencia macmon"))
            } else if self.metricsTask != nil {
                self.notifyState(.running("promedio macmon como respaldo; no se dispone del máximo por sensor"))
            } else {
                self.notifyState(.failed("no fue posible iniciar ninguna fuente térmica"))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopLocked(notify: true) }
    }

    private func startMaximumSensor(path: String, intervalMilliseconds: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--interval", String(intervalMilliseconds)]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { [weak self] in self?.consumeMaximumSensor(text) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { [weak self] in self?.temperatureErrorBuffer.append(text) }
        }
        process.terminationHandler = { [weak self] terminated in
            self?.queue.async { [weak self] in
                self?.handleMaximumSensorTermination(terminated,
                                                     output: output,
                                                     errorPipe: errorPipe)
            }
        }

        do {
            try process.run()
            temperatureTask = process
            primaryMaximumSensorRunning = true
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            temperatureTask = nil
            primaryMaximumSensorRunning = false
            temperatureErrorBuffer = error.localizedDescription
        }
    }

    private func startMetricsSensor(path: String, intervalMilliseconds: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["pipe", "--samples", "0", "--interval", String(max(500, intervalMilliseconds))]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { [weak self] in self?.consumeMacMon(text) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { [weak self] in self?.metricsErrorBuffer.append(text) }
        }
        process.terminationHandler = { [weak self] terminated in
            self?.queue.async { [weak self] in
                self?.handleMetricsTermination(terminated,
                                               output: output,
                                               errorPipe: errorPipe)
            }
        }

        do {
            try process.run()
            metricsTask = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            metricsTask = nil
            metricsErrorBuffer = error.localizedDescription
        }
    }

    private func stopLocked(notify: Bool) {
        requestedStop = true
        terminate(task: temperatureTask)
        terminate(task: metricsTask)
        temperatureTask = nil
        metricsTask = nil
        primaryMaximumSensorRunning = false
        latestMetrics = AuxiliaryMetrics()
        latestMetricsDate = nil
        temperatureOutputBuffer = ""
        metricsOutputBuffer = ""
        if notify { notifyState(.stopped) }
    }

    private func terminate(task: Process?) {
        guard let task else { return }
        task.terminationHandler = nil
        (task.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (task.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if task.isRunning { task.terminate() }
    }

    private func handleMaximumSensorTermination(_ terminated: Process,
                                                output: Pipe,
                                                errorPipe: Pipe) {
        guard temperatureTask?.processIdentifier == terminated.processIdentifier else { return }
        output.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        temperatureTask = nil
        primaryMaximumSensorRunning = false
        guard !requestedStop else { return }

        let detail = temperatureErrorBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if metricsTask != nil {
            notifyState(.failed("sensor máximo detenido; usando promedio macmon. \(detail)"))
        } else {
            notifyState(.failed(detail.isEmpty
                                ? "el sensor máximo terminó inesperadamente"
                                : detail))
        }
    }

    private func handleMetricsTermination(_ terminated: Process,
                                          output: Pipe,
                                          errorPipe: Pipe) {
        guard metricsTask?.processIdentifier == terminated.processIdentifier else { return }
        output.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        metricsTask = nil
        latestMetrics = AuxiliaryMetrics()
        latestMetricsDate = nil
        guard !requestedStop else { return }

        if temperatureTask != nil {
            notifyState(.running("máximo instantáneo SMC; potencia macmon no disponible"))
        } else {
            let detail = metricsErrorBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyState(.failed(detail.isEmpty ? "macmon terminó inesperadamente" : detail))
        }
    }

    private func consumeMaximumSensor(_ text: String) {
        temperatureOutputBuffer.append(text)
        let objects = extractJSONObjectStrings(from: &temperatureOutputBuffer)
        for object in objects {
            let metrics = freshAuxiliaryMetrics()
            guard let reading = Self.decodeMaximumReading(from: object,
                                                          cpuPowerWatts: metrics.cpuPowerWatts,
                                                          gpuPowerWatts: metrics.gpuPowerWatts,
                                                          cpuEffectiveUsage: metrics.cpuEffectiveUsage,
                                                          gpuEffectiveUsage: metrics.gpuEffectiveUsage) else { continue }
            emit(reading)
        }
    }

    private func consumeMacMon(_ text: String) {
        metricsOutputBuffer.append(text)
        let objects = extractJSONObjectStrings(from: &metricsOutputBuffer)
        for object in objects {
            guard let reading = Self.decodeReading(from: object) else { continue }
            latestMetrics = AuxiliaryMetrics(cpuPowerWatts: reading.cpuPowerWatts,
                                             gpuPowerWatts: reading.gpuPowerWatts,
                                             cpuEffectiveUsage: reading.cpuEffectiveUsage,
                                             gpuEffectiveUsage: reading.gpuEffectiveUsage)
            latestMetricsDate = Date()
            // Respaldo: solo controla con promedios si el helper máximo no está activo.
            if !primaryMaximumSensorRunning {
                emit(reading)
            }
        }
    }

    private func freshAuxiliaryMetrics(now: Date = Date()) -> AuxiliaryMetrics {
        guard let latestMetricsDate,
              now.timeIntervalSince(latestMetricsDate) <= 3.5 else {
            return AuxiliaryMetrics()
        }
        return latestMetrics
    }

    private func emit(_ reading: TemperatureReading) {
        DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
    }

    /// Decodifica la salida del helper integrado. El control usa cpu/gpu max,
    /// mientras los promedios quedan disponibles únicamente como referencia.
    static func decodeMaximumReading(from json: String,
                                     cpuPowerWatts: Double? = nil,
                                     gpuPowerWatts: Double? = nil,
                                     cpuEffectiveUsage: Double? = nil,
                                     gpuEffectiveUsage: Double? = nil) -> TemperatureReading? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MaximumTemperaturePayload.self, from: data) else {
            return nil
        }
        let date = payload.timestampEpoch.map(Date.init(timeIntervalSince1970:)) ?? Date()
        let reading = TemperatureReading(
            date: date,
            cpuMaximumCelsius: payload.cpuTempMax,
            gpuMaximumCelsius: payload.gpuTempMax,
            cpuAverageCelsius: payload.cpuTempAvg,
            gpuAverageCelsius: payload.gpuTempAvg,
            cpuMaximumSensor: payload.cpuMaxSensor,
            gpuMaximumSensor: payload.gpuMaxSensor,
            cpuSensorCount: payload.cpuSensorCount,
            gpuSensorCount: payload.gpuSensorCount,
            cpuPowerWatts: cpuPowerWatts,
            gpuPowerWatts: gpuPowerWatts,
            cpuEffectiveUsage: cpuEffectiveUsage,
            gpuEffectiveUsage: gpuEffectiveUsage,
            source: "TBTemperatureSensor-max"
        )
        return reading.hasTemperature ? reading : nil
    }

    /// Decodifica macmon. Como macmon solo publica promedios, en modo de
    /// respaldo esos valores también ocupan el campo máximo para conservar un
    /// control preventivo explícitamente marcado como no-hotspot.
    static func decodeReading(from json: String) -> TemperatureReading? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MacMonPayload.self, from: data) else { return nil }
        let reading = TemperatureReading(
            date: payload.parsedDate ?? Date(),
            cpuMaximumCelsius: payload.temp?.cpuTempAvg,
            gpuMaximumCelsius: payload.temp?.gpuTempAvg,
            cpuAverageCelsius: payload.temp?.cpuTempAvg,
            gpuAverageCelsius: payload.temp?.gpuTempAvg,
            cpuMaximumSensor: nil,
            gpuMaximumSensor: nil,
            cpuSensorCount: 0,
            gpuSensorCount: 0,
            cpuPowerWatts: payload.cpuPower,
            gpuPowerWatts: payload.gpuPower,
            cpuEffectiveUsage: payload.cpuUsagePct,
            gpuEffectiveUsage: payload.gpuUsage?.last,
            source: "macmon-average-fallback"
        )
        return reading.hasTemperature ? reading : nil
    }

    private func notifyState(_ state: SensorState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }

    /// Extrae objetos JSON completos de un flujo que puede venir en una o varias líneas.
    private func extractJSONObjectStrings(from buffer: inout String) -> [String] {
        var results: [String] = []
        var start: String.Index?
        var depth = 0
        var insideString = false
        var escaped = false
        var index = buffer.startIndex
        var consumedThrough: String.Index?

        while index < buffer.endIndex {
            let character = buffer[index]
            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
            } else {
                if character == "\"" {
                    insideString = true
                } else if character == "{" {
                    if depth == 0 { start = index }
                    depth += 1
                } else if character == "}", depth > 0 {
                    depth -= 1
                    if depth == 0, let objectStart = start {
                        let end = buffer.index(after: index)
                        results.append(String(buffer[objectStart..<end]))
                        consumedThrough = end
                        start = nil
                    }
                }
            }
            index = buffer.index(after: index)
        }

        if let consumedThrough {
            buffer.removeSubrange(buffer.startIndex..<consumedThrough)
        } else if buffer.count > 1_000_000 {
            buffer.removeAll(keepingCapacity: true)
        }
        return results
    }
}

private struct MaximumTemperaturePayload: Decodable {
    let timestampEpoch: Double?
    let cpuTempMax: Double?
    let gpuTempMax: Double?
    let cpuTempAvg: Double?
    let gpuTempAvg: Double?
    let cpuMaxSensor: String?
    let gpuMaxSensor: String?
    let cpuSensorCount: Int
    let gpuSensorCount: Int

    enum CodingKeys: String, CodingKey {
        case timestampEpoch = "timestamp_epoch"
        case cpuTempMax = "cpu_temp_max"
        case gpuTempMax = "gpu_temp_max"
        case cpuTempAvg = "cpu_temp_avg"
        case gpuTempAvg = "gpu_temp_avg"
        case cpuMaxSensor = "cpu_max_sensor"
        case gpuMaxSensor = "gpu_max_sensor"
        case cpuSensorCount = "cpu_sensor_count"
        case gpuSensorCount = "gpu_sensor_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampEpoch = try container.decodeIfPresent(Double.self, forKey: .timestampEpoch)
        cpuTempMax = try container.decodeIfPresent(Double.self, forKey: .cpuTempMax)
        gpuTempMax = try container.decodeIfPresent(Double.self, forKey: .gpuTempMax)
        cpuTempAvg = try container.decodeIfPresent(Double.self, forKey: .cpuTempAvg)
        gpuTempAvg = try container.decodeIfPresent(Double.self, forKey: .gpuTempAvg)
        cpuMaxSensor = try container.decodeIfPresent(String.self, forKey: .cpuMaxSensor)
        gpuMaxSensor = try container.decodeIfPresent(String.self, forKey: .gpuMaxSensor)
        cpuSensorCount = try container.decodeIfPresent(Int.self, forKey: .cpuSensorCount) ?? 0
        gpuSensorCount = try container.decodeIfPresent(Int.self, forKey: .gpuSensorCount) ?? 0
    }
}

private struct MacMonPayload: Decodable {
    struct Temperature: Decodable {
        let cpuTempAvg: Double?
        let gpuTempAvg: Double?

        enum CodingKeys: String, CodingKey {
            case cpuTempAvg = "cpu_temp_avg"
            case gpuTempAvg = "gpu_temp_avg"
        }
    }

    let timestamp: String?
    let temp: Temperature?
    let cpuPower: Double?
    let gpuPower: Double?
    let cpuUsagePct: Double?
    let gpuUsage: [Double]?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case temp
        case cpuPower = "cpu_power"
        case gpuPower = "gpu_power"
        case cpuUsagePct = "cpu_usage_pct"
        case gpuUsage = "gpu_usage"
    }

    var parsedDate: Date? {
        guard let timestamp else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: timestamp) { return date }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}
