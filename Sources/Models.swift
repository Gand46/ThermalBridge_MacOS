import Foundation

struct ProcessIdentity: Hashable, Codable, CustomStringConvertible {
    let pid: Int32
    let startID: UInt64

    var description: String { "\(pid)-\(startID)" }
}

/// Contadores acumulados publicados por el kernel. Un campo `nil` significa
/// que la versión de `proc_pid_rusage` disponible no expone esa métrica.
struct ProcessResourceCounters: Hashable {
    let rusageVersion: Int
    let directEnergyNJ: UInt64?
    let billedEnergyNJ: UInt64?
    let servicedEnergyNJ: UInt64?
    let qosDefaultNS: UInt64?
    let qosMaintenanceNS: UInt64?
    let qosBackgroundNS: UInt64?
    let qosUtilityNS: UInt64?
    let qosLegacyNS: UInt64?
    let qosUserInitiatedNS: UInt64?
    let qosUserInteractiveNS: UInt64?
}

struct ProcessSnapshot: Identifiable, Hashable {
    let identity: ProcessIdentity
    let parentPID: Int32
    let name: String
    let path: String
    let commandLine: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let niceValue: Int32
    let resourceCounters: ProcessResourceCounters?

    init(identity: ProcessIdentity,
         parentPID: Int32,
         name: String,
         path: String,
         commandLine: String,
         cpuPercent: Double,
         memoryBytes: UInt64,
         niceValue: Int32,
         resourceCounters: ProcessResourceCounters? = nil) {
        self.identity = identity
        self.parentPID = parentPID
        self.name = name
        self.path = path
        self.commandLine = commandLine
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.niceValue = niceValue
        self.resourceCounters = resourceCounters
    }

    var id: ProcessIdentity { identity }
    var pid: Int32 { identity.pid }

    /// Evidencia que no depende de que macOS publique el nombre del ejecutable
    /// Windows. Algunos juegos quedan detrás de un host con nombre neutro y
    /// argv vacío; sus descendientes se clasifican mediante ProcessTopologyIndex.
    var hasDirectCrossOverRuntimeEvidence: Bool {
        let rawName = name.lowercased()
        let rawPath = path.lowercased()
        let rawCommand = commandLine.lowercased()
        return Self.directCrossOverRuntimeNames.contains(rawName)
            || rawPath.contains("crossover.app")
            || rawPath.contains("crossover preview.app")
            || rawPath.contains("/crossover/bottles/")
            || rawPath.contains("/bottles/")
            || rawPath.contains("wine64-preloader")
            || rawPath.contains("wine-preloader")
            || rawCommand.contains("crossover.app")
            || rawCommand.contains("/bottles/")
            || rawCommand.contains("wineprefix=")
            || rawCommand.contains("cx_bottle=")
    }

    private static let wineRuntimeNames: Set<String> = [
        "wine", "wine64", "wine-preloader", "wine64-preloader", "cxstart"
    ]

    private static let directCrossOverRuntimeNames: Set<String> = [
        "crossover", "cxstart", "wine", "wine64", "wine-preloader",
        "wine64-preloader", "wineserver", "wineserver64"
    ]

    private static let ignoredWindowsExecutables: Set<String> = [
        "cmd.exe", "explorer.exe", "services.exe", "rundll32.exe", "start.exe",
        "plugplay.exe", "rpcss.exe", "winedevice.exe", "conhost.exe", "svchost.exe",
        "reg.exe", "regsvr32.exe", "wineboot.exe", "winecfg.exe", "winemenubuilder.exe",
        "winedbg.exe", "taskkill.exe", "tasklist.exe"
    ]

    private static let auxiliaryExecutableTokens = [
        "helper", "crash", "overlay", "updater", "update", "webview",
        "cefsubprocess", "anticheat", "easyanticheat", "battleye"
    ]

