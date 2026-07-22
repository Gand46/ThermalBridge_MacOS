import AppKit
import Foundation

extension ProcessStore {
    var automaticThermalProcess: ProcessSnapshot? {
        guard let automaticThermalProcessID else { return nil }
        return process(for: automaticThermalProcessID)
    }

    var automaticThermalGameCandidates: [ProcessSnapshot] {
        let preferredTargetIsCurrent = automaticThermalPreferredExecutableNeedle
            == automaticThermalConfiguration.normalizedExecutableNeedle
        return crossOverSelectableProcesses.sorted { lhs, rhs in
            if lhs.identity == automaticThermalProcessID { return true }
            if rhs.identity == automaticThermalProcessID { return false }
            if preferredTargetIsCurrent,
               lhs.identity == automaticThermalPreferredProcessID { return true }
            if preferredTargetIsCurrent,
               rhs.identity == automaticThermalPreferredProcessID { return false }

            let leftRelated = isCrossOverRelated(lhs)
            let rightRelated = isCrossOverRelated(rhs)
            if leftRelated != rightRelated { return leftRelated }

            let leftScore = automaticThermalConfiguration.matchScore(for: lhs) ?? 0
            let rightScore = automaticThermalConfiguration.matchScore(for: rhs) ?? 0
            if leftScore != rightScore { return leftScore > rightScore }

            let leftResolved = lhs.windowsExecutableName != nil
            let rightResolved = rhs.windowsExecutableName != nil
            if leftResolved != rightResolved { return leftResolved }

            let leftGame = isCrossOverGameCandidate(lhs)
            let rightGame = isCrossOverGameCandidate(rhs)
            if leftGame != rightGame { return leftGame }

            // El orden de primera aparición evita que la lista salte por CPU,
            // nombre temporal o PIDs creados por Wine durante el arranque.
            return stableOrder(for: lhs) < stableOrder(for: rhs)
        }
    }

    var automaticThermalResolvedCandidateCount: Int {
        automaticThermalGameCandidates.filter { $0.windowsExecutableName != nil }.count
    }

    private var automaticCrossOverMatchCandidates: [ProcessSnapshot] {
        crossOverSelectableProcesses.filter(isCrossOverRelated)
    }

    var temperatureSensorAvailable: Bool {
        switch temperatureSensorState {
        case .running, .starting:
            return true
        case .failed:
            return temperatureReadingFresh
        case .unavailable:
            return false
        case .stopped:
            return temperatureSensor.executablePath != nil
        }
    }

    var temperatureReadingFresh: Bool {
        guard let lastTemperatureReadingDate else { return false }
        return Date().timeIntervalSince(lastTemperatureReadingDate) <= 4.0
    }

    var cpuTemperatureText: String {
        temperatureText(cpuTemperatureCelsius)
    }

    var gpuTemperatureText: String {
        temperatureText(gpuTemperatureCelsius)
    }

    var cpuAverageTemperatureText: String {
        temperatureText(cpuAverageTemperatureCelsius)
    }

    var gpuAverageTemperatureText: String {
        temperatureText(gpuAverageTemperatureCelsius)
    }

    var usingMaximumTemperatureSensor: Bool {
        temperatureReadingSource == "TBTemperatureSensor-max"
            && (cpuTemperatureSensorCount > 0 || gpuTemperatureSensorCount > 0)
    }

    var cpuSmoothedTemperatureText: String {
        temperatureText(cpuTemperatureSmoothedCelsius)
    }

    var gpuSmoothedTemperatureText: String {
        temperatureText(gpuTemperatureSmoothedCelsius)
    }

    var automaticThermalActivityText: String {
        "\(automaticThermalActivityPercent)%"
    }

    var automaticMacPolicyText: String {
        guard automaticMacPolicyEnabled else { return "Desactivada" }
        return automaticMacPolicyRuntimeAvailable ? automaticMacPolicyLevel.title : "No disponible"
    }

    var automaticMacPolicyDetail: String {
        guard automaticMacPolicyEnabled else {
            return "Solo se mantiene el control de actividad existente"
        }
        return automaticMacPolicyStatus
    }

    var crossOverQoSLaunchAvailable: Bool {
        controller.launchQoSClampAvailable
    }

    var automaticQoSEvidenceText: String {
        let requested = automaticQoSEvidence.requestedClass?.rawValue ?? "sin solicitud"
        let dominant = automaticQoSEvidence.dominantClass?.rawValue
        switch automaticQoSEvidence.state {
        case .confirmed:
            return "Confirmado por kernel: \(requested)"
        case .inferred:
            return "Solicitado \(requested); todavía sin tiempo CPU en la ventana"
        case .notObserved:
            return "No observado: \(requested)" + (dominant.map { " · dominante \($0)" } ?? "")
        case .unavailable:
            if automaticTreeResourceMetrics?.qosSampledProcessCount ?? 0 > 0,
               automaticQoSEvidence.requestedClass == nil {
                return "Contadores disponibles; no hay clamp de lanzamiento solicitado"
                    + (dominant.map { " · dominante \($0)" } ?? "")
            }
            return "QoS efectivo no disponible en esta muestra"
        case .failed:
            return "La solicitud QoS falló"
        }
    }

    var automaticEnergyEvidenceText: String {
        guard let energy = automaticTreeResourceMetrics?.directEnergyNJ else {
            return "Energía directa no disponible"
        }
        return String(format: "Energía del árbol: %.3f mJ por muestra", Double(energy) / 1_000_000.0)
    }

    var automaticPowerAnticipationDetail: String {
        guard automaticPowerAnticipationEnabled else { return "Desactivada" }
        guard sensorCPUPowerWatts != nil || sensorGPUPowerWatts != nil else {
            return "Activa; esperando potencia de macmon"
        }
        return "Activa con potencia y tendencia térmica"
    }

    var automaticThermalSensorDetail: String {
        if temperatureReadingFresh {
            guard usingMaximumTemperatureSensor else {
                return "Respaldo por promedio macmon; no representa el sensor individual más caliente"
            }
            let cpuName = cpuMaximumSensorName.map { "CPU \($0)" } ?? "CPU sin nombre"
            let gpuName = gpuMaximumSensorName.map { "GPU \($0)" } ?? "GPU sin nombre"
            let counts = "\(cpuTemperatureSensorCount) sensores CPU / \(gpuTemperatureSensorCount) GPU"
            return "Máximos instantáneos: \(cpuName), \(gpuName) · \(counts)"
        }
        return temperatureSensorState.description
    }

