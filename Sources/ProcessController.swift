import Foundation
import Darwin

struct ProcessControlError: LocalizedError {
    let operation: String
    let code: Int32
    let detail: String

    var errorDescription: String? {
        if !detail.isEmpty {
            return "\(operation): \(detail)"
        }
        if code != 0, let text = String(validatingUTF8: strerror(code)) {
            return "\(operation): \(text) (\(code))"
        }
        return operation
    }
}

final class ProcessController {
    func identityStillMatches(_ process: ProcessSnapshot) -> Bool {
        tb_identity_matches(process.pid, process.identity.startID) == 1
    }

    func applyLowPriority(_ process: ProcessSnapshot) throws {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }
        let target = max(process.niceValue, 10)
        let result = tb_set_nice(process.pid, target)
        guard result == 0 else {
            throw ProcessControlError(operation: "No se pudo reducir la prioridad", code: result, detail: "")
        }
    }

    func setBackground(_ process: ProcessSnapshot, enabled: Bool) throws {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }

        // Ruta principal: API nativa de Darwin. Esto funciona incluso en macOS
        // donde /usr/bin/taskpolicy ya no está instalado.
        let native = tb_set_darwin_background(process.pid, enabled ? 1 : 0)
        if native == 0 { return }

        // Respaldo para versiones antiguas que sí incluyen taskpolicy.
        let taskPolicyPath = "/usr/bin/taskpolicy"
        guard FileManager.default.isExecutableFile(atPath: taskPolicyPath) else {
            throw ProcessControlError(
                operation: enabled ? "No se pudo activar Darwin Background" : "No se pudo restaurar Darwin Background",
                code: native,
                detail: "La API nativa falló y taskpolicy no está disponible"
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: taskPolicyPath)
        task.arguments = [enabled ? "-b" : "-B", "-p", String(process.pid)]
        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.standardOutput = Pipe()

        do {
            try task.run()
        } catch {
            throw ProcessControlError(operation: "No se pudo ejecutar taskpolicy", code: native, detail: error.localizedDescription)
        }

        task.waitUntilExit()
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard task.terminationStatus == 0 else {
            throw ProcessControlError(operation: enabled ? "No se pudo activar el modo de fondo" : "No se pudo restaurar el modo normal",
                                      code: native,
                                      detail: detail)
        }
    }

    var launchQoSClampAvailable: Bool {
        tb_qos_clamp_supported() == 1
    }

    /// Abre una aplicación .app bajo un clamp QoS de lanzamiento. El clamp se
    /// hereda por los hijos creados directamente por la aplicación, sin tocar
    /// Wine, la botella ni la configuración del juego.
    func launchApplication(_ applicationURL: URL,
                           qosClamp: MacLaunchQoSClamp) throws -> Int32 {
        guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw ProcessControlError(operation: "La ruta no corresponde a una aplicación", code: EINVAL, detail: applicationURL.path)
        }
        guard launchQoSClampAvailable else {
            throw ProcessControlError(operation: "Clamp QoS de lanzamiento no disponible", code: ENOTSUP, detail: "libSystem no publica posix_spawnattr_set_qos_clamp_np")
        }

        let executableURL: URL?
        if let bundle = Bundle(url: applicationURL), let bundled = bundle.executableURL {
            executableURL = bundled
        } else {
            let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
            let executableName: String? = {
                guard let data = try? Data(contentsOf: infoURL),
                      let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dictionary = object as? [String: Any] else { return nil }
                return dictionary["CFBundleExecutable"] as? String
            }()
            executableURL = executableName.map {
                applicationURL.appendingPathComponent("Contents/MacOS/\($0)")
            }
        }

        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ProcessControlError(operation: "No se encontró el ejecutable principal", code: ENOENT, detail: applicationURL.path)
        }

        var childPID: Int32 = 0
        let result = executableURL.path.withCString { path in
            tb_spawn_with_qos_clamp(path,
                                    Int32(qosClamp.rawValue),
                                    1,
                                    &childPID)
        }
        guard result == 0 else {
            throw ProcessControlError(operation: "No se pudo abrir la aplicación con QoS \(qosClamp.title)", code: result, detail: executableURL.path)
        }
        return childPID
    }

    /// Ajusta únicamente políticas de planificación proporcionadas por macOS.
    /// Primero usa /usr/bin/taskpolicy, firmado por Apple, porque en versiones
    /// recientes un binario local puede recibir KERN_INVALID_ARGUMENT al usar
    /// task_name_for_pid. El puente Mach queda como respaldo.
    func setSchedulingPolicy(_ process: ProcessSnapshot,
                             throughputTier: Int,
                             latencyTier: Int) throws {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }
        guard (-1...5).contains(throughputTier), (-1...5).contains(latencyTier),
              (throughputTier == -1) == (latencyTier == -1) else {
            throw ProcessControlError(operation: "Tier de planificación inválido", code: EINVAL, detail: "")
        }

        if throughputTier >= 0 {
            let command = runTaskPolicy([
                "-t", String(throughputTier),
                "-l", String(latencyTier),
                "-p", String(process.pid)
            ])
            if command.status == 0 { return }

            let mach = tb_set_qos_tiers(process.pid,
                                        Int32(latencyTier),
                                        Int32(throughputTier))
            guard mach == 0 else {
                let commandDetail = command.detail.isEmpty
                    ? "taskpolicy terminó con código \(command.status)"
                    : command.detail
                throw ProcessControlError(
                    operation: "Políticas macOS no disponibles para este proceso",
                    code: mach,
                    detail: "\(commandDetail) · Mach \(mach)"
                )
            }
            return
        }

        // Restauración exacta primero. Si el kernel rechaza el puerto Mach,
        // taskpolicy tier 3 devuelve los tiers de lanzamiento documentados y
        // evita dejar un proceso atascado en tier 5.
        let mach = tb_set_qos_tiers(process.pid, -1, -1)
        if mach == 0 { return }

        let command = runTaskPolicy([
            "-t", "3", "-l", "3", "-p", String(process.pid)
        ])
        guard command.status == 0 else {
            let commandDetail = command.detail.isEmpty
                ? "taskpolicy terminó con código \(command.status)"
                : command.detail
            throw ProcessControlError(
                operation: "No se pudo restaurar la política de planificación",
                code: mach,
                detail: "\(commandDetail) · Mach \(mach)"
            )
        }
    }

    private func runTaskPolicy(_ arguments: [String]) -> (status: Int32, detail: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
        task.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        task.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let detail = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return (task.terminationStatus, detail)
    }

    func suspend(_ process: ProcessSnapshot, timeoutSeconds: Int) throws -> Process {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }

        let helperURL = helper(named: "TBWatchdog")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw ProcessControlError(operation: "No se encontró TBWatchdog", code: ENOENT, detail: helperURL.path)
        }

        let watchdog = Process()
        watchdog.executableURL = helperURL
        watchdog.arguments = [
            String(ProcessInfo.processInfo.processIdentifier),
            String(process.pid),
            String(process.identity.startID),
            String(max(5, timeoutSeconds))
        ]
        watchdog.standardOutput = Pipe()
        watchdog.standardError = Pipe()

        do {
            try watchdog.run()
        } catch {
            throw ProcessControlError(operation: "No se pudo iniciar el watchdog", code: 0, detail: error.localizedDescription)
        }

        let result = tb_send_signal(process.pid, SIGSTOP)
        guard result == 0 else {
            watchdog.terminate()
            throw ProcessControlError(operation: "No se pudo suspender el proceso", code: result, detail: "")
        }
        return watchdog
    }

    func resume(_ process: ProcessSnapshot) throws {
        guard identityStillMatches(process) else { return }
        let result = tb_send_signal(process.pid, SIGCONT)
        guard result == 0 else {
            throw ProcessControlError(operation: "No se pudo reanudar el proceso", code: result, detail: "")
        }
    }

    func startCPULimiter(_ process: ProcessSnapshot,
                         activityPercent: Int,
                         cycleMilliseconds: Int = 40,
                         pulseMode: ActivityLimiterPulseMode = .burst) throws -> Process {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }

        let helperURL = helper(named: "TBCPULimiter")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw ProcessControlError(operation: "No se encontró TBCPULimiter", code: ENOENT, detail: helperURL.path)
        }

        let clampedActivity = min(max(10, activityPercent), 100)
        try writeCPULimiterActivity(clampedActivity,
                                    pulseMode: pulseMode,
                                    for: process)

        let limiter = Process()
        limiter.executableURL = helperURL
        limiter.arguments = [
            String(ProcessInfo.processInfo.processIdentifier),
            String(process.pid),
            String(process.identity.startID),
            String(clampedActivity),
            String(min(max(4, cycleMilliseconds), 500)),
            String(pulseMode.rawValue),
            limiterControlURL(for: process).path
        ]
        limiter.standardOutput = Pipe()
        limiter.standardError = Pipe()

        do {
            try limiter.run()
        } catch {
            removeCPULimiterControl(for: process)
            throw ProcessControlError(operation: "No se pudo iniciar el limitador de CPU", code: 0, detail: error.localizedDescription)
        }
        return limiter
    }

    /// Supervisa al limitador desde un proceso independiente. Si el helper es
    /// eliminado de forma no interceptable (por ejemplo SIGKILL), reanuda el
    /// PID y sus descendientes que sigan perteneciendo a la misma identidad.
    func startCPULimiterGuardian(_ process: ProcessSnapshot,
                                 limiterPID: Int32) throws -> Process {
        guard identityStillMatches(process), limiterPID > 0 else {
            throw ProcessControlError(operation: "No se puede proteger el limitador",
                                      code: ESRCH, detail: "Identidad no válida")
        }
        let helperURL = helper(named: "TBLimiterGuardian")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw ProcessControlError(operation: "No se encontró TBLimiterGuardian",
                                      code: ENOENT, detail: helperURL.path)
        }
        let guardian = Process()
        guardian.executableURL = helperURL
        guardian.arguments = [
            String(ProcessInfo.processInfo.processIdentifier),
            String(limiterPID),
            String(process.pid),
            String(process.identity.startID)
        ]
        guardian.standardOutput = Pipe()
        guardian.standardError = Pipe()
        do {
            try guardian.run()
        } catch {
            throw ProcessControlError(operation: "No se pudo iniciar el guardián del limitador",
                                      code: 0, detail: error.localizedDescription)
        }
        return guardian
    }

    /// Actualiza el porcentaje sin reiniciar el helper. El limitador relee este
    /// archivo en cada ciclo, evitando pausas largas o procesos helper repetidos.
    func updateCPULimiter(_ process: ProcessSnapshot,
                          activityPercent: Int,
                          pulseMode: ActivityLimiterPulseMode = .burst) throws {
        guard identityStillMatches(process) else {
            throw ProcessControlError(operation: "El proceso ya no existe", code: ESRCH, detail: "")
        }
        try writeCPULimiterActivity(min(max(10, activityPercent), 100),
                                    pulseMode: pulseMode,
                                    for: process)
    }

    func removeCPULimiterControl(for process: ProcessSnapshot) {
        removeCPULimiterControl(for: process.identity)
    }

    func removeCPULimiterControl(for identity: ProcessIdentity) {
        try? FileManager.default.removeItem(at: limiterControlURL(for: identity))
    }

    private func writeCPULimiterActivity(_ activityPercent: Int,
                                         pulseMode: ActivityLimiterPulseMode,
                                         for process: ProcessSnapshot) throws {
        let value = "\(activityPercent) \(pulseMode.rawValue)\n"
        guard let data = value.data(using: .utf8) else {
            throw ProcessControlError(operation: "No se pudo codificar el límite", code: EINVAL, detail: "")
        }
        do {
            try data.write(to: limiterControlURL(for: process.identity), options: .atomic)
        } catch {
            throw ProcessControlError(operation: "No se pudo actualizar el control de actividad",
                                      code: 0,
                                      detail: error.localizedDescription)
        }
    }

    private func limiterControlURL(for process: ProcessSnapshot) -> URL {
        limiterControlURL(for: process.identity)
    }

    private func limiterControlURL(for identity: ProcessIdentity) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.germangomez.thermalbridge.limiter.\(identity.pid).\(identity.startID).txt")
    }

    private func helper(named name: String) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent(name)
    }
}