    private static let windowsExecutableExpressions: [NSRegularExpression] = [
        #"(?i)[\"']([^\"']+?\.exe)[\"']"#,
        #"(?i)(?:^|\s)([^\s\"']+?\.exe)(?=\s|$|[\"',;])"#,
        #"(?i)([A-Za-z]:[\\/][^\r\n\"']+?\.exe)"#,
        #"(?i)(/(?:[^\s\"']|\\ )+?\.exe)"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let bottlePathExpressions: [NSRegularExpression] = [
        #"(?i)/Bottles/([^/\"']+)"#,
        #"(?i)CrossOver/Bottles/([^/\"']+)"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let bottleEnvironmentExpressions: [NSRegularExpression] = [
        #"(?i)[\"']CX_BOTTLE=([^\"']+)[\"']"#,
        #"(?i)(?:^|\s)CX_BOTTLE=([^\s\"']+)"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    var displayName: String {
        let lowerName = name.lowercased()
        if Self.wineRuntimeNames.contains(lowerName), let executable = windowsExecutableName {
            return executable
        }
        if let direct = Self.normalizedExecutableComponent(name),
           direct.lowercased().hasSuffix(".exe") {
            return direct
        }
        if !name.isEmpty { return name }
        if let executable = windowsExecutableName { return executable }
        if !path.isEmpty { return URL(fileURLWithPath: path).lastPathComponent }
        return "Proceso \(pid)"
    }

    /// Ejecutables Windows hallados en nombre, ruta y argumentos. Se mantiene el
    /// orden de aparición y se eliminan duplicados para diagnosticar cadenas de
    /// lanzamiento de CrossOver que contienen varios .exe.
    var windowsExecutableCandidates: [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            guard let component = Self.normalizedExecutableComponent(raw),
                  component.lowercased().hasSuffix(".exe") else { return }
            let key = component.lowercased()
            guard !component.hasPrefix("-"), !seen.contains(key) else { return }

            // Una ruta entre comillas puede producir también una coincidencia parcial
            // por espacios (por ejemplo, «My Game.exe» y «Game.exe»). Conservamos
            // siempre la variante más completa para no mostrar un ejecutable truncado.
            if result.contains(where: { existing in
                let existingKey = existing.lowercased()
                return existingKey.count > key.count && existingKey.hasSuffix(key)
            }) {
                return
            }

            let shorterSuffixes = result.enumerated().compactMap { index, existing -> Int? in
                let existingKey = existing.lowercased()
                return key.count > existingKey.count && key.hasSuffix(existingKey) ? index : nil
            }
            for index in shorterSuffixes.reversed() {
                seen.remove(result[index].lowercased())
                result.remove(at: index)
            }

            seen.insert(key)
            result.append(component)
        }

        append(name)
        append(path)