    func prepareAutomaticThermalMode() {
        migrateAutomaticThermalConfiguration()
        disablePreviousAutomaticSystems()

        temperatureSensor.onReading = { [weak self] reading in
            self?.acceptTemperatureReading(reading)
        }
        temperatureSensor.onStateChange = { [weak self] state in
            guard let self else { return }
            self.temperatureSensorState = state
            if case .running = state {
                self.automaticThermalStatus = self.automaticThermalEnabled
                    ? self.automaticThermalStatus
                    : "Sensor listo; selecciona un juego"
            }
        }
        temperatureSensor.start(intervalMilliseconds: 1000)

        if automaticSelectHighestCPUExecutableEnabled,
           !automaticThermalConfiguration.executableContains.isEmpty {
            var configuration = automaticThermalConfiguration
            configuration.executableContains = ""
            automaticThermalPreferredProcessID = nil
            automaticThermalPreferredExecutableNeedle = nil
            automaticThermalSessionIDs.removeAll()
            automaticThermalConfiguration = configuration
        }

        if automaticThermalConfiguration.autoAttach,
           automaticThermalConfiguration.hasTarget {
            automaticThermalEnabled = true
            automaticThermalEngine.reset(activityPercent: automaticThermalConfiguration.maximumActivityPercent)
            automaticThermalActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticThermalRequestedActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticLimiterPulseMode = automaticAudioProtectionEnabled ? .audioSafe : .burst
            automaticThermalStatus = "Armado; esperando \(automaticThermalConfiguration.executableContains)"
            automaticThermalReason = "Autoaplicación restaurada al iniciar"
        }
    }

    func restartTemperatureSensor() {
        temperatureSensor.start(intervalMilliseconds: 1000)
    }

