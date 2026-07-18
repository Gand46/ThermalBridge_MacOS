import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutomaticThermalView: View {
    @ObservedObject var store: ProcessStore
    @State private var selectedProcessID: ProcessIdentity?
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sensorSection
                gameSection
                targetSection
                controlSection
                explanation
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 700)
        .onAppear {
            selectBestCandidateIfNeeded()
            store.restartTemperatureSensor()
        }
        .onChange(of: store.automaticThermalGameCandidates.map(\.identity)) { _, _ in
            selectBestCandidateIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(store.automaticThermalEmergency ? Color.red : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("ThermalBridge Auto")
                    .font(.title2.bold())
                Text("Control térmico en tiempo real para juegos de CrossOver")
                    .foregroundColor(Color.secondary)
            }
            Spacer()
            if store.automaticThermalEnabled {
                Label("Activo", systemImage: "checkmark.circle.fill")
                    .foregroundColor(Color.green)
            } else {
                Label("Detenido", systemImage: "pause.circle")
                    .foregroundColor(Color.secondary)
            }
        }
    }

    private var sensorSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TemperatureCard(title: "CPU máxima",
                                    value: store.cpuTemperatureText,
                                    target: store.automaticThermalConfiguration.cpuTargetCelsius,
                                    temperature: store.cpuTemperatureCelsius,
                                    fresh: store.temperatureReadingFresh)
                    TemperatureCard(title: "GPU máxima",
                                    value: store.gpuTemperatureText,
                                    target: store.automaticThermalConfiguration.gpuTargetCelsius,
                                    temperature: store.gpuTemperatureCelsius,
                                    fresh: store.temperatureReadingFresh)
                    StatusCard(title: "Actividad permitida",
                               value: store.automaticThermalActivityText,
                               symbol: "speedometer",
                               emphasized: store.automaticThermalActivityPercent < 100)
                }

                HStack(spacing: 8) {
                    Image(systemName: store.temperatureReadingFresh
                          ? "sensor.tag.radiowaves.forward.fill"
                          : "sensor.tag.radiowaves.forward")
                        .foregroundColor(store.temperatureReadingFresh ? Color.green : Color.orange)
                    Text(store.automaticThermalSensorDetail)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    Spacer()
                    if let watts = store.sensorCPUPowerWatts {
                        Text(String(format: "CPU %.2f W", watts))
                            .font(.caption.monospacedDigit())
                    }
                    if let watts = store.sensorGPUPowerWatts {
                        Text(String(format: "GPU %.2f W", watts))
                            .font(.caption.monospacedDigit())
                    }
                    Button("Reintentar sensor") {
                        store.restartTemperatureSensor()
                    }
                    .controlSize(.small)
                }

                if store.temperatureReadingFresh {
                    HStack(spacing: 12) {
                        Text("Promedio CPU: \(store.cpuAverageTemperatureText)")
                        Text("Promedio GPU: \(store.gpuAverageTemperatureText)")
                        Spacer()
                        Text(store.usingMaximumTemperatureSensor
                             ? "Control: sensor individual más caliente"
                             : "Control de respaldo: promedio macmon")
                            .foregroundColor(store.usingMaximumTemperatureSensor ? Color.green : Color.orange)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color.secondary)
                }

                if !store.usingMaximumTemperatureSensor {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color.orange)
                        Text(store.temperatureSensorAvailable
                             ? "El helper de máximos no está entregando datos. Se usa temporalmente el promedio de macmon, que puede ocultar un núcleo o bloque GPU más caliente. Reinstala esta versión si el aviso persiste."
                             : "No hay una lectura térmica válida. ThermalBridge aplica un límite preventivo y usa el estado térmico general de macOS.")
                            .font(.caption)
                        Spacer()
                        Button("Reintentar") {
                            store.restartTemperatureSensor()
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
                }
            }
            .padding(6)
        } label: {
            Label("Temperatura real", systemImage: "waveform.path.ecg.rectangle")
                .font(.headline)
        }
    }

    private var gameSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if store.automaticThermalGameCandidates.isEmpty {
                        Label("Abre el juego dentro de CrossOver y pulsa Actualizar.",
                              systemImage: "gamecontroller")
                            .foregroundColor(Color.secondary)
                    } else {
                        Picker("Proceso", selection: $selectedProcessID) {
                            Text("Seleccionar…").tag(Optional<ProcessIdentity>.none)
                            ForEach(Array(store.automaticThermalGameCandidates), id: \.identity) { (process: ProcessSnapshot) in
                                Text(gameTitle(process)).tag(Optional(process.identity))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Spacer()
                    Button {
                        store.refreshNow()
                    } label: {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }

                HStack(spacing: 10) {
                    TextField("Ejecutable del juego, por ejemplo PRAGMATA.exe",
                              text: executableBinding)
                        .textFieldStyle(.roundedBorder)

                    Button("Usar selección") {
                        guard let selectedProcessID,
                              let process = store.process(for: selectedProcessID) else { return }
                        store.captureAutomaticThermalGame(process)
                    }
                    .disabled(selectedProcessID == nil)

                    Button("Buscar .exe…") {
                        chooseExecutableFile()
                    }
                }

                Text("Elegir un proceso no modifica el ejecutable guardado. «Usar selección» confirma el .exe si existe o vincula explícitamente el proceso del árbol para esta sesión.")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)

                if let selectedProcessID,
                   let selected = store.process(for: selectedProcessID),
                   selected.windowsExecutableName == nil {
                    Label("CrossOver no publicó el .exe de este PID. Puedes escribirlo o usar Buscar .exe… para armar la autoaplicación; si pulsas Usar selección sin .exe, se controlará este proceso del árbol solo en la sesión actual.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(Color.orange)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.automaticThermalConfiguration.hasTarget
                             ? "Guardado: \(store.automaticThermalConfiguration.executableContains)"
                             : "Todavía no hay un ejecutable .exe guardado")
                        if !store.automaticThermalConfiguration.bottleName.isEmpty {
                            HStack(spacing: 6) {
                                Text("Botella: \(store.automaticThermalConfiguration.bottleName)")
                                Button("Olvidar botella") {
                                    store.automaticThermalConfiguration.bottleName = ""
                                }
                                .buttonStyle(.link)
                                .controlSize(.small)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    Spacer()
                    Text("\(store.automaticThermalResolvedCandidateCount) .exe detectados · \(store.automaticThermalGameCandidates.count) procesos del árbol seleccionables")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Color.secondary)
                    Toggle("Aplicar al volver a abrir",
                           isOn: $store.automaticThermalConfiguration.autoAttach)
                        .toggleStyle(.switch)
                }
            }
            .padding(6)
        } label: {
            Label("Juego de CrossOver", systemImage: "gamecontroller.fill")
                .font(.headline)
        }
    }

    private var targetSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                TargetSlider(title: "Límite CPU máxima",
                             value: intBinding(\.cpuTargetCelsius),
                             range: 60...105,
                             accent: .orange)
                TargetSlider(title: "Límite GPU máxima",
                             value: intBinding(\.gpuTargetCelsius),
                             range: 55...105,
                             accent: .purple)

                Picker("Respuesta", selection: $store.automaticThermalConfiguration.aggressiveness) {
                    ForEach(ThermalControlAggressiveness.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.automaticThermalConfiguration.aggressiveness.explanation)
                    .font(.caption)
                    .foregroundColor(Color.secondary)

                DisclosureGroup("Ajustes avanzados", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        TargetSlider(title: "Actividad mínima del juego",
                                     value: intBinding(\.minimumActivityPercent),
                                     range: 20...80,
                                     suffix: "%",
                                     accent: .blue)
                        Text("La actividad mínima protege la fluidez. Si macOS entra en estado térmico serio o crítico, la protección de emergencia puede reducir temporalmente por debajo de ese valor.")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)
                        Toggle("Proteger continuidad de audio",
                               isOn: $store.automaticAudioProtectionEnabled)
                        Text(store.automaticAudioProtectionEnabled
                             ? "El limitador detiene solo el host principal en pausas de hasta 2 ms con temporización monotónica; los ayudantes separados de audio y red permanecen activos. No puede eliminar todos los cortes si el audio vive dentro del mismo proceso. En estado térmico serio o crítico prevalece el freno completo del árbol."
                             : "Usa el freno por bloques tradicional sobre el árbol completo. Puede enfriar con menos señales, pero las pausas largas suelen entrecortar audio y presentación de fotogramas.")
                            .font(.caption2)
                            .foregroundColor(store.automaticAudioProtectionEnabled ? Color.secondary : Color.orange)
                        TargetSlider(title: "Histéresis",
                                     value: intBinding(\.hysteresisCelsius),
                                     range: 1...8,
                                     suffix: " °C",
                                     accent: .green)
                        Toggle("Tiers de throughput/latencia cuando macOS los permita",
                               isOn: $store.automaticMacPolicyEnabled)
                        Text("Esta capa es opcional y no encierra el proceso en E-cores. Si el sistema rechaza el puerto Mach o no incluye taskpolicy, ThermalBridge conserva todos los demás controles.")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)

                        Toggle("Anticipar el calentamiento con potencia CPU/GPU",
                               isOn: $store.automaticPowerAnticipationEnabled)
                        Text(store.automaticPowerAnticipationDetail)
                            .font(.caption2)
                            .foregroundColor(Color.secondary)

                        Toggle("Darwin Background para el juego solo en emergencia",
                               isOn: $store.automaticEmergencyBackgroundEnabled)
                        Text("Usa setpriority nativo únicamente con exceso grave o presión térmica seria. Es reversible, pero puede afectar red, audio o fluidez; permanece desactivado por defecto.")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)

                        Divider()
                        Text("Game Mode: integración retirada en RC3.5")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)

                        Toggle("Reducir la pantalla principal a 60 Hz cuando domine la GPU",
                               isOn: $store.automaticGPURefreshReductionEnabled)
                        Text("Cambia únicamente a un modo CoreGraphics con la misma resolución. Un guardián independiente conserva los datos del modo original y lo restaura también si ThermalBridge termina inesperadamente.")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)
                        Text(store.automaticDisplayRefreshStatus)
                            .font(.caption2)
                            .foregroundColor(store.automaticGPURefreshReductionEnabled
                                             ? Color.orange : Color.secondary)

                        Text(store.ioReportCapabilityAvailable
                             ? "IOReport: símbolos requeridos detectados. RC3.5 solo verifica la capacidad; todavía no alimenta el controlador térmico."
                             : "IOReport: capacidad no disponible. ThermalBridge conserva sus sensores actuales sin degradar el control.")
                            .font(.caption2)
                            .foregroundColor(Color.secondary)

                        if !store.crossOverInstallations.isEmpty {
                            Divider()
                            HStack(spacing: 10) {
                                Picker("QoS al abrir CrossOver", selection: $store.crossOverLaunchQoSClamp) {
                                    ForEach(MacLaunchQoSClamp.allCases) { clamp in
                                        Text(clamp.title).tag(clamp)
                                    }
                                }
                                .frame(maxWidth: 320)

                                Menu {
                                    ForEach(Array(store.crossOverInstallations), id: \.id) { (installation: CrossOverInstallation) in
                                        Button("\(installation.displayName) · \(installation.version)") {
                                            store.launchCrossOverWithQoS(installation)
                                        }
                                    }
                                } label: {
                                    Label("Abrir CrossOver con QoS", systemImage: "leaf.circle")
                                }
                                .disabled(!store.crossOverQoSLaunchAvailable)
                            }
                            Text(store.crossOverLaunchQoSClamp.explanation)
                                .font(.caption2)
                                .foregroundColor(Color.secondary)
                            Text(store.crossOverEfficientLaunchStatus)
                                .font(.caption2)
                                .foregroundColor(store.crossOverQoSLaunchAvailable ? Color.secondary : Color.orange)
                        }

                        Toggle("Reducir launchers y ayudantes de tienda",
                               isOn: $store.automaticThermalConfiguration.optimizeLaunchers)
                        if store.automaticThermalConfiguration.optimizeLaunchers {
                            TargetSlider(title: "Actividad de launchers",
                                         value: intBinding(\.launcherActivityPercent),
                                         range: 20...100,
                                         suffix: "%",
                                         accent: .gray)
                            Toggle("Aplicar política de fondo a launchers",
                                   isOn: $store.automaticThermalConfiguration.launcherBackground)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(6)
        } label: {
            Label("Temperatura objetivo", systemImage: "target")
                .font(.headline)
        }
    }

    private var controlSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        store.startAutomaticThermalControl(processID: selectedProcessID)
                    } label: {
                        Label(store.automaticThermalEnabled ? "Reaplicar control" : "Iniciar control automático",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedProcessID == nil && !store.automaticThermalConfiguration.hasTarget)

                    Button {
                        store.stopAutomaticThermalControl()
                    } label: {
                        Label("Detener", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                    .disabled(!store.automaticThermalEnabled)

                    Spacer()

                    if store.automaticThermalEmergency {
                        Label("Protección térmica", systemImage: "exclamationmark.shield.fill")
                            .foregroundColor(Color.red)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.automaticThermalStatus)
                        .font(.callout.weight(.medium))
                    Text(store.automaticThermalReason)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: store.automaticMacPolicyLevel.symbolName)
                        Text("Política macOS: \(store.automaticMacPolicyText)")
                            .fontWeight(.medium)
                        Text("· \(store.automaticMacPolicyDetail)")
                            .foregroundColor(Color.secondary)
                    }
                    .font(.caption)
                    if store.automaticThermalActivityPercent < 100 {
                        HStack(spacing: 6) {
                            Image(systemName: store.automaticLimiterPulseMode == .audioSafe
                                  ? "speaker.wave.2.circle" : "speaker.slash.circle")
                            Text("Limitador: \(store.automaticLimiterPulseMode.title)")
                                .fontWeight(.medium)
                            Text("· \(store.automaticLimiterPulseMode.explanation)")
                                .foregroundColor(Color.secondary)
                                .lineLimit(2)
                        }
                        .font(.caption)
                    }
                    if let root = store.automaticThermalProcess {
                        Text("Árbol: \(store.treeProcessCount(for: root)) procesos · CPU \(store.treeCPUText(for: root)) · GPU global \(store.gpuUtilizationText)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Color.secondary)
                        Text("QoS efectivo: \(store.automaticQoSEvidenceText)")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                        Text(store.automaticEnergyEvidenceText)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Control automático", systemImage: "thermometer.variable.and.figure")
                .font(.headline)
        }
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(Color.secondary)
            Text("macOS no permite fijar directamente los GHz ni forzar un proceso a E-cores. Esta beta conserva el control térmico por actividad, añade pulsos de audio protegido, Darwin Background nativo, clamp QoS opcional al abrir CrossOver, tiers cuando el sistema los acepta y anticipación por potencia. No modifica Wine, D3DMetal ni archivos del juego.")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func selectBestCandidateIfNeeded() {
        if let active = store.automaticThermalProcessID,
           store.process(for: active) != nil {
            selectedProcessID = active
            return
        }
        if let current = selectedProcessID,
           store.process(for: current) != nil {
            return
        }

        // No cambies a un .exe aleatorio cuando la lista de Wine se reordena.
        // Primero busca el objetivo ya guardado; si todavía no existe objetivo,
        // solo preselecciona el primer candidato sin capturarlo automáticamente.
        if store.automaticThermalConfiguration.hasTarget,
           let matching = store.automaticThermalGameCandidates.first(where: {
               store.automaticThermalConfiguration.matchScore(for: $0) != nil
           }) {
            selectedProcessID = matching.identity
        } else if store.automaticThermalConfiguration.hasTarget {
            selectedProcessID = nil
        } else {
            selectedProcessID = store.automaticThermalGameCandidates.first?.identity
        }
    }

    private func gameTitle(_ process: ProcessSnapshot) -> String {
        let bottle = process.crossOverBottleName.map { " · \($0)" } ?? ""
        if let executable = process.windowsExecutableName {
            return "\(executable)\(bottle) · PID \(process.pid) · CPU \(store.treeCPUText(for: process))"
        }
        return "Proceso CrossOver sin .exe · \(process.displayName)\(bottle) · PID \(process.pid) · CPU \(store.treeCPUText(for: process))"
    }


    private func chooseExecutableFile() {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar ejecutable Windows"
        panel.prompt = "Usar ejecutable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let executableType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [executableType]
        }

        let bottles = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
        if FileManager.default.fileExists(atPath: bottles.path) {
            panel.directoryURL = bottles
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.captureAutomaticThermalExecutable(at: url)
    }

    private var executableBinding: Binding<String> {
        Binding(
            get: { store.automaticThermalConfiguration.executableContains },
            set: { newValue in
                store.updateAutomaticThermalExecutableName(newValue)
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<AutomaticThermalConfiguration, Int>) -> Binding<Double> {
        Binding(
            get: { Double(store.automaticThermalConfiguration[keyPath: keyPath]) },
            set: { newValue in
                var config = store.automaticThermalConfiguration
                config[keyPath: keyPath] = Int(newValue.rounded())
                config.clamp()
                store.automaticThermalConfiguration = config
            }
        )
    }
}

private struct TemperatureCard: View {
    let title: String
    let value: String
    let target: Int
    let temperature: Double?
    let fresh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(cardColor)
            Text("Objetivo \(target) °C")
                .font(.caption2.monospacedDigit())
                .foregroundColor(Color.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardColor.opacity(0.25)))
    }

    private var cardColor: Color {
        guard fresh, let temperature else { return Color.secondary }
        let error = temperature - Double(target)
        if error > 4 { return Color.red }
        if error > 0 { return Color.orange }
        return Color.green
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
            HStack {
                Image(systemName: symbol)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundColor(emphasized ? Color.accentColor : Color.primary)
            Text(emphasized ? "Regulando" : "Sin límite")
                .font(.caption2)
                .foregroundColor(Color.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.20)))
    }
}

private struct TargetSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = " °C"
    let accent: Color

    init(title: String,
         value: Binding<Double>,
         range: ClosedRange<Int>,
         suffix: String = " °C",
         accent: Color) {
        self.title = title
        self._value = value
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.suffix = suffix
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 190, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
                .tint(accent)
            Text("\(Int(value.rounded()))\(suffix)")
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
    }
}