        guard !commandLine.isEmpty else { return result }
        let fullRange = NSRange(commandLine.startIndex..<commandLine.endIndex, in: commandLine)
        for expression in Self.windowsExecutableExpressions {
            for match in expression.matches(in: commandLine, range: fullRange) {
                let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
                guard capture.location != NSNotFound,
                      let swiftRange = Range(capture, in: commandLine) else { continue }
                append(String(commandLine[swiftRange]))
            }
        }
        return result
    }

    var windowsExecutableName: String? {
        let candidates = windowsExecutableCandidates
        if let direct = Self.normalizedExecutableComponent(name),
           direct.lowercased().hasSuffix(".exe"),
           !Self.ignoredWindowsExecutables.contains(direct.lowercased()) {
            return direct
        }
        let usable = candidates.filter {
            !Self.ignoredWindowsExecutables.contains($0.lowercased())
        }
        if let primary = usable.first(where: { candidate in
            let lower = candidate.lowercased()
            return !Self.auxiliaryExecutableTokens.contains(where: { lower.contains($0) })
        }) {
            return primary
        }
        return usable.first
    }

    private static func normalizedExecutableComponent(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>,;"))
        value = value.replacingOccurrences(of: "\\\\?\\", with: "")
        value = value.replacingOccurrences(of: "\\ ", with: " ")
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        guard let component = normalized.split(separator: "/", omittingEmptySubsequences: true).last else {
            return nil
        }
        let cleaned = String(component)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>,;"))
        guard cleaned.lowercased().hasSuffix(".exe") else {
            return nil
        }
        return cleaned
    }

    func containsWindowsExecutable(named rawName: String) -> Bool {
        let needle = rawName
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard needle.hasSuffix(".exe") else { return false }
        return windowsExecutableCandidates.contains { $0.lowercased() == needle }
    }

    /// Calidad de la evidencia del ejecutable. Se usa para mantener una
    /// selección determinista cuando un mismo árbol Wine expone varios .exe.
    func windowsExecutableEvidenceScore(named rawName: String) -> Int? {
        let needle = rawName
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard needle.hasSuffix(".exe") else { return nil }
        if let direct = Self.normalizedExecutableComponent(name), direct.lowercased() == needle {
            return 1_200
        }
        if windowsExecutableCandidates.contains(where: { $0.lowercased() == needle }) {
            return 1_100
        }
        if commandLine.lowercased().contains(needle) {
            return 800
        }
        return nil
    }

    var normalizedExecutableName: String {
        let candidate = windowsExecutableName ?? displayName
        return candidate
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? candidate.lowercased()
    }

    var crossOverBottleName: String? {
        let combined = [path, commandLine].joined(separator: " ")
        for expression in Self.bottlePathExpressions {
            let range = NSRange(combined.startIndex..<combined.endIndex, in: combined)
            guard let match = expression.firstMatch(in: combined, range: range),
                  let swiftRange = Range(match.range(at: 1), in: combined) else { continue }
            let raw = String(combined[swiftRange])
            let value = (raw.removingPercentEncoding ?? raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }

        // Algunas versiones de CrossOver solo publican el nombre mediante el
        // entorno del proceso. ProcessBridge añade de forma selectiva estas
        // variables al texto de diagnóstico.
        for expression in Self.bottleEnvironmentExpressions {
            let range = NSRange(combined.startIndex..<combined.endIndex, in: combined)
            guard let match = expression.firstMatch(in: combined, range: range),
                  let swiftRange = Range(match.range(at: 1), in: combined) else { continue }
            let value = String(combined[swiftRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    var searchableText: String {
        ([displayName, name, path, commandLine, String(pid)] + windowsExecutableCandidates)
            .joined(separator: " ")
            .lowercased()
    }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var cpuText: String {
        String(format: "%.1f %%", cpuPercent)
    }
}

/// Resuelve instantáneas seguras para retirar políticas al cerrar. La muestra
/// más reciente tiene prioridad, pero una copia confirmada permite restaurar
/// un proceso vivo aunque falte transitoriamente del último censo.
enum ProcessRestorationResolver {
    static func targets(for identities: Set<ProcessIdentity>,
                        current: [ProcessSnapshot],
                        cached: [ProcessIdentity: ProcessSnapshot]) -> [ProcessSnapshot] {
        // No usamos Dictionary(uniqueKeysWithValues:) porque una muestra
        // anómala con identidades repetidas no debe cerrar la aplicación.
        var currentByIdentity: [ProcessIdentity: ProcessSnapshot] = [:]
        currentByIdentity.reserveCapacity(current.count)
        for process in current {
            currentByIdentity[process.identity] = process
        }
        return identities.compactMap { identity in
            currentByIdentity[identity] ?? cached[identity]
        }
    }
}

/// Índice inmutable de una muestra. Evita reconstruir un diccionario completo
/// cada vez que se pregunta si un proceso desciende de CrossOver y, sobre todo,
/// permite reconocer hosts neutros aunque no contengan «wine» ni «.exe».
struct ProcessTopologyIndex {
    private let processesByPID: [Int32: ProcessSnapshot]

    init(processes: [ProcessSnapshot]) {
        var indexed: [Int32: ProcessSnapshot] = [:]
        indexed.reserveCapacity(processes.count)
        for process in processes {
            // La caché de observación normalmente elimina la identidad anterior
            // antes de aceptar un PID reutilizado. La asignación defensiva evita
            // que una muestra anómala provoque un trap por clave duplicada.
            indexed[process.pid] = process
        }
        processesByPID = indexed
    }

    func hasCrossOverRuntimeAncestor(of process: ProcessSnapshot) -> Bool {
        var parentPID = process.parentPID
        var visited = Set<Int32>()
        var depth = 0
        while parentPID > 0, visited.insert(parentPID).inserted, depth < 24 {
            guard let parent = processesByPID[parentPID] else { return false }
            if parent.hasDirectCrossOverRuntimeEvidence { return true }
            parentPID = parent.parentPID
            depth += 1
        }
        return false
    }
}

enum RuleTrigger: String, Codable, CaseIterable, Identifiable {
    case whileRunning
    case whenBackground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whileRunning: return "Mientras esté ejecutándose"
        case .whenBackground: return "Solo cuando esté en segundo plano"
        }
    }

    var explanation: String {
        switch self {
        case .whileRunning:
            return "La regla permanece activa mientras exista un proceso coincidente."
        case .whenBackground:
            return "La regla se aplica cuando el PID coincidente no es la aplicación frontal y se revierte al volver al frente cuando la acción lo permite."
        }
    }
}

enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case background
    case lowPriority
    case cpuLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background: return "Fondo / eficiencia"
        case .lowPriority: return "Prioridad baja (+10)"
        case .cpuLimit: return "Control de actividad"
        }
    }

    var explanation: String {
        switch self {
        case .background:
            return "Aplica la política Darwin de fondo. Es reversible y puede favorecer núcleos de eficiencia, pero no fija afinidad."
        case .lowPriority:
            return "Aumenta el valor nice. No siempre puede restaurarse sin permisos antes de que termine el proceso."
        case .cpuLimit:
            return "Regula el tiempo activo del proceso y sus descendientes con SIGSTOP/SIGCONT. 80 % significa ejecutar el árbol durante el 80 % de cada ciclo."
        }
    }

    var isReversible: Bool {
        self != .lowPriority
    }
}