    func openTemperatureSensorInstaller() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Instalar_Sensor_macmon.command"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Instalar_Sensor_macmon.command")
        ].compactMap { $0 }

        guard let installer = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            addLog("No se encontró Instalar_Sensor_macmon.command. El sensor máximo integrado no requiere esta instalación.", isError: true)
            return
        }
        NSWorkspace.shared.open(installer)
    }

    func updateAutomaticThermalExecutableName(_ rawValue: String) {
        var configuration = automaticThermalConfiguration
        let previousNeedle = configuration.normalizedExecutableNeedle
        configuration.executableContains = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nextNeedle = configuration.normalizedExecutableNeedle
        if previousNeedle != nextNeedle,
           automaticThermalPreferredExecutableNeedle != nextNeedle {
            automaticThermalPreferredProcessID = nil
            automaticThermalPreferredExecutableNeedle = nil
            automaticThermalSessionIDs.removeAll()
        }
        automaticThermalConfiguration = configuration
    }

    func captureAutomaticThermalGame(_ process: ProcessSnapshot) {
        guard isCrossOverSelectableProcess(process) else {
            automaticThermalStatus = "El proceso seleccionado no pertenece a un juego de CrossOver"
            return
        }

        var configuration = automaticThermalConfiguration
        let manual = configuration.executableContains
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manualIsExecutable = manual.lowercased().hasSuffix(".exe")
        let directProcessName = process.name.lowercased().hasSuffix(".exe")

        if automaticSelectHighestCPUExecutableEnabled {
            configuration.executableContains = ""
            configuration.bottleName = process.crossOverBottleName ?? configuration.bottleName
            automaticThermalPreferredProcessID = process.identity
            automaticThermalPreferredExecutableNeedle = nil
            automaticThermalSessionIDs.formUnion(automaticSessionIdentities(around: process))
            automaticThermalConfiguration = configuration
            automaticThermalStatus = "Proceso automático: \(process.displayName)"
            automaticThermalReason = "Auto .exe por CPU activo; asociación limitada a esta sesión"
            addLog("CrossOver: PID \(process.pid) seleccionado por mayor CPU sin guardar .exe persistente.")
            return
        }

        if manualIsExecutable,
           process.containsWindowsExecutable(named: manual) {
            // La selección confirma el objetivo escrito, sin cambiar mayúsculas
            // ni sustituirlo por otro .exe encontrado en el mismo comando.
            configuration.executableContains = manual
        } else if manualIsExecutable,
                  !directProcessName {
            // Un wine64-preloader puede publicar ejecutables auxiliares de forma
            // intermitente. Al asociarlo manualmente, conserva el .exe escrito.
            configuration.executableContains = manual
        } else if let executable = process.windowsExecutableName {
            configuration.executableContains = executable
        } else {
            configuration.bottleName = process.crossOverBottleName ?? configuration.bottleName
            automaticThermalPreferredProcessID = process.identity
            automaticThermalPreferredExecutableNeedle = nil
            automaticThermalSessionIDs.formUnion(automaticSessionIdentities(around: process))
            automaticThermalConfiguration = configuration
            automaticThermalStatus = "Proceso seleccionado: \(process.displayName)"
            automaticThermalReason = "Selección manual explícita sin .exe; se controla esta sesión y sus descendientes"
            addLog("CrossOver: PID \(process.pid) seleccionado sin nombre .exe; asociación limitada a la sesión.")
            return
        }

        configuration.bottleName = process.crossOverBottleName ?? configuration.bottleName
        automaticThermalPreferredProcessID = process.identity
        automaticThermalPreferredExecutableNeedle = configuration.normalizedExecutableNeedle
        automaticThermalSessionIDs.formUnion(automaticSessionIdentities(around: process))
        automaticThermalConfiguration = configuration
        automaticThermalStatus = "Juego guardado: \(configuration.executableContains)"
        automaticThermalReason = configuration.bottleName.isEmpty
            ? "Ejecutable confirmado; botella todavía no visible"
            : "Botella asociada: \(configuration.bottleName)"
        addLog("Modo térmico: \(configuration.executableContains) capturado"
               + (configuration.bottleName.isEmpty ? "." : " en \(configuration.bottleName)."))
    }

    func captureAutomaticThermalExecutable(at url: URL) {
        guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else {
            automaticThermalStatus = "El archivo seleccionado no termina en .exe"
            addLog("CrossOver: archivo no válido: \(url.lastPathComponent)", isError: true)
            return
        }

        var configuration = automaticThermalConfiguration
        configuration.executableContains = url.lastPathComponent
        let components = url.standardizedFileURL.pathComponents
        if let bottlesIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare("Bottles") == .orderedSame
        }), components.indices.contains(bottlesIndex + 1) {
            configuration.bottleName = components[bottlesIndex + 1]
        }
        automaticThermalPreferredProcessID = nil
        automaticThermalPreferredExecutableNeedle = nil
        automaticThermalSessionIDs.removeAll()
        automaticThermalConfiguration = configuration
        automaticThermalStatus = "Ejecutable guardado: \(url.lastPathComponent)"
        automaticThermalReason = configuration.bottleName.isEmpty
            ? "Seleccionado manualmente desde el disco"
            : "Botella detectada: \(configuration.bottleName)"
        addLog("CrossOver: ejecutable manual \(url.lastPathComponent)"
               + (configuration.bottleName.isEmpty ? "." : " en \(configuration.bottleName)."))
    }

    func launchCrossOverWithQoS(_ installation: CrossOverInstallation) {
        let applicationURL = URL(fileURLWithPath: installation.path)
        let normalizedPath = applicationURL.standardizedFileURL.path.lowercased()
        let alreadyRunning = processes.contains { process in
            process.path.lowercased().hasPrefix(normalizedPath + "/contents/")
                && !process.path.lowercased().contains("/sharedsupport/")
        }
        guard !alreadyRunning else {
            updateCrossOverEfficientLaunchStatus("CrossOver ya está abierto; ciérralo antes de aplicar un clamp de lanzamiento")
            addLog("CrossOver: no se aplicó QoS porque la aplicación ya estaba abierta.", isError: true)
            return
        }
        guard crossOverQoSLaunchAvailable else {
            updateCrossOverEfficientLaunchStatus("El clamp QoS de lanzamiento no está disponible en este macOS")
            addLog("CrossOver: libSystem no ofrece el clamp QoS de lanzamiento.", isError: true)
            return
        }

        updateCrossOverEfficientLaunchStatus("Abriendo \(installation.displayName) con QoS \(crossOverLaunchQoSClamp.title)…")
        let controller = controller
        let clamp = crossOverLaunchQoSClamp
        controlQueue.async { [weak self] in
            do {
                let pid = try controller.launchApplication(applicationURL, qosClamp: clamp)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recordCrossOverEfficientLaunch(
                        pid: pid,
                        clamp: clamp,
                        status: "CrossOver abierto con QoS \(clamp.title) · PID \(pid)"
                    )
                    self.addLog("CrossOver: \(installation.displayName) abierto con clamp QoS \(clamp.title), PID \(pid).")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.refreshNow()
                        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.recordCrossOverEfficientLaunchFailure(
                        clamp: clamp,
                        status: error.localizedDescription
                    )
                    self?.addLog("CrossOver: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    func launchCrossOverAfterThermalBridgeIfNeeded() {
        guard !automaticCrossOverLaunchAfterStartupRequested else { return }
        automaticCrossOverLaunchAfterStartupRequested = true
        guard let installation = crossOverInstallations.first else {
            updateCrossOverEfficientLaunchStatus("No se detectó CrossOver para abrirlo con QoS")
            return
        }
        guard crossOverQoSLaunchAvailable else {
            updateCrossOverEfficientLaunchStatus("El clamp QoS de lanzamiento no está disponible en este macOS")
            return
        }

        updateCrossOverEfficientLaunchStatus(
            "ThermalBridge listo; abriendo CrossOver con QoS \(crossOverLaunchQoSClamp.title)…"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.launchCrossOverWithQoS(installation)
        }
    }

    func startAutomaticThermalControl(processID: ProcessIdentity?) {
        disablePreviousAutomaticSystems()
        clearAutomaticThermalRequests()

        guard automaticThermalConfiguration.hasTarget
                || processID != nil
                || automaticThermalPreferredProcessID != nil else {
            automaticThermalStatus = "Selecciona un proceso del árbol CrossOver o guarda el .exe"
            addLog("Modo térmico: falta seleccionar un proceso o un juego.", isError: true)
            return
        }

        // La selección visual nunca debe sobrescribir el .exe guardado. Solo el
        // botón «Usar selección» captura un juego; aquí se acepta el PID elegido
        // únicamente cuando coincide con el objetivo persistido.
        let preferredTargetIsCurrent = automaticThermalPreferredExecutableNeedle
            == automaticThermalConfiguration.normalizedExecutableNeedle
        let selected: ProcessSnapshot?
        if let processID,
           let process = process(for: processID),
           isCrossOverSelectableProcess(process),
           (!automaticThermalConfiguration.hasTarget
                || automaticThermalConfiguration.matchScore(for: process) != nil
                || (preferredTargetIsCurrent
                    && automaticThermalPreferredProcessID == process.identity)) {
            selected = process
        } else if let preferred = preferredAutomaticThermalProcess() {
            selected = preferred
        } else {
            selected = bestAutomaticThermalMatch()
        }

        automaticThermalEnabled = true
        automaticThermalEmergency = false
        automaticMacPolicyLevel = .normal
        automaticMacPolicyStatus = automaticMacPolicyEnabled
            ? "Preparando políticas macOS"
            : "Políticas macOS desactivadas"
        automaticThermalEngine.reset(activityPercent: automaticThermalConfiguration.maximumActivityPercent)
        b1PredictiveThermalGovernor.reset()
        b1ThermalGovernorState = .observation
        b1ThermalControlLevel = 0
        automaticThermalActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticThermalRequestedActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticLimiterPulseMode = automaticAudioProtectionEnabled ? .audioSafe : .burst
        lastAutomaticThermalEvaluation = .distantPast
        lastAutomaticThermalDecisionReadingDate = nil
        automaticThermalMissingSamples = 0
        automaticThermalLastRootSnapshot = nil
        automaticThermalSessionIDs.removeAll()
        resetAutomaticResourceEvidence()
        startAutomaticSessionTelemetry()

        if let selected {
            attachAutomaticThermalControl(to: selected, automatic: false)
        } else {
            automaticThermalProcessID = nil
            automaticThermalStatus = "Armado; esperando \(automaticThermalConfiguration.executableContains)"
            automaticThermalReason = "Esperando que el juego se abra en CrossOver"
        }
    }

    func stopAutomaticThermalControl(keepAutoAttach: Bool = true) {
        clearAutomaticThermalRequests()
        restoreAutomaticMacPolicies()
        restoreDisplayRefreshSafety(reason: "thermal_control_stopped")
        sessionTelemetryWriter.stop(reason: "thermal_control_stopped")
        automaticThermalEnabled = false
        automaticThermalProcessID = nil
        automaticThermalActivityPercent = 100
        automaticThermalRequestedActivityPercent = 100
        automaticLimiterPulseMode = automaticAudioProtectionEnabled ? .audioSafe : .burst
        automaticThermalEmergency = false
        automaticThermalReason = "Inactivo"
        automaticThermalEngine.reset()
        lastAutomaticThermalEvaluation = .distantPast
        lastAutomaticThermalDecisionReadingDate = nil
        automaticThermalMissingSamples = 0
        automaticThermalLastRootSnapshot = nil
        automaticThermalSessionIDs.removeAll()
        resetAutomaticResourceEvidence()
        if !keepAutoAttach {
            automaticThermalConfiguration.autoAttach = false
        }
        automaticMacPolicyLevel = .normal
        automaticMacPolicyStatus = "Políticas macOS restauradas"
        automaticThermalStatus = "Control detenido"
        addLog("Modo térmico automático detenido; controles liberados.")
    }

    func evaluateAutomaticThermalMode(force: Bool = false) {
        guard automaticThermalEnabled else { return }

        if let identity = automaticThermalProcessID,
           let root = process(for: identity) {
            automaticThermalMissingSamples = 0
            automaticThermalLastRootSnapshot = root
            automaticThermalSessionIDs.formUnion(automaticSessionIdentities(around: root))
            evaluateAutomaticTemperatureDecision(root: root, force: force)
            applyAutomaticLauncherControls(root: root)
            return
        }

        // Una asociación confirmada mediante «Usar selección» es evidencia
        // explícita del usuario y no depende de que argv repita el .exe.
        if automaticThermalProcessID == nil,
           let preferred = preferredAutomaticThermalProcess() {
            attachAutomaticThermalControl(to: preferred, automatic: true)
            return
        }

        // Wine puede reemplazar un host, ejecutar un nuevo PID o quedar ausente
        // en una sola enumeración. Buscamos primero un reemplazo y mantenemos el
        // estado armado durante varias muestras antes de liberar controles.
        if automaticThermalProcessID != nil {
            automaticThermalMissingSamples += 1
            if let replacement = bestAutomaticThermalMatch() {
                attachAutomaticThermalControl(to: replacement, automatic: true)
                return
            }
            if automaticThermalMissingSamples <= 5 {
                automaticThermalStatus = "Reconfirmando \(automaticThermalConfiguration.executableContains)…"
                automaticThermalReason = "CrossOver está cambiando el proceso del juego; se conserva el control"
                return
            }
        }

        automaticThermalProcessID = nil
        automaticThermalLastRootSnapshot = nil
        automaticThermalSessionIDs.removeAll()
        clearAutomaticThermalRequests()
        restoreDisplayRefreshSafety(reason: "game_not_running")
        guard automaticThermalConfiguration.autoAttach else {
            automaticThermalEnabled = false
            sessionTelemetryWriter.stop(reason: "game_ended")
            automaticThermalStatus = "El juego terminó"
            automaticThermalReason = "Autoaplicación desactivada"
            return
        }

        guard automaticThermalConfiguration.hasTarget else {
            automaticThermalEnabled = false
            sessionTelemetryWriter.stop(reason: "manual_tree_session_ended")
            automaticThermalStatus = "El proceso seleccionado terminó"
            automaticThermalReason = "La selección por árbol sin .exe no se rearma automáticamente"
            return
        }

        guard let match = bestAutomaticThermalMatch() else {
            automaticThermalStatus = "Armado; esperando \(automaticThermalConfiguration.executableContains)"
            automaticThermalReason = "Esperando evidencia estable del .exe o de su botella"
            return
        }
        attachAutomaticThermalControl(to: match, automatic: true)
    }

    func persistAutomaticThermalConfiguration() {
        guard let data = try? JSONEncoder().encode(automaticThermalConfiguration) else { return }
        UserDefaults.standard.set(data, forKey: "ThermalBridge.automaticThermalConfiguration.v2")
        recordAutomaticSessionConfiguration()
        if automaticThermalEnabled && !suppressAutomaticThermalConfigurationEvaluation {
            // Los cambios de interfaz se aplican con la siguiente muestra del
            // sensor; así mover un slider no acumula varias reducciones sobre
            // una única lectura de temperatura.
            evaluateAutomaticThermalMode(force: false)
        }
    }

    private func migrateAutomaticThermalConfiguration() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "ThermalBridge.automaticThermalConfiguration.v2"),
           var decoded = try? JSONDecoder().decode(AutomaticThermalConfiguration.self, from: data) {
            decoded.clamp()
            automaticThermalConfiguration = decoded
            return
        }

        // La versión 0.6.0 controlaba promedios. Al migrar a máximos por sensor,
        // eleva los objetivos antiguos para evitar una limitación excesiva e
        // informa al usuario mediante los nuevos valores visibles en pantalla.
        if let legacyData = defaults.data(forKey: "ThermalBridge.automaticThermalConfiguration.v1"),
           var legacy = try? JSONDecoder().decode(AutomaticThermalConfiguration.self, from: legacyData) {
            legacy.cpuTargetCelsius += 8
            legacy.gpuTargetCelsius += 7
            legacy.clamp()
            automaticThermalConfiguration = legacy
            persistAutomaticThermalConfiguration()
            return
        }

        // Conserva el juego capturado en versiones anteriores y migra sus ajustes
        // hacia un único controlador por temperatura.
        if let previous = selectedCrossOverProfile ?? crossOverProfiles.first(where: { $0.hasTarget }) {
            automaticThermalConfiguration.executableContains = previous.executableContains
            automaticThermalConfiguration.bottleName = previous.bottleName
            automaticThermalConfiguration.autoAttach = previous.autoAttach
            automaticThermalConfiguration.minimumActivityPercent = previous.gpuMinimumActivityPercent
            automaticThermalConfiguration.optimizeLaunchers = previous.optimizeLaunchers
            automaticThermalConfiguration.launcherActivityPercent = previous.launcherActivityPercent
            automaticThermalConfiguration.launcherBackground = previous.launcherBackground
        }
        persistAutomaticThermalConfiguration()
    }

    private func disablePreviousAutomaticSystems() {
        if activeCrossOverProfileID != nil || crossOverAutoAttachEnabled {
            stopCrossOverProfile(clearAutoAttach: true)
        }
        if gpuGuardEnabled { stopGPUGuard() }
        if thermalAutomationEnabled { thermalAutomationEnabled = false }
        if !rules.isEmpty { rules = [] }
        if !thermalTargets.isEmpty { thermalTargets = [] }
    }

    private func acceptTemperatureReading(_ reading: TemperatureReading) {
        // Los factores determinantes son los máximos instantáneos de cada grupo.
        // El promedio se conserva únicamente para diagnóstico y comparación.
        cpuTemperatureCelsius = plausibleTemperature(reading.cpuControlCelsius)
        gpuTemperatureCelsius = plausibleTemperature(reading.gpuControlCelsius)
        cpuAverageTemperatureCelsius = plausibleTemperature(reading.cpuAverageCelsius)
        gpuAverageTemperatureCelsius = plausibleTemperature(reading.gpuAverageCelsius)
        cpuMaximumSensorName = reading.cpuMaximumSensor
        gpuMaximumSensorName = reading.gpuMaximumSensor
        cpuTemperatureSensorCount = reading.cpuSensorCount
        gpuTemperatureSensorCount = reading.gpuSensorCount
        temperatureReadingSource = reading.source
        sensorCPUPowerWatts = reading.cpuPowerWatts
        sensorGPUPowerWatts = reading.gpuPowerWatts
        lastTemperatureReadingDate = reading.date
        if automaticThermalEnabled {
            evaluateAutomaticThermalMode()
        }
    }

    private func plausibleTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 130 else { return nil }
        return value
    }

    private func attachAutomaticThermalControl(to root: ProcessSnapshot, automatic: Bool) {
        guard isCrossOverSelectableProcess(root) else { return }
        repairAutomaticThermalBottleIfNeeded(from: root)
        clearAutomaticThermalRequests()
        automaticThermalProcessID = root.identity
        automaticThermalMissingSamples = 0
        automaticThermalLastRootSnapshot = root
        automaticThermalSessionIDs.formUnion(automaticSessionIdentities(around: root))
        selectForHistory(root)
        automaticThermalEngine.reset(activityPercent: automaticThermalConfiguration.maximumActivityPercent)
        b1PredictiveThermalGovernor.reset()
        b1ThermalGovernorState = .observation
        b1ThermalControlLevel = 0
        automaticThermalActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticThermalRequestedActivityPercent = automaticThermalConfiguration.maximumActivityPercent
        automaticLimiterPulseMode = automaticAudioProtectionEnabled ? .audioSafe : .burst
        lastAutomaticThermalEvaluation = .distantPast
        lastAutomaticThermalDecisionReadingDate = nil
        let targetName = automaticThermalConfiguration.hasTarget
            ? automaticThermalConfiguration.executableContains
            : root.displayName
        automaticThermalStatus = "Controlando \(targetName) mediante \(root.displayName)\(automatic ? " automáticamente" : "")"
        automaticThermalReason = "Esperando la primera decisión térmica"
        addLog("Modo térmico: control aplicado a \(root.displayName)\(automatic ? " automáticamente" : "").")
        evaluateAutomaticTemperatureDecision(root: root, force: true)
        applyAutomaticLauncherControls(root: root)
    }

    private func repairAutomaticThermalBottleIfNeeded(from process: ProcessSnapshot) {
        let target = automaticThermalConfiguration.executableContains
        guard let evidence = process.windowsExecutableEvidenceScore(named: target),
              evidence >= 1_100,
              let detectedBottle = process.crossOverBottleName,
              !detectedBottle.isEmpty else { return }

        let storedBottle = automaticThermalConfiguration.bottleName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard storedBottle.caseInsensitiveCompare(detectedBottle) != .orderedSame else { return }

        var configuration = automaticThermalConfiguration
        configuration.bottleName = detectedBottle
        suppressAutomaticThermalConfigurationEvaluation = true
        automaticThermalConfiguration = configuration
        suppressAutomaticThermalConfigurationEvaluation = false
        addLog(storedBottle.isEmpty
               ? "CrossOver: botella detectada automáticamente: \(detectedBottle)."
               : "CrossOver: se corrigió la botella guardada de \(storedBottle) a \(detectedBottle) usando evidencia exacta de \(target).")
    }

    private func currentThermalSignalSnapshot(now: Date) -> ThermalSignalSnapshot {
        let age = lastTemperatureReadingDate.map { now.timeIntervalSince($0) }
        let quality: B1ThermalSensorQuality
        if let age {
            switch age {
            case ...2: quality = .fresh
            case ...5: quality = .hold
            case ...10: quality = .stale
            default: quality = .lost
            }
        } else {
            quality = .lost
        }
        return ThermalSignalSnapshot(date: now,
                                     cpuTemperature: cpuTemperatureCelsius,
                                     gpuTemperature: gpuTemperatureCelsius,
                                     thermalState: thermalLabel,
                                     sampleAgeSeconds: age,
                                     source: temperatureReadingSource,
                                     quality: quality,
                                     cpuSensorCount: cpuTemperatureSensorCount,
                                     gpuSensorCount: gpuTemperatureSensorCount,
                                     cpuMaximumSensor: cpuMaximumSensorName,
                                     gpuMaximumSensor: gpuMaximumSensorName,
                                     lastError: temperatureSensorState.description)
    }

    private func evaluateAutomaticTemperatureDecision(root: ProcessSnapshot, force: Bool) {
        let now = Date()
        if !force {
            if temperatureReadingFresh, let readingDate = lastTemperatureReadingDate {
                guard lastAutomaticThermalDecisionReadingDate != readingDate else { return }
                lastAutomaticThermalDecisionReadingDate = readingDate
            } else {
                guard now.timeIntervalSince(lastAutomaticThermalEvaluation) >= 2.0 else { return }
            }
        } else {
            lastAutomaticThermalDecisionReadingDate = lastTemperatureReadingDate
        }
        lastAutomaticThermalEvaluation = now

        let input = ThermalControlInput(
            date: now,
            cpuTemperature: cpuTemperatureCelsius,
            gpuTemperature: gpuTemperatureCelsius,
            cpuPowerWatts: sensorCPUPowerWatts,
            gpuPowerWatts: sensorGPUPowerWatts,
            powerAnticipationEnabled: automaticPowerAnticipationEnabled,
            sensorFresh: temperatureReadingFresh,
            systemThermalState: thermalLabel
        )
        let decision = automaticThermalEngine.update(input: input,
                                                     configuration: automaticThermalConfiguration,
                                                     force: force)
        let signal = currentThermalSignalSnapshot(now: now)
        let b1Decision = b1PredictiveThermalGovernor.update(
            signal: signal,
            targetCPU: automaticThermalConfiguration.cpuTargetCelsius,
            targetGPU: automaticThermalConfiguration.gpuTargetCelsius,
            force: force
        )
        b1ThermalGovernorState = b1Decision.state
        b1ThermalControlLevel = b1Decision.appliedControlLevel
        let pulseMode: ActivityLimiterPulseMode = .burst
        let emergencyLimiterPercent = b1Decision.emergency
            ? min(decision.activityPercent, b1Decision.activityPercentShadow, 25)
            : nil
        automaticThermalRequestedActivityPercent = b1Decision.activityPercentShadow
        automaticThermalActivityPercent = emergencyLimiterPercent ?? 100
        automaticLimiterPulseMode = pulseMode
        automaticThermalReason = b1Decision.reason
        if b1Decision.emergency {
            automaticThermalReason += " · emergencia: limitador genérico habilitado"
        } else {
            automaticThermalReason += " · modo sombra: sin SIGSTOP/SIGCONT fuera de emergencia"
        }
        automaticThermalEmergency = b1Decision.emergency
        cpuTemperatureSmoothedCelsius = b1Decision.cpuFiltered ?? decision.cpuSmoothed
        gpuTemperatureSmoothedCelsius = b1Decision.gpuFiltered ?? decision.gpuSmoothed

        updateCPULimitRequest(root,
                              sourceKey: automaticThermalSourceKey,
                              percent: emergencyLimiterPercent,
                              pulseMode: pulseMode)
        let resourceEvidence = refreshAutomaticResourceEvidence(for: root)
        sessionTelemetryWriter.recordDecision(
            cpuTemperatureCelsius: cpuTemperatureCelsius,
            gpuTemperatureCelsius: gpuTemperatureCelsius,
            cpuPowerWatts: sensorCPUPowerWatts,
            gpuPowerWatts: sensorGPUPowerWatts,
            sensorFresh: temperatureReadingFresh,
            sensorSource: temperatureReadingSource,
            thermalState: thermalLabel.rawValue,
            requestedActivityPercent: b1Decision.activityPercentShadow,
            appliedActivityPercent: cpuLimitByID[root.identity] ?? 100,
            pulseMode: b1Decision.emergency ? "burst" : "none",
            emergency: b1Decision.emergency,
            reason: b1Decision.reason,
            resourceMetrics: resourceEvidence.0,
            qosEvidence: resourceEvidence.1,
            b1Decision: b1Decision,
            signal: signal,
            ephemeralProcessStartID: automaticSelectHighestCPUExecutableEnabled ? root.identity.startID : nil
        )
        applyAutomaticMacPolicy(root: root)
        let cpuError = cpuTemperatureCelsius.map {
            $0 - Double(automaticThermalConfiguration.cpuTargetCelsius)
        }
        let gpuError = gpuTemperatureCelsius.map {
            $0 - Double(automaticThermalConfiguration.gpuTargetCelsius)
        }
        let severeSensorExcess = [cpuError, gpuError].compactMap { $0 }.max().map { $0 >= 7 } ?? false
        applyAutomaticEmergencyBackground(
            root: root,
            enabled: automaticEmergencyBackgroundEnabled
                && (b1Decision.emergency || severeSensorExcess)
        )
        reconcileDisplayRefreshIntegration()

        let cpu = cpuTemperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—"
        let gpu = gpuTemperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—"
        let targetLabel = automaticThermalConfiguration.executableContains.isEmpty ? root.displayName : automaticThermalConfiguration.executableContains
        let limiterLabel = b1Decision.emergency ? " · \(pulseMode.title)" : " · B1 sombra"
        automaticThermalStatus = "\(targetLabel) · host \(root.displayName) · CPU máx. \(cpu) · GPU máx. \(gpu) · control B1 \(Int((b1Decision.appliedControlLevel * 100).rounded()))%\(limiterLabel)"
    }

    private func automaticSessionTelemetryConfiguration() -> SessionTelemetryEvent.Configuration {
        SessionTelemetryEvent.Configuration(
            cpuTargetCelsius: automaticThermalConfiguration.cpuTargetCelsius,
            gpuTargetCelsius: automaticThermalConfiguration.gpuTargetCelsius,
            hysteresisCelsius: automaticThermalConfiguration.hysteresisCelsius,
            minimumActivityPercent: automaticThermalConfiguration.minimumActivityPercent,
            maximumActivityPercent: automaticThermalConfiguration.maximumActivityPercent,
            aggressiveness: automaticThermalConfiguration.aggressiveness.rawValue,
            powerAnticipationEnabled: automaticPowerAnticipationEnabled,
            audioProtectionEnabled: automaticAudioProtectionEnabled,
            requestedQoSClamp: lastCrossOverRequestedQoSClamp?.title
        )
    }

    private func startAutomaticSessionTelemetry() {
        let file = sessionTelemetryWriter.start(
            configuration: automaticSessionTelemetryConfiguration()
        )
        updateLastSessionTelemetryURL(file)
        if let file {
            addLog("Telemetría de sesión iniciada: \(file.lastPathComponent).")
        } else {
            addLog("No se pudo iniciar la telemetría JSONL; el control térmico continúa sin cambios.", isError: true)
        }
    }

    private func recordAutomaticSessionConfiguration() {
        guard automaticThermalEnabled else { return }
        sessionTelemetryWriter.recordConfiguration(
            automaticSessionTelemetryConfiguration()
        )
    }

    private func applyAutomaticMacPolicy(root: ProcessSnapshot) {
        guard automaticMacPolicyEnabled else {
            restoreAutomaticMacPolicies()
            automaticMacPolicyStatus = "Políticas macOS desactivadas"
            return
        }
        guard automaticMacPolicyRuntimeAvailable else {
            automaticMacPolicyStatus = "No disponible; el control de actividad continúa funcionando"
            return
        }

        let plan = MacApplicationPolicyPlanner.plan(
            cpuTemperature: cpuTemperatureCelsius,
            gpuTemperature: gpuTemperatureCelsius,
            cpuTarget: automaticThermalConfiguration.cpuTargetCelsius,
            gpuTarget: automaticThermalConfiguration.gpuTargetCelsius,
            hysteresis: automaticThermalConfiguration.hysteresisCelsius,
            sensorFresh: temperatureReadingFresh,
            thermalState: thermalLabel,
            currentLevel: automaticMacPolicyLevel
        )

        let previousIDs = automaticMacPolicyAppliedIDs
        let treeTargets = processTree(for: root).filter { !isProtected($0) }
        let desiredIDs = plan.level == .normal ? Set<ProcessIdentity>() : Set(treeTargets.map(\.identity))
        let targets = plan.level == .normal
            ? processes.filter { previousIDs.contains($0.identity) }
            : treeTargets
        let staleTargets = plan.level == .normal
            ? []
            : processes.filter { previousIDs.contains($0.identity) && !desiredIDs.contains($0.identity) }

        if plan.level == .normal && previousIDs.isEmpty {
            automaticMacPolicyLevel = .normal
            automaticMacPolicyStatus = plan.reason
            return
        }

        let requiresUpdate = plan.level != automaticMacPolicyLevel
            || desiredIDs != previousIDs
        automaticMacPolicyLevel = plan.level
        automaticMacPolicyStatus = plan.level == .normal
            ? plan.reason
            : "\(plan.reason) · throughput \(plan.throughputTier) / latencia \(plan.latencyTier)"
        guard requiresUpdate else { return }

        automaticMacPolicyGeneration += 1
        let generation = automaticMacPolicyGeneration
        let controller = controller
        // Se registran de forma pesimista antes del trabajo asíncrono. Así una
        // detención inmediata conoce todos los PID que podrían recibir tiers y
        // la restauración síncrona, encolada después, no deja una carrera.
        automaticMacPolicyAppliedIDs.formUnion(previousIDs)
        automaticMacPolicyAppliedIDs.formUnion(desiredIDs)
        for process in targets + staleTargets {
            automaticMacPolicySnapshots[process.identity] = process
        }
        controlQueue.async { [weak self] in
            var staleRestoreFailures = Set<ProcessIdentity>()
            var targetFailures = Set<ProcessIdentity>()
            var targetSuccesses = Set<ProcessIdentity>()
            var failureMessages: [String] = []

            for process in staleTargets {
                do {
                    try controller.setSchedulingPolicy(process,
                                                       throughputTier: -1,
                                                       latencyTier: -1)
                } catch {
                    staleRestoreFailures.insert(process.identity)
                    failureMessages.append("restaurar \(process.displayName): \(error.localizedDescription)")
                }
            }

            for process in targets {
                do {
                    try controller.setSchedulingPolicy(
                        process,
                        throughputTier: plan.throughputTier,
                        latencyTier: plan.latencyTier
                    )
                    targetSuccesses.insert(process.identity)
                } catch {
                    targetFailures.insert(process.identity)
                    failureMessages.append("\(process.displayName): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                guard let self,
                      self.automaticMacPolicyGeneration == generation else { return }

                var stillApplied = staleRestoreFailures
                if plan.level == .normal {
                    // Los procesos que no pudieron restaurarse continúan bajo la
                    // política anterior y deben permanecer rastreados.
                    stillApplied.formUnion(targetFailures)
                } else {
                    stillApplied.formUnion(targetSuccesses)
                    // Si un cambio de tier falló sobre un proceso previamente
                    // controlado, su política anterior puede seguir activa.
                    stillApplied.formUnion(targetFailures.intersection(previousIDs))
                }
                self.automaticMacPolicyAppliedIDs = stillApplied
                self.automaticMacPolicySnapshots = self.automaticMacPolicySnapshots.filter {
                    stillApplied.contains($0.key)
                }

                if plan.level != .normal,
                   !targets.isEmpty,
                   targetSuccesses.isEmpty {
                    self.automaticMacPolicyRuntimeAvailable = false
                    self.automaticMacPolicyLevel = .normal
                    self.automaticMacPolicyStatus = "No disponible en este macOS; se conserva el control de actividad"
                    self.addLog("Políticas macOS beta no disponibles: \(failureMessages.joined(separator: "; " )). El limitador térmico continúa activo.", isError: true)
                } else if failureMessages.isEmpty {
                    self.automaticMacPolicyStatus = plan.level == .normal
                        ? "Políticas macOS restauradas"
                        : "\(plan.level.title) aplicada a \(targets.count) procesos"
                    self.addLog(plan.level == .normal
                                ? "Políticas macOS restauradas."
                                : "Política macOS \(plan.level.title) aplicada a \(targets.count) procesos del árbol.")
                } else {
                    self.automaticMacPolicyStatus = plan.level == .normal
                        ? "Restauración parcial: \(targetFailures.count) procesos"
                        : "Aplicación parcial: \(targetSuccesses.count)/\(targets.count) procesos"
                    self.addLog("Política macOS parcial: \(failureMessages.joined(separator: "; "))", isError: true)
                }
            }
        }
    }

    func restoreAutomaticMacPolicies() {
        guard !automaticMacPolicyAppliedIDs.isEmpty
                || automaticMacPolicyLevel != .normal else {
            automaticMacPolicyLevel = .normal
            return
        }
        let identities = automaticMacPolicyAppliedIDs
        let currentByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity, $0) })
        let targets = identities.compactMap {
            currentByID[$0] ?? automaticMacPolicySnapshots[$0]
        }
        automaticMacPolicyLevel = .normal
        automaticMacPolicyGeneration += 1
        let controller = controller
        var failedIDs = Set<ProcessIdentity>()
        // FIFO con cualquier aplicación pendiente y espera hasta que el kernel
        // haya aceptado la retirada. Es idempotente: solo conserva fallos para
        // permitir un reintento posterior.
        controlQueue.sync {
            for process in targets {
                guard controller.identityStillMatches(process) else { continue }
                do {
                    try controller.setSchedulingPolicy(process,
                                                       throughputTier: -1,
                                                       latencyTier: -1)
                } catch {
                    failedIDs.insert(process.identity)
                }
            }
        }
        automaticMacPolicyAppliedIDs = failedIDs
        automaticMacPolicySnapshots = automaticMacPolicySnapshots.filter {
            failedIDs.contains($0.key)
        }
        automaticMacPolicyStatus = failedIDs.isEmpty
            ? "Políticas macOS restauradas"
            : "Restauración parcial: \(failedIDs.count) procesos no respondieron"
        sessionTelemetryWriter.recordSafetyEvent(
            operation: "policy_restore",
            status: failedIDs.isEmpty ? "restored" : "partial",
            reason: failedIDs.isEmpty
                ? "Todos los overrides rastreados fueron retirados"
                : "No se pudieron retirar \(failedIDs.count) overrides rastreados"
        )
    }

    func displayRefreshConfigurationChanged() {
        displayRefreshFailureLatched = false
        if !automaticGPURefreshReductionEnabled {
            restoreDisplayRefreshIntegration(reason: "configuration_disabled")
        } else if !automaticThermalEnabled {
            updateAutomaticDisplayRefreshStatus("Armado; máximo 60 Hz cuando domine la temperatura GPU")
        }
        if automaticThermalEnabled {
            evaluateAutomaticThermalMode(force: true)
        }
    }

    private func reconcileDisplayRefreshIntegration() {
        if displayRefreshController.isReduced,
           !displayRefreshController.guardianActive {
            restoreDisplayRefreshIntegration(reason: "display_guardian_missing")
            return
        }
        let action = DisplayRefreshPlanner.action(
            enabled: automaticGPURefreshReductionEnabled,
            sensorFresh: temperatureReadingFresh,
            cpuTemperature: cpuTemperatureCelsius,
            gpuTemperature: gpuTemperatureCelsius,
            cpuTarget: automaticThermalConfiguration.cpuTargetCelsius,
            gpuTarget: automaticThermalConfiguration.gpuTargetCelsius,
            hysteresis: automaticThermalConfiguration.hysteresisCelsius,
            currentlyReduced: displayRefreshController.isReduced
        )
        switch action {
        case .hold:
            if !displayRefreshController.isReduced {
                displayRefreshFailureLatched = false
                if automaticGPURefreshReductionEnabled {
                    updateAutomaticDisplayRefreshStatus("En espera; GPU aún no domina el exceso térmico")
                }
            }
        case .reduce:
            guard !displayRefreshFailureLatched else { return }
            do {
                let result = try displayRefreshController.reduceMainDisplay(
                    maximumRefreshRate: 60
                )
                switch result {
                case let .applied(refreshRate):
                    updateAutomaticDisplayRefreshStatus(
                        String(format: "Aplicado: %.0f Hz · guardián de restauración activo", refreshRate)
                    )
                    sessionTelemetryWriter.recordSafetyEvent(
                        operation: "display_refresh",
                        status: "applied",
                        reason: "GPU dominante; refresco reducido con guardián independiente"
                    )
                case let .unchanged(refreshRate):
                    displayRefreshFailureLatched = true
                    updateAutomaticDisplayRefreshStatus(
                        String(format: "Sin cambio: la pantalla ya opera a %.0f Hz o menos", refreshRate)
                    )
                    sessionTelemetryWriter.recordSafetyEvent(
                        operation: "display_refresh",
                        status: "unchanged",
                        reason: "La pantalla ya estaba en el límite solicitado o por debajo"
                    )
                }
            } catch {
                displayRefreshFailureLatched = true
                updateAutomaticDisplayRefreshStatus("No disponible: \(error.localizedDescription)")
                sessionTelemetryWriter.recordSafetyEvent(
                    operation: "display_refresh",
                    status: "unavailable",
                    reason: "No se encontró un modo compatible, falló el guardián o CoreGraphics rechazó el cambio"
                )
            }
        case .restore:
            restoreDisplayRefreshIntegration(reason: "gpu_recovered")
        }
    }

    func restoreDisplayRefreshSafety(reason: String) {
        restoreDisplayRefreshIntegration(reason: reason)
    }

    private func restoreDisplayRefreshIntegration(reason: String) {
        guard displayRefreshController.isReduced else {
            displayRefreshFailureLatched = false
            updateAutomaticDisplayRefreshStatus(
                automaticGPURefreshReductionEnabled ? "En espera" : "Desactivado"
            )
            return
        }
        do {
            let rate = try displayRefreshController.restore()
            displayRefreshFailureLatched = false
            updateAutomaticDisplayRefreshStatus(
                rate.map { String(format: "Modo original restaurado (%.0f Hz)", $0) }
                    ?? "Modo original restaurado"
            )
            sessionTelemetryWriter.recordSafetyEvent(
                operation: "display_refresh",
                status: "restored",
                reason: reason
            )
        } catch {
            updateAutomaticDisplayRefreshStatus("Restauración pendiente: \(error.localizedDescription)")
            sessionTelemetryWriter.recordSafetyEvent(
                operation: "display_refresh",
                status: "restore_failed",
                reason: reason
            )
        }
    }

    private func preferredAutomaticThermalProcess() -> ProcessSnapshot? {
        guard let identity = automaticThermalPreferredProcessID,
              let process = process(for: identity),
              isCrossOverSelectableProcess(process) else { return nil }
        guard automaticThermalConfiguration.hasTarget else { return process }
        guard automaticThermalPreferredExecutableNeedle
                == automaticThermalConfiguration.normalizedExecutableNeedle else { return nil }
        return process
    }

    private func bestAutomaticThermalMatch() -> ProcessSnapshot? {
        let matchCandidates = automaticCrossOverMatchCandidates
        let exact = matchCandidates
            .compactMap { process -> (ProcessSnapshot, Int)? in
                guard let score = automaticThermalConfiguration.matchScore(for: process) else { return nil }
                let roleBonus = isCrossOverGameCandidate(process) ? 200 : 0
                return (process, score + roleBonus)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.cpuPercent != rhs.0.cpuPercent { return lhs.0.cpuPercent > rhs.0.cpuPercent }
                if lhs.0.memoryBytes != rhs.0.memoryBytes { return lhs.0.memoryBytes > rhs.0.memoryBytes }
                return stableOrder(for: lhs.0) < stableOrder(for: rhs.0)
            }
            .first?.0
        if let exact { return exact }

        // Beta 4 podía guardar una botella equivocada cuando un helper aparecía
        // durante una selección automática. Si no existe coincidencia estricta,
        // recupera únicamente una evidencia exacta y fuerte del .exe. Se acepta
        // cuando todos los candidatos resueltos pertenecen a una sola botella,
        // evitando elegir entre dos sesiones realmente ambiguas.
        let strongExecutableMatches = CrossOverExecutableResolver.strongMatches(
            target: automaticThermalConfiguration.executableContains,
            among: matchCandidates.filter {
                !isCrossOverInfrastructure($0)
                    && !isCrossOverLauncher($0)
                    && !isCrossOverHelper($0)
            }
        )
        if CrossOverExecutableResolver.isUnambiguousRecoverySet(strongExecutableMatches) {
            return strongExecutableMatches.sorted { lhs, rhs in
                let leftEvidence = lhs.windowsExecutableEvidenceScore(
                    named: automaticThermalConfiguration.executableContains
                ) ?? 0
                let rightEvidence = rhs.windowsExecutableEvidenceScore(
                    named: automaticThermalConfiguration.executableContains
                ) ?? 0
                if leftEvidence != rightEvidence { return leftEvidence > rightEvidence }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return stableOrder(for: lhs) < stableOrder(for: rhs)
            }.first
        }

        let sessionCandidates = matchCandidates
            .filter { process in
                automaticThermalSessionIDs.contains(process.identity)
                    && !isCrossOverInfrastructure(process)
                    && !isCrossOverLauncher(process)
                    && !isCrossOverHelper(process)
            }
            .sorted { lhs, rhs in
                let leftRuntime = automaticRuntimeHostRank(lhs)
                let rightRuntime = automaticRuntimeHostRank(rhs)
                if leftRuntime != rightRuntime { return leftRuntime < rightRuntime }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return stableOrder(for: lhs) < stableOrder(for: rhs)
            }
        if let session = sessionCandidates.first { return session }

        // Cuando argv del juego está oculto, el host de Wine puede seguir siendo
        // identificable por WINEPREFIX/CX_BOTTLE. Ya no exigimos que exista un
        // único host: escogemos de forma determinista el preloader con mayor
        // actividad dentro de la botella y evitamos launchers/ayudantes.
        let configuredBottle = automaticThermalConfiguration.bottleName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredBottle.isEmpty else { return nil }

        let unresolved = matchCandidates
            .filter { process in
                guard process.windowsExecutableEvidenceScore(
                    named: automaticThermalConfiguration.executableContains
                ) == nil,
                !isCrossOverInfrastructure(process),
                !isCrossOverLauncher(process),
                !isCrossOverHelper(process),
                let detectedBottle = process.crossOverBottleName else { return false }
                return detectedBottle.caseInsensitiveCompare(configuredBottle) == .orderedSame
            }
            .sorted { lhs, rhs in
                let leftRuntime = automaticRuntimeHostRank(lhs)
                let rightRuntime = automaticRuntimeHostRank(rhs)
                if leftRuntime != rightRuntime { return leftRuntime < rightRuntime }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return stableOrder(for: lhs) < stableOrder(for: rhs)
            }
        return unresolved.first
    }

    private func automaticSessionIdentities(around root: ProcessSnapshot) -> Set<ProcessIdentity> {
        var identities = Set(processTree(for: root).map(\.identity))
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var parentPID = root.parentPID
        var visited = Set<Int32>()
        var depth = 0
        while parentPID > 0, visited.insert(parentPID).inserted, depth < 32 {
            guard let parent = byPID[parentPID] else { break }
            identities.insert(parent.identity)
            parentPID = parent.parentPID
            depth += 1
        }
        if let bottle = root.crossOverBottleName {
            identities.formUnion(processes.compactMap { process in
                guard process.crossOverBottleName?.caseInsensitiveCompare(bottle) == .orderedSame else {
                    return nil
                }
                return process.identity
            })
        }
        return identities
    }

    private func automaticRuntimeHostRank(_ process: ProcessSnapshot) -> Int {
        let rawName = process.name.lowercased()
        if rawName == "wine64-preloader" || rawName == "wine-preloader" { return 0 }
        if rawName == "wine64" || rawName == "wine" { return 1 }
        if !isCrossOverInfrastructure(process) { return 2 }
        if rawName == "cxstart" { return 3 }
        if rawName.contains("wineserver") { return 5 }
        return 4
    }

    private func applyAutomaticEmergencyBackground(root: ProcessSnapshot,
                                                     enabled: Bool) {
        let desiredIDs = enabled
            ? Set(processTree(for: root).filter { !isProtected($0) }.map(\.identity))
            : Set<ProcessIdentity>()
        for process in processes where !isProtected(process) {
            updateBackgroundRequest(
                process,
                sourceKey: automaticThermalEmergencyBackgroundSourceKey,
                enabled: desiredIDs.contains(process.identity)
            )
        }
    }

    private func applyAutomaticLauncherControls(root: ProcessSnapshot) {
        let gameTreeIDs = Set(processTree(for: root).map(\.identity))
        let candidates = processes.filter { process in
            automaticThermalConfiguration.optimizeLaunchers
                && !isProtected(process)
                && !gameTreeIDs.contains(process.identity)
                && !automaticIsAncestor(process, of: root)
                && isCrossOverLauncher(process)
        }
        let candidatePIDs = Set(candidates.map(\.pid))
        let rootIDs = Set(candidates
            .filter { !candidatePIDs.contains($0.parentPID) }
            .map(\.identity))

        for process in processes where !isProtected(process) && process.identity != root.identity {
            let shouldControl = rootIDs.contains(process.identity)
            updateCPULimitRequest(process,
                                  sourceKey: automaticThermalLauncherSourceKey,
                                  percent: shouldControl
                                    && automaticThermalConfiguration.launcherActivityPercent < 100
                                    ? automaticThermalConfiguration.launcherActivityPercent
                                    : nil)
            updateBackgroundRequest(process,
                                    sourceKey: automaticThermalLauncherSourceKey,
                                    enabled: shouldControl
                                        && automaticThermalConfiguration.launcherBackground)
        }
    }

    private func automaticIsAncestor(_ candidate: ProcessSnapshot, of descendant: ProcessSnapshot) -> Bool {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var parentPID = descendant.parentPID
        var visited = Set<Int32>()
        while parentPID > 0, visited.insert(parentPID).inserted {
            if parentPID == candidate.pid { return true }
            guard let parent = byPID[parentPID] else { return false }
            parentPID = parent.parentPID
        }
        return false
    }

    private func clearAutomaticThermalRequests() {
        restoreAutomaticMacPolicies()
        for process in processes {
            updateCPULimitRequest(process, sourceKey: automaticThermalSourceKey, percent: nil)
            updateCPULimitRequest(process, sourceKey: automaticThermalLauncherSourceKey, percent: nil)
            updateBackgroundRequest(process, sourceKey: automaticThermalLauncherSourceKey, enabled: false)
            updateBackgroundRequest(process,
                                    sourceKey: automaticThermalEmergencyBackgroundSourceKey,
                                    enabled: false)
        }
    }

    private func temperatureText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f °C", value)
    }
}