struct ProcessRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var nameContains = ""
    var pathContains = ""
    var trigger: RuleTrigger = .whileRunning
    var action: RuleAction = .background
    var cpuLimitPercent = 80

    func matches(_ process: ProcessSnapshot) -> Bool {
        guard enabled else { return false }
        let nameNeedle = nameContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathNeedle = pathContains.trimmingCharacters(in: .whitespacesAndNewlines)

        if !nameNeedle.isEmpty,
           !process.displayName.localizedCaseInsensitiveContains(nameNeedle) {
            return false
        }

        if !pathNeedle.isEmpty,
           !process.path.localizedCaseInsensitiveContains(pathNeedle),
           !process.commandLine.localizedCaseInsensitiveContains(pathNeedle) {
            return false
        }

        return !nameNeedle.isEmpty || !pathNeedle.isEmpty
    }
}

struct ThermalTarget: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var nameContains = ""
    var pathContains = ""
    var cpuLimitPercent = 80

    func matches(_ process: ProcessSnapshot) -> Bool {
        guard enabled else { return false }
        let nameNeedle = nameContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathNeedle = pathContains.trimmingCharacters(in: .whitespacesAndNewlines)

        if !nameNeedle.isEmpty,
           !process.displayName.localizedCaseInsensitiveContains(nameNeedle) {
            return false
        }
        if !pathNeedle.isEmpty,
           !process.path.localizedCaseInsensitiveContains(pathNeedle) {
            return false
        }
        return !nameNeedle.isEmpty || !pathNeedle.isEmpty
    }
}

enum ThermalLabel: String, Codable, CaseIterable, Identifiable {
    case nominal = "Nominal"
    case fair = "Elevado"
    case serious = "Serio"
    case critical = "Crítico"
    case unknown = "Desconocido"

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        case .unknown: return -1
        }
    }
}

enum ThermalThreshold: String, Codable, CaseIterable, Identifiable {
    case fair
    case serious
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fair: return "Elevado"
        case .serious: return "Serio"
        case .critical: return "Crítico"
        }
    }

    var rank: Int {
        switch self {
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        }
    }
}

struct MetricPoint: Identifiable, Hashable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let message: String
    let isError: Bool

    var timeText: String {
        Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct TelemetryRecord: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let totalCPUPercent: Double
    let selectedTreeCPUPercent: Double?
    let gpuPercent: Double?
    let rendererPercent: Double?
    let tilerPercent: Double?
    let gpuActivityLimitPercent: Int?
    let thermalState: ThermalLabel
}


enum CrossOverPreset: String, Codable, CaseIterable, Identifiable {
    case performance
    case balanced
    case cool
    case compatibility
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: return "Máximo rendimiento"
        case .balanced: return "Equilibrado"
        case .cool: return "Frío"
        case .compatibility: return "Compatibilidad"
        case .custom: return "Personalizado"
        }
    }

    var explanation: String {
        switch self {
        case .performance:
            return "No limita el juego; reduce launchers y ayudantes para liberar CPU y memoria."
        case .balanced:
            return "Mantiene el juego sin límite fijo y usa GPU Guard con una reducción moderada."
        case .cool:
            return "Prioriza temperatura y estabilidad sostenida con límites más estrictos."
        case .compatibility:
            return "Observa el juego sin modificar sus procesos ni los launchers."
        case .custom:
            return "Conserva los valores definidos manualmente."
        }
    }
}

struct CrossOverProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var name = "Perfil CrossOver"
    var preset: CrossOverPreset = .custom
    var bottleName = ""
    var executableContains = ""
    var pathContains = ""
    var autoAttach = true

    var gameActivityPercent = 100
    var gpuGuardEnabled = true
    var gpuTargetPercent = 75
    var gpuMinimumActivityPercent = 50
    var gpuStepPercent = 5
    var gpuAllowsRecovery = false

    var optimizeLaunchers = true
    var launcherBackground = true
    var launcherActivityPercent = 60

    var optimizeExternalApps = false
    var externalActivityPercent = 60
    var externalNames = "Google Chrome\nDropbox\nOneDrive\nGoogle Drive"

    var thermalEmergencyEnabled = true
    var thermalThreshold: ThermalThreshold = .serious
    var thermalActivityPercent = 65

    var normalizedExecutableNeedle: String {
        executableContains
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    var hasTarget: Bool {
        !normalizedExecutableNeedle.isEmpty || !pathContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matchScore(for process: ProcessSnapshot) -> Int? {
        guard enabled, hasTarget else { return nil }
        let executableNeedle = normalizedExecutableNeedle
        let pathNeedle = pathContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let processExecutable = process.normalizedExecutableName
        let display = process.displayName.lowercased()
        let path = process.path.lowercased()
        let command = process.commandLine.lowercased()

        var score = 0
        if !executableNeedle.isEmpty {
            if processExecutable == executableNeedle {
                score += 1_000
            } else if display == executableNeedle {
                score += 900
            } else if command.contains(executableNeedle) {
                score += 600
            } else if display.contains(executableNeedle) || path.contains(executableNeedle) {
                score += 350
            } else {
                return nil
            }
        }

        if !pathNeedle.isEmpty {
            guard path.contains(pathNeedle) || command.contains(pathNeedle) else { return nil }
            score += 200
        }

        let bottleNeedle = bottleName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bottleNeedle.isEmpty {
            if let detectedBottle = process.crossOverBottleName?.lowercased() {
                guard detectedBottle == bottleNeedle else { return nil }
                score += 500
            } else {
                let bottlePathToken = "/bottles/\(bottleNeedle)/"
                guard path.contains(bottlePathToken) || command.contains(bottlePathToken) else {
                    return nil
                }
                score += 250
            }
        }

        if process.windowsExecutableName != nil { score += 100 }
        return score
    }

    func matches(_ process: ProcessSnapshot) -> Bool {
        matchScore(for: process) != nil
    }

    var effectivePreset: CrossOverPreset {
        guard preset != .custom, isConfigurationEquivalent(to: preset) else { return .custom }
        return preset
    }

    func isConfigurationEquivalent(to candidate: CrossOverPreset) -> Bool {
        guard candidate != .custom else { return preset == .custom }
        let reference = CrossOverProfile.presetProfile(candidate)
        return gameActivityPercent == reference.gameActivityPercent
            && gpuGuardEnabled == reference.gpuGuardEnabled
            && gpuTargetPercent == reference.gpuTargetPercent
            && gpuMinimumActivityPercent == reference.gpuMinimumActivityPercent
            && gpuStepPercent == reference.gpuStepPercent
            && gpuAllowsRecovery == reference.gpuAllowsRecovery
            && optimizeLaunchers == reference.optimizeLaunchers
            && launcherBackground == reference.launcherBackground
            && launcherActivityPercent == reference.launcherActivityPercent
            && optimizeExternalApps == reference.optimizeExternalApps
            && externalActivityPercent == reference.externalActivityPercent
            && (!optimizeExternalApps || externalNameTokens == reference.externalNameTokens)
            && thermalEmergencyEnabled == reference.thermalEmergencyEnabled
            && thermalThreshold == reference.thermalThreshold
            && thermalActivityPercent == reference.thermalActivityPercent
    }

    var validationMessages: [String] {
        var messages: [String] = []
        if !hasTarget {
            messages.append("Falta capturar o escribir el ejecutable del juego.")
        }
        if gpuGuardEnabled && gpuMinimumActivityPercent > gameActivityPercent {
            messages.append("La actividad fija del juego es más restrictiva que el mínimo de GPU Guard.")
        }
        if thermalEmergencyEnabled && thermalActivityPercent > gameActivityPercent {
            messages.append("El límite térmico no será más restrictivo que la actividad fija actual.")
        }
        if optimizeLaunchers && launcherActivityPercent >= 100 && !launcherBackground {
            messages.append("La optimización de launchers está activa, pero no aplica ningún cambio.")
        }
        if autoAttach && !hasTarget {
            messages.append("La autoaplicación no puede funcionar sin una coincidencia de ejecutable o ruta.")
        }
        return messages
    }

    var externalNameTokens: [String] {
        externalNames
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func presetProfile(_ preset: CrossOverPreset) -> CrossOverProfile {
        var profile = CrossOverProfile()
        profile.applyPreset(preset)
        return profile
    }

    mutating func applyPreset(_ newPreset: CrossOverPreset) {
        preset = newPreset
        switch newPreset {
        case .performance:
            name = "Máximo rendimiento"
            gameActivityPercent = 100
            gpuGuardEnabled = false
            gpuTargetPercent = 85
            gpuMinimumActivityPercent = 70
            gpuStepPercent = 5
            gpuAllowsRecovery = false
            optimizeLaunchers = true
            launcherBackground = true
            launcherActivityPercent = 70
            optimizeExternalApps = false
            externalActivityPercent = 70
            thermalEmergencyEnabled = true
            thermalThreshold = .serious
            thermalActivityPercent = 85
        case .balanced:
            name = "Equilibrado"
            gameActivityPercent = 100
            gpuGuardEnabled = true
            gpuTargetPercent = 75
            gpuMinimumActivityPercent = 55
            gpuStepPercent = 5
            gpuAllowsRecovery = false
            optimizeLaunchers = true
            launcherBackground = true
            launcherActivityPercent = 60
            optimizeExternalApps = false
            externalActivityPercent = 65
            thermalEmergencyEnabled = true
            thermalThreshold = .serious
            thermalActivityPercent = 70
        case .cool:
            name = "Frío"
            gameActivityPercent = 90
            gpuGuardEnabled = true
            gpuTargetPercent = 65
            gpuMinimumActivityPercent = 40
            gpuStepPercent = 5
            gpuAllowsRecovery = false
            optimizeLaunchers = true
            launcherBackground = true
            launcherActivityPercent = 45
            optimizeExternalApps = true
            externalActivityPercent = 50
            thermalEmergencyEnabled = true
            thermalThreshold = .fair
            thermalActivityPercent = 60
        case .compatibility:
            name = "Compatibilidad"
            gameActivityPercent = 100
            gpuGuardEnabled = false
            gpuTargetPercent = 90
            gpuMinimumActivityPercent = 80
            gpuStepPercent = 5
            gpuAllowsRecovery = false
            optimizeLaunchers = false
            launcherBackground = false
            launcherActivityPercent = 100
            optimizeExternalApps = false
            externalActivityPercent = 100
            thermalEmergencyEnabled = false
            thermalThreshold = .critical
            thermalActivityPercent = 100
        case .custom:
            break
        }
    }
}

struct CrossOverInstallation: Identifiable, Hashable {
    let path: String
    let displayName: String
    let version: String

    var id: String { path }
}

struct CrossOverBottle: Identifiable, Hashable {
    let path: String
    let name: String
    let modifiedAt: Date?

    var id: String { path }
}
