import AppKit
import Foundation
import Darwin
import ServiceManagement
import UniformTypeIdentifiers

final class ProcessStore: ObservableObject {
    enum SortMode: String, CaseIterable, Identifiable {
        case stable = "Estable"
        case cpu = "CPU"
        case memory = "Memoria"
        case name = "Nombre"
        case pid = "PID"

        var id: String { rawValue }
    }


    enum ProcessScope: String, CaseIterable, Identifiable {
        case applications = "Aplicaciones"
        case crossOver = "CrossOver"
        case controlled = "Controlados"
        case all = "Todos"

        var id: String { rawValue }
    }

    @Published private(set) var processes: [ProcessSnapshot] = []
    @Published var searchText = "" {
        didSet {
            guard !loadingPersistence, searchText != oldValue else { return }
            UserDefaults.standard.set(searchText, forKey: Keys.processSearch)
        }
    }
    @Published var showProtected = false {
        didSet {
            guard !loadingPersistence, showProtected != oldValue else { return }
            UserDefaults.standard.set(showProtected, forKey: Keys.processShowProtected)
        }
    }
    @Published var sortMode: SortMode = .stable {
        didSet {
            guard !loadingPersistence, sortMode != oldValue else { return }
            UserDefaults.standard.set(sortMode.rawValue, forKey: Keys.processSortMode)
        }
    }
    @Published var processScope: ProcessScope = .applications {
        didSet {
            guard !loadingPersistence, processScope != oldValue else { return }
            UserDefaults.standard.set(processScope.rawValue, forKey: Keys.processScope)
        }
    }
    @Published private(set) var isMonitoring = false
    @Published private(set) var thermalLabel: ThermalLabel = .unknown
    @Published private(set) var backgroundIDs: Set<ProcessIdentity> = []
    @Published private(set) var suspendedIDs: Set<ProcessIdentity> = []
    @Published private(set) var lowPriorityIDs: Set<ProcessIdentity> = []
    @Published private(set) var cpuLimitByID: [ProcessIdentity: Int] = [:]
    @Published private(set) var logEntries: [LogEntry] = []
    @Published private(set) var systemCPUHistory: [MetricPoint] = []
    @Published private(set) var selectedProcessHistory: [MetricPoint] = []
    @Published private(set) var selectedProcessID: ProcessIdentity?
    @Published private(set) var frontmostPID: Int32 = 0
    @Published private(set) var frontmostName = "Desconocida"
    @Published private(set) var thermalAutomationActive = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var gpuUtilization: Double?
    @Published private(set) var rendererUtilization: Double?
    @Published private(set) var tilerUtilization: Double?
    @Published private(set) var gpuMemoryBytes: UInt64?
    @Published private(set) var gpuMetricsSource = "No disponible"
    @Published private(set) var gpuHistory: [MetricPoint] = []
    @Published private(set) var selectedTreeCPUHistory: [MetricPoint] = []
    @Published private(set) var gpuGuardActivityHistory: [MetricPoint] = []
    @Published private(set) var telemetryRecords: [TelemetryRecord] = []
    @Published private(set) var gpuGuardEnabled = false
    @Published private(set) var gpuGuardProcessID: ProcessIdentity?
    @Published private(set) var gpuGuardCurrentActivityPercent = 100
    @Published private(set) var gpuGuardStatus = "Inactivo"
    @Published private(set) var isCapturingPower = false
    @Published private(set) var lastPowerSnapshot: PowerMetricsSnapshot?
    @Published var crossOverProfiles: [CrossOverProfile] = [] {
        didSet { persistCrossOverProfiles() }
    }
    @Published var selectedCrossOverProfileID: UUID? {
        didSet {
            guard selectedCrossOverProfileID != oldValue else { return }
            if let selectedCrossOverProfileID {
                UserDefaults.standard.set(selectedCrossOverProfileID.uuidString, forKey: Keys.crossOverSelectedProfile)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.crossOverSelectedProfile)
            }
            scheduleCrossOverEvaluation()
        }
    }
    @Published var crossOverAutoAttachEnabled = false {
        didSet {
            guard crossOverAutoAttachEnabled != oldValue else { return }
            UserDefaults.standard.set(crossOverAutoAttachEnabled, forKey: Keys.crossOverAutoAttach)
            scheduleCrossOverEvaluation()
        }
    }
    @Published private(set) var crossOverInstallations: [CrossOverInstallation] = []
    @Published private(set) var crossOverBottles: [CrossOverBottle] = []
    @Published private(set) var activeCrossOverProfileID: UUID?
    @Published private(set) var activeCrossOverProcessID: ProcessIdentity?
    @Published private(set) var crossOverStatus = "Sin perfil activo"
    @Published private(set) var isScanningCrossOver = false
    @Published private(set) var lastCrossOverScanDate: Date?

    // Modo automático térmico exclusivo para CrossOver (v0.7 beta).
    @Published var automaticThermalConfiguration = AutomaticThermalConfiguration() {
        didSet { persistAutomaticThermalConfiguration() }
    }
    @Published var automaticThermalEnabled = false
    @Published var automaticThermalProcessID: ProcessIdentity?
    @Published var automaticThermalActivityPercent = 100
    @Published var automaticThermalReason = "Inactivo"
    @Published var automaticThermalStatus = "Selecciona un juego de CrossOver"
    @Published var automaticThermalEmergency = false
    @Published var automaticMacPolicyEnabled = true {
        didSet {
            guard !loadingPersistence, automaticMacPolicyEnabled != oldValue else { return }
            UserDefaults.standard.set(automaticMacPolicyEnabled, forKey: Keys.automaticMacPolicyEnabled)
            if automaticMacPolicyEnabled {
                automaticMacPolicyRuntimeAvailable = true
                automaticMacPolicyStatus = "Reintentando políticas macOS"
                evaluateAutomaticThermalMode(force: true)
            } else {
                restoreAutomaticMacPolicies()
                automaticMacPolicyStatus = "Políticas macOS desactivadas"
            }
        }
    }
    @Published var automaticMacPolicyRuntimeAvailable = true
    @Published var automaticMacPolicyLevel: MacApplicationPolicyLevel = .normal
    @Published var automaticMacPolicyStatus = "Políticas macOS en espera"
    @Published var automaticPowerAnticipationEnabled = true {
        didSet {
            guard !loadingPersistence, automaticPowerAnticipationEnabled != oldValue else { return }
            UserDefaults.standard.set(automaticPowerAnticipationEnabled, forKey: Keys.automaticPowerAnticipationEnabled)
            evaluateAutomaticThermalMode(force: false)
        }
    }
    @Published var automaticAudioProtectionEnabled = true {
        didSet {
            guard !loadingPersistence, automaticAudioProtectionEnabled != oldValue else { return }
            UserDefaults.standard.set(automaticAudioProtectionEnabled, forKey: Keys.automaticAudioProtectionEnabled)
            evaluateAutomaticThermalMode(force: true)
        }
    }
    @Published var automaticLimiterPulseMode: ActivityLimiterPulseMode = .audioSafe
    @Published var automaticThermalRequestedActivityPercent = 100
    @Published var automaticEmergencyBackgroundEnabled = false {
        didSet {
            guard !loadingPersistence, automaticEmergencyBackgroundEnabled != oldValue else { return }
            UserDefaults.standard.set(automaticEmergencyBackgroundEnabled, forKey: Keys.automaticEmergencyBackgroundEnabled)
            evaluateAutomaticThermalMode(force: true)
        }
    }
    @Published var automaticGPURefreshReductionEnabled = false {
        didSet {
            guard !loadingPersistence,
                  automaticGPURefreshReductionEnabled != oldValue else { return }
            UserDefaults.standard.set(automaticGPURefreshReductionEnabled,
                                      forKey: Keys.automaticGPURefreshReductionEnabled)
            displayRefreshConfigurationChanged()
        }
    }
    @Published private(set) var automaticDisplayRefreshStatus = "Desactivado"
    @Published var crossOverLaunchQoSClamp: MacLaunchQoSClamp = .utility {
        didSet {
            guard !loadingPersistence, crossOverLaunchQoSClamp != oldValue else { return }
            UserDefaults.standard.set(crossOverLaunchQoSClamp.rawValue, forKey: Keys.crossOverLaunchQoSClamp)
        }
    }
    @Published private(set) var crossOverEfficientLaunchStatus = "Inicio QoS listo"
    @Published private(set) var lastCrossOverEfficientLaunchPID: Int32?
    @Published private(set) var lastCrossOverRequestedQoSClamp: MacLaunchQoSClamp?
    @Published private(set) var lastSessionTelemetryURL: URL?
    @Published private(set) var automaticTreeResourceMetrics: ProcessTreeResourceMetrics?
    @Published private(set) var automaticQoSEvidence = QoSEvidence(
        state: .unavailable,
        requestedClass: nil,
        dominantClass: nil,
        observedRequestedCPUTimeNS: nil
    )
    private var lastCrossOverQoSRequestAccepted = false
    private var lastCrossOverQoSRequestFailed = false

    func updateCrossOverEfficientLaunchStatus(_ status: String) {
        crossOverEfficientLaunchStatus = status
    }

    func updateLastSessionTelemetryURL(_ url: URL?) {
        lastSessionTelemetryURL = url
    }

    func resetAutomaticResourceEvidence() {
        automaticTreeResourceMetrics = nil
        automaticQoSEvidence = QoSEvidence(
            state: .unavailable,
            requestedClass: nil,
            dominantClass: nil,
            observedRequestedCPUTimeNS: nil
        )
    }

    func updateAutomaticDisplayRefreshStatus(_ status: String) {
        guard automaticDisplayRefreshStatus != status else { return }
        automaticDisplayRefreshStatus = status
    }

    func recordCrossOverEfficientLaunch(pid: Int32,
                                        clamp: MacLaunchQoSClamp,
                                        status: String) {
        lastCrossOverEfficientLaunchPID = pid
        lastCrossOverRequestedQoSClamp = clamp
        lastCrossOverQoSRequestAccepted = true
        lastCrossOverQoSRequestFailed = false
        crossOverEfficientLaunchStatus = status
    }

    func recordCrossOverEfficientLaunchFailure(clamp: MacLaunchQoSClamp,
                                               status: String) {
        lastCrossOverRequestedQoSClamp = clamp
        lastCrossOverQoSRequestAccepted = false
        lastCrossOverQoSRequestFailed = true
        crossOverEfficientLaunchStatus = status
    }
    // Temperaturas de control: máximo instantáneo entre sensores CPU/GPU.
    @Published var cpuTemperatureCelsius: Double?
    @Published var gpuTemperatureCelsius: Double?
    @Published var cpuAverageTemperatureCelsius: Double?
    @Published var gpuAverageTemperatureCelsius: Double?
    @Published var cpuMaximumSensorName: String?
    @Published var gpuMaximumSensorName: String?
    @Published var cpuTemperatureSensorCount = 0
    @Published var gpuTemperatureSensorCount = 0
    @Published var temperatureReadingSource = "Sin lectura"
    @Published var cpuTemperatureSmoothedCelsius: Double?
    @Published var gpuTemperatureSmoothedCelsius: Double?
    @Published var temperatureSensorState: MacMonTemperatureSensor.SensorState = .stopped
    @Published var lastTemperatureReadingDate: Date?
    @Published var sensorCPUPowerWatts: Double?
    @Published var sensorGPUPowerWatts: Double?

    @Published var gpuGuardTargetPercent: Int = 75 {
        didSet { UserDefaults.standard.set(gpuGuardTargetPercent, forKey: Keys.gpuGuardTarget) }
    }
    @Published var gpuGuardMinimumActivityPercent: Int = 40 {
        didSet { UserDefaults.standard.set(gpuGuardMinimumActivityPercent, forKey: Keys.gpuGuardMinimum) }
    }
    @Published var gpuGuardStepPercent: Int = 5 {
        didSet { UserDefaults.standard.set(gpuGuardStepPercent, forKey: Keys.gpuGuardStep) }
    }
    @Published var gpuGuardAllowsRecovery = false {
        didSet { UserDefaults.standard.set(gpuGuardAllowsRecovery, forKey: Keys.gpuGuardRecovery) }
    }

    @Published var rules: [ProcessRule] = [] {
        didSet { persistRules() }
    }
    @Published var thermalTargets: [ThermalTarget] = [] {
        didSet { persistThermalTargets() }
    }
    @Published var suspensionTimeoutSeconds: Int = 300 {
        didSet { UserDefaults.standard.set(suspensionTimeoutSeconds, forKey: Keys.suspensionTimeout) }
    }
    @Published var thermalAutomationEnabled = false {
        didSet {
            UserDefaults.standard.set(thermalAutomationEnabled, forKey: Keys.thermalEnabled)
            evaluateAutomations()
        }
    }
    @Published var thermalThreshold: ThermalThreshold = .serious {
        didSet {
            UserDefaults.standard.set(thermalThreshold.rawValue, forKey: Keys.thermalThreshold)
            evaluateAutomations()
        }
    }
    @Published var limiterCycleMilliseconds: Int = 40 {
        didSet {
            UserDefaults.standard.set(limiterCycleMilliseconds, forKey: Keys.limiterCycle)
        }
    }

    private let sampler = ProcessSampler()
    private let systemMetricsSampler = SystemMetricsSampler()
    private let powerMetricsSampler = PowerMetricsSampler()
    private let crossOverDiscovery = CrossOverDiscovery()
    let sessionTelemetryWriter = SessionTelemetryWriter()
    let temperatureSensor = MacMonTemperatureSensor()
    let automaticThermalEngine = ThermalControlEngine()
    let controller = ProcessController()
    let displayRefreshController = DisplayRefreshController()
    lazy var ioReportCapabilityAvailable = tb_ioreport_capability() == 1
    private let samplingQueue = DispatchQueue(label: "ThermalBridge.ProcessSampling", qos: .utility)
    let controlQueue = DispatchQueue(label: "ThermalBridge.ProcessControl", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var knownIdentities: Set<ProcessIdentity> = []
    private var stableOrderByID: [ProcessIdentity: Int] = [:]
    private var nextStableOrder = 0
    private var smoothedCPUByID: [ProcessIdentity: Double] = [:]
    private var processObservationCache = ProcessObservationCache()
    private var processTopologyIndex = ProcessTopologyIndex(processes: [])
    private var processResourceObservationCache = ProcessResourceObservationCache()
    private var latestProcessResourceDeltas: [ProcessIdentity: ProcessResourceDelta] = [:]
    private let processObservationGraceInterval: TimeInterval = 3.5
    var automaticThermalMissingSamples = 0
    var automaticThermalLastRootSnapshot: ProcessSnapshot?
    var automaticThermalSessionIDs: Set<ProcessIdentity> = []
    // Solo se establece cuando el usuario confirma «Usar selección». Permite
    // controlar un wine64-preloader aunque argv o el nombre .exe estén ocultos.
    var automaticThermalPreferredProcessID: ProcessIdentity?
    var automaticThermalPreferredExecutableNeedle: String?
    var suppressAutomaticThermalConfigurationEvaluation = false
    private var lowPriorityAttempts: Set<String> = []
    private var watchdogs: [ProcessIdentity: Process] = [:]
    private var cpuLimiters: [ProcessIdentity: Process] = [:]
    private var cpuLimiterGuardians: [ProcessIdentity: Process] = [:]
    private var backgroundSources: [ProcessIdentity: Set<String>] = [:]
    private var backgroundSnapshots: [ProcessIdentity: ProcessSnapshot] = [:]
    private var cpuLimitSources: [ProcessIdentity: [String: Int]] = [:]
    private var cpuLimitModeSources: [ProcessIdentity: [String: ActivityLimiterPulseMode]] = [:]
    private var cpuLimiterModeByID: [ProcessIdentity: ActivityLimiterPulseMode] = [:]
    private var backgroundTokens: [ProcessIdentity: UUID] = [:]
    private var processHistory: [ProcessIdentity: [MetricPoint]] = [:]
    private var loadingPersistence = true
    private var workspaceObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?
    private var lastThermalAutomationState = false
    private var samplingCounter = 0
    private var cachedSystemMetrics = SystemMetricsSample(gpuUtilization: nil,
                                                          rendererUtilization: nil,
                                                          tilerUtilization: nil,
                                                          gpuMemoryBytes: nil,
                                                          source: "No disponible")
    private var gpuGuardHighSamples = 0
    private var gpuGuardLowSamples = 0
    private var lastGPUGuardEvaluation = Date.distantPast
    private let gpuGuardSourceKey = "gpu-guard"
    private let crossOverSourcePrefix = "crossover:"
    let automaticThermalSourceKey = "automatic-thermal:game"
    let automaticThermalLauncherSourceKey = "automatic-thermal:launcher"
    let automaticThermalEmergencyBackgroundSourceKey = "automatic-thermal:emergency-background"
    var lastAutomaticThermalEvaluation = Date.distantPast
    var lastAutomaticThermalDecisionReadingDate: Date?
    var automaticMacPolicyAppliedIDs: Set<ProcessIdentity> = []
    var automaticMacPolicySnapshots: [ProcessIdentity: ProcessSnapshot] = [:]
    var automaticMacPolicyGeneration = 0
    var displayRefreshFailureLatched = false
    private var gpuGuardOwnedByCrossOverProfile = false
    private var crossOverEvaluationInProgress = false
    private var crossOverMutationDepth = 0
    private var crossOverEvaluationWorkItem: DispatchWorkItem?
    private var activeCrossOverWasAutoAttached = false

    private enum Keys {
        static let rules = "ThermalBridge.rules.v3"
        static let thermalTargets = "ThermalBridge.thermalTargets.v3"
        static let suspensionTimeout = "ThermalBridge.suspensionTimeout.v1"
        static let thermalEnabled = "ThermalBridge.thermalEnabled.v3"
        static let thermalThreshold = "ThermalBridge.thermalThreshold.v3"
        static let limiterCycle = "ThermalBridge.limiterCycle.v3"
        static let automaticMacPolicyEnabled = "ThermalBridge.automaticMacPolicyEnabled.beta1"
        static let automaticPowerAnticipationEnabled = "ThermalBridge.automaticPowerAnticipationEnabled.beta4"
        static let automaticAudioProtectionEnabled = "ThermalBridge.automaticAudioProtection.beta6"
        static let automaticEmergencyBackgroundEnabled = "ThermalBridge.automaticEmergencyBackgroundEnabled.beta4"
        static let automaticGPURefreshReductionEnabled = "ThermalBridge.automaticGPURefreshReductionEnabled.beta10"
        static let crossOverLaunchQoSClamp = "ThermalBridge.crossOverLaunchQoSClamp.beta4"
        static let gpuGuardTarget = "ThermalBridge.gpuGuardTarget.v1"
        static let gpuGuardMinimum = "ThermalBridge.gpuGuardMinimum.v1"
        static let gpuGuardStep = "ThermalBridge.gpuGuardStep.v1"
        static let gpuGuardRecovery = "ThermalBridge.gpuGuardRecovery.v1"
        static let crossOverProfiles = "ThermalBridge.crossOverProfiles.v1"
        static let crossOverSelectedProfile = "ThermalBridge.crossOverSelectedProfile.v1"
        static let crossOverAutoAttach = "ThermalBridge.crossOverAutoAttach.v1"
        static let processSearch = "ThermalBridge.processSearch.v1"
        static let processShowProtected = "ThermalBridge.processShowProtected.v1"
        static let processSortMode = "ThermalBridge.processSortMode.v1"
        static let processScope = "ThermalBridge.processScope.v1"
        static let automaticThermalConfiguration = "ThermalBridge.automaticThermalConfiguration.v2"
    }

    init() {
        loadPersistence()
        refreshFrontmostApplication()
        refreshThermalState()
        refreshLoginItemStatus()
        installObservers()
        loadingPersistence = false
        if automaticGPURefreshReductionEnabled {
            updateAutomaticDisplayRefreshStatus(
                "Armado; máximo 60 Hz cuando domine la temperatura GPU"
            )
        }
        persistCrossOverProfiles()
        prepareAutomaticThermalMode()
        scanCrossOverEnvironment()
        startMonitoring()
    }

    deinit {
        // Respaldo para cualquier destrucción normal del store que no haya
        // pasado por AppDelegate. Los cierres forzados no ejecutan deinit.
        _ = try? displayRefreshController.restore()
        sessionTelemetryWriter.stop(reason: "store_deinitialized")
        temperatureSensor.stop()
        timer?.cancel()
        crossOverEvaluationWorkItem?.cancel()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    var filteredProcesses: [ProcessSnapshot] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = processes.filter { process in
            let searchMatches = needle.isEmpty || process.searchableText.contains(needle)
            let protectedMatches = showProtected || !isProtected(process)
            let scopeMatches: Bool
            switch processScope {
            case .applications:
                scopeMatches = isUserFacingApplication(process)
                    || isCrossOverGameCandidate(process)
                    || controlledIdentity(process.identity)
            case .crossOver:
                scopeMatches = isCrossOverRelated(process)
            case .controlled:
                scopeMatches = controlledIdentity(process.identity)
            case .all:
                scopeMatches = true
            }
            return searchMatches && protectedMatches && scopeMatches
        }

        if !needle.isEmpty {
            result.sort { lhs, rhs in
                let leftRank = searchRank(lhs, needle: needle)
                let rightRank = searchRank(rhs, needle: needle)
                if leftRank != rightRank { return leftRank > rightRank }
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return stableOrder(for: lhs) < stableOrder(for: rhs)
            }
            return result
        }

        switch sortMode {
        case .stable:
            result.sort { stableOrder(for: $0) < stableOrder(for: $1) }
        case .cpu:
            result.sort { lhs, rhs in
                let left = smoothedCPUByID[lhs.identity] ?? lhs.cpuPercent
                let right = smoothedCPUByID[rhs.identity] ?? rhs.cpuPercent
                if abs(left - right) < 1.5 { return stableOrder(for: lhs) < stableOrder(for: rhs) }
                return left > right
            }
        case .memory:
            result.sort { lhs, rhs in
                let difference = lhs.memoryBytes > rhs.memoryBytes
                    ? lhs.memoryBytes - rhs.memoryBytes
                    : rhs.memoryBytes - lhs.memoryBytes
                if difference < 8 * 1_024 * 1_024 { return stableOrder(for: lhs) < stableOrder(for: rhs) }
                return lhs.memoryBytes > rhs.memoryBytes
            }
        case .name:
            result.sort { lhs, rhs in
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                return comparison == .orderedSame
                    ? stableOrder(for: lhs) < stableOrder(for: rhs)
                    : comparison == .orderedAscending
            }
        case .pid:
            result.sort { $0.pid < $1.pid }
        }
        return result
    }

    var filteredProcessCountText: String {
        let visible = filteredProcesses.count
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(visible) visibles"
            : "\(visible) resultados"
    }

    func resetProcessFilters() {
        searchText = ""
        sortMode = .stable
        processScope = .applications
        showProtected = false
    }

    func stableOrder(for process: ProcessSnapshot) -> Int {
        stableOrderByID[process.identity] ?? Int.max
    }


    private func isUserFacingApplication(_ process: ProcessSnapshot) -> Bool {
        let path = process.path.lowercased()
        guard path.contains(".app/contents/macos/") else { return false }
        let helperContainers = [
            "/contents/frameworks/", "/contents/xpcservices/", "/contents/helpers/",
            "/contents/plugins/", "/contents/library/loginitems/"
        ]
        return !helperContainers.contains { path.contains($0) }
    }

    private func searchRank(_ process: ProcessSnapshot, needle: String) -> Int {
        let name = process.displayName.lowercased()
        let executable = process.normalizedExecutableName
        if name == needle || executable == needle { return 500 }
        if name.hasPrefix(needle) || executable.hasPrefix(needle) { return 400 }
        if name.contains(needle) || executable.contains(needle) { return 300 }
        if process.path.lowercased().contains(needle) { return 200 }
        if process.commandLine.lowercased().contains(needle) { return 100 }
        return 0
    }

    var selectedProcess: ProcessSnapshot? {
        guard let selectedProcessID else { return nil }
        return processes.first { $0.identity == selectedProcessID }
    }

    func processTree(for root: ProcessSnapshot) -> [ProcessSnapshot] {
        var includedPIDs: Set<Int32> = [root.pid]
        var changed = true
        while changed {
            changed = false
            for process in processes where !includedPIDs.contains(process.pid) {
                if includedPIDs.contains(process.parentPID) {
                    includedPIDs.insert(process.pid)
                    changed = true
                }
            }
        }
        return processes.filter { includedPIDs.contains($0.pid) }
    }

    @discardableResult
    func refreshAutomaticResourceEvidence(for root: ProcessSnapshot)
        -> (ProcessTreeResourceMetrics, QoSEvidence) {
        let metrics = ProcessTreeResourceMetrics.aggregate(
            tree: processTree(for: root),
            deltas: latestProcessResourceDeltas
        )
        let requestedClass: EffectiveQoSClass? = {
            switch lastCrossOverRequestedQoSClamp {
            case .utility?: return .utility
            case .background?: return .background
            case .maintenance?: return .maintenance
            case nil: return nil
            }
        }()
        let evidence = QoSEvidence.evaluate(
            requestedClass: requestedClass,
            requestAccepted: lastCrossOverQoSRequestAccepted,
            requestFailed: lastCrossOverQoSRequestFailed,
            metrics: metrics
        )
        automaticTreeResourceMetrics = metrics
        automaticQoSEvidence = evidence
        return (metrics, evidence)
    }

    func treeCPUValue(for root: ProcessSnapshot) -> Double {
        processTree(for: root).reduce(0) { $0 + $1.cpuPercent }
    }

    func treeCPUText(for root: ProcessSnapshot) -> String {
        String(format: "%.1f %%", treeCPUValue(for: root))
    }

    func treeProcessCount(for root: ProcessSnapshot) -> Int {
        processTree(for: root).count
    }

    var controlledCount: Int {
        backgroundIDs.union(suspendedIDs).union(lowPriorityIDs).union(Set(cpuLimitByID.keys)).count
    }

    var totalCPUValue: Double {
        processes.reduce(0) { $0 + $1.cpuPercent }
    }

    var totalCPUText: String {
        String(format: "%.1f %%", totalCPUValue)
    }

    var cpuLimiterCount: Int { cpuLimitByID.count }

    var selectedCrossOverProfile: CrossOverProfile? {
        guard let selectedCrossOverProfileID else { return nil }
        return crossOverProfiles.first { $0.id == selectedCrossOverProfileID }
    }

    var activeCrossOverProfile: CrossOverProfile? {
        guard let activeCrossOverProfileID else { return nil }
        return crossOverProfiles.first { $0.id == activeCrossOverProfileID }
    }

    var activeCrossOverProcess: ProcessSnapshot? {
        guard let activeCrossOverProcessID else { return nil }
        return process(for: activeCrossOverProcessID)
    }

    var runningCrossOverProcesses: [ProcessSnapshot] {
        processes
            .filter(isCrossOverRelated)
            .sorted { lhs, rhs in
                if lhs.identity == activeCrossOverProcessID { return true }
                if rhs.identity == activeCrossOverProcessID { return false }
                let leftRole = crossOverRoleRank(lhs)
                let rightRole = crossOverRoleRank(rhs)
                if leftRole != rightRole { return leftRole < rightRole }
                return stableOrder(for: lhs) < stableOrder(for: rhs)
            }
    }

    var crossOverGameCandidates: [ProcessSnapshot] {
        runningCrossOverProcesses.filter(isCrossOverGameCandidate)
    }

    /// Procesos que pueden seleccionarse manualmente cuando CrossOver oculta el
    /// nombre del .exe o cuando el árbol no deja evidencia suficiente para ser
    /// reconocido. La selección manual muestra todos los procesos no protegidos;
    /// los relacionados con CrossOver se ordenan primero y la autoaplicación
    /// continúa descartando candidatos ambiguos salvo confirmación explícita.
    var crossOverSelectableProcesses: [ProcessSnapshot] {
        processes.filter(isCrossOverSelectableProcess)
    }

    func isCrossOverRelated(_ process: ProcessSnapshot) -> Bool {
        process.hasDirectCrossOverRuntimeEvidence
            || processTopologyIndex.hasCrossOverRuntimeAncestor(of: process)
    }

    private func hasCrossOverRuntimeAncestor(_ process: ProcessSnapshot) -> Bool {
        processTopologyIndex.hasCrossOverRuntimeAncestor(of: process)
    }

    func isCrossOverInfrastructure(_ process: ProcessSnapshot) -> Bool {
        let name = process.displayName.lowercased()
        let exact: Set<String> = [
            "crossover", "cxstart", "wine", "wine64", "wine-preloader", "wine64-preloader",
            "wineserver", "wineserver64", "services.exe", "explorer.exe", "plugplay.exe",
            "rpcss.exe", "winedevice.exe", "conhost.exe", "start.exe", "rundll32.exe",
            "svchost.exe", "tabtip.exe", "cmd.exe", "reg.exe", "regsvr32.exe",
            "wineboot.exe", "winecfg.exe", "winemenubuilder.exe", "winedbg.exe"
        ]
        return exact.contains(name)
    }

    func isCrossOverLauncher(_ process: ProcessSnapshot) -> Bool {
        let name = process.displayName.lowercased()
        let launcherNames: Set<String> = [
            "steam.exe", "steamwebhelper.exe", "epicgameslauncher.exe", "epicwebhelper.exe",
            "eadesktop.exe", "ealauncher.exe", "eabackgroundservice.exe", "ubisoftconnect.exe",
            "upc.exe", "galaxyclient.exe", "galaxyclient helper.exe", "battle.net.exe",
            "agent.exe", "rockstargameslauncher.exe", "socialclubhelper.exe", "goggalaxy.exe"
        ]
        return launcherNames.contains(name)
            || name.contains("steamwebhelper")
            || name.contains("epicwebhelper")
            || name.contains("launcher")
    }

    func isCrossOverHelper(_ process: ProcessSnapshot) -> Bool {
        let name = process.displayName.lowercased()
        let helperTokens = [
            "crashpad", "crashreport", "cefsubprocess", "webview", "overlay",
            "helper.exe", "updater.exe", "update.exe", "unins", "diagnostic",
            "anticheat", "easyanticheat", "battleye", "vc_redist", "dotnet"
        ]
        return helperTokens.contains { name.contains($0) }
    }

    func isCrossOverGameCandidate(_ process: ProcessSnapshot) -> Bool {
        let executableLike = process.normalizedExecutableName.hasSuffix(".exe")
            || process.windowsExecutableName != nil
        return isCrossOverRelated(process)
            && executableLike
            && !isCrossOverInfrastructure(process)
            && !isCrossOverLauncher(process)
            && !isCrossOverHelper(process)
            && !isProtected(process)
    }

    func isCrossOverSelectableProcess(_ process: ProcessSnapshot) -> Bool {
        !isProtected(process)
    }

    func crossOverRoleLabel(_ process: ProcessSnapshot) -> String {
        if isCrossOverGameCandidate(process) { return "Juego" }
        if isCrossOverLauncher(process) { return "Launcher" }
        if isCrossOverHelper(process) { return "Ayudante" }
        return "Infraestructura"
    }

    private func crossOverRoleRank(_ process: ProcessSnapshot) -> Int {
        if isCrossOverGameCandidate(process) { return 0 }
        if isCrossOverLauncher(process) { return 1 }
        if isCrossOverHelper(process) { return 2 }
        return 3
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let snapshots = self.sampler.sample()
            self.samplingCounter += 1
            if self.samplingCounter == 1 || self.samplingCounter % 2 == 0 {
                self.cachedSystemMetrics = self.systemMetricsSampler.sample()
            }
            let metrics = self.cachedSystemMetrics
            DispatchQueue.main.async { [weak self] in
                self?.acceptSample(snapshots, metrics: metrics)
            }
        }
        self.timer = timer
        timer.resume()
        addLog("Monitorización iniciada.")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        timer?.cancel()
        timer = nil
        isMonitoring = false
        addLog("Monitorización pausada.")
    }

    func toggleMonitoring() {
        isMonitoring ? stopMonitoring() : startMonitoring()
    }

    func refreshNow() {
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let snapshots = self.sampler.sample()
            let metrics = self.systemMetricsSampler.sample()
            self.cachedSystemMetrics = metrics
            DispatchQueue.main.async { [weak self] in
                self?.acceptSample(snapshots, metrics: metrics)
            }
        }
    }

    func selectForHistory(_ process: ProcessSnapshot) {
        let changed = selectedProcessID != process.identity
        selectedProcessID = process.identity
        selectedProcessHistory = processHistory[process.identity] ?? []
        if changed {
            selectedTreeCPUHistory.removeAll()
        }
    }

    func isProtected(_ process: ProcessSnapshot) -> Bool {
        if process.pid <= 1 || process.pid == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if !process.path.isEmpty && process.path.hasPrefix(Bundle.main.bundlePath) {
            return true
        }

        let protectedNames: Set<String> = [
            "launchd", "loginwindow", "WindowServer", "Dock", "Finder", "SystemUIServer",
            "ControlCenter", "coreaudiod", "runningboardd", "tccd", "trustd", "secd",
            "cfprefsd", "distnoted", "notifyd", "powerd", "thermalmonitord", "UserEventAgent",
            "ThermalBridge", "TBWatchdog", "TBCPULimiter", "TBLimiterGuardian"
        ]
        if protectedNames.contains(process.displayName) {
            return true
        }

        let protectedPrefixes = [
            "/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"
        ]
        return protectedPrefixes.contains { process.path.hasPrefix($0) }
    }

    func stateText(for process: ProcessSnapshot) -> String {
        var states: [String] = []
        if suspendedIDs.contains(process.identity) { states.append("Suspendido") }
        if let limit = cpuLimitByID[process.identity] { states.append("Actividad \(limit)% · árbol") }
        if gpuGuardEnabled && gpuGuardProcessID == process.identity { states.append("GPU Guard") }
        if activeCrossOverProcessID == process.identity, let profile = activeCrossOverProfile { states.append("CrossOver: \(profile.name)") }
        if backgroundIDs.contains(process.identity) { states.append("Fondo") }
        if lowPriorityIDs.contains(process.identity) || process.niceValue >= 10 { states.append("Nice \(process.niceValue)") }
        if isProtected(process) { states.append("Protegido") }
        return states.isEmpty ? "Normal" : states.joined(separator: " · ")
    }

    func hasBackgroundRequest(_ process: ProcessSnapshot, source: String = "manual") -> Bool {
        backgroundSources[process.identity]?.contains(source) == true
    }

    func hasCPULimitRequest(_ process: ProcessSnapshot, source: String = "manual") -> Bool {
        cpuLimitSources[process.identity]?[source] != nil
    }

    func setBackground(_ process: ProcessSnapshot, enabled: Bool, source: String = "manual") {
        guard !enabled || validateControllable(process) else { return }
        updateBackgroundRequest(process, sourceKey: source, enabled: enabled)
    }

    func applyLowPriority(_ process: ProcessSnapshot, source: String = "manual") {
        guard validateControllable(process) else { return }
        let attemptKey = "\(process.identity.description)|\(source)"
        guard lowPriorityAttempts.insert(attemptKey).inserted else { return }

        controlQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.controller.applyLowPriority(process)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lowPriorityIDs.insert(process.identity)
                    self.addLog("\(process.displayName): prioridad reducida a nice +10 (\(source)).")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.addLog("\(process.displayName): \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    func setCPULimit(_ process: ProcessSnapshot,
                     percent: Int?,
                     source: String = "manual") {
        guard percent == nil || validateControllable(process) else { return }
        let clamped = percent.map { min(max($0, 10), 100) }
        updateCPULimitRequest(process, sourceKey: source, percent: clamped)
    }

    func suspend(_ process: ProcessSnapshot) {
        guard validateControllable(process) else { return }
        guard !suspendedIDs.contains(process.identity) else { return }

        clearAllCPULimitRequests(for: process)
        do {
            let watchdog = try controller.suspend(process, timeoutSeconds: suspensionTimeoutSeconds)
            let identity = process.identity
            let displayName = process.displayName
            watchdog.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.suspendedIDs.contains(identity) else { return }
                    self.suspendedIDs.remove(identity)
                    self.watchdogs.removeValue(forKey: identity)
                    self.addLog("\(displayName): reanudado automáticamente por el watchdog.")
                    self.evaluateAutomations()
                }
            }
            watchdogs[process.identity] = watchdog
            suspendedIDs.insert(process.identity)
            addLog("\(process.displayName): suspendido. Reanudación de seguridad en \(suspensionTimeoutSeconds) s.")
        } catch {
            addLog("\(process.displayName): \(error.localizedDescription)", isError: true)
        }
    }

    func resume(_ process: ProcessSnapshot) {
        do {
            try controller.resume(process)
            watchdogs[process.identity]?.terminate()
            watchdogs.removeValue(forKey: process.identity)
            suspendedIDs.remove(process.identity)
            addLog("\(process.displayName): reanudado.")
            evaluateAutomations()
        } catch {
            addLog("\(process.displayName): \(error.localizedDescription)", isError: true)
        }
    }

    func addRule(for process: ProcessSnapshot, action: RuleAction) {
        let duplicate = rules.contains {
            $0.nameContains.caseInsensitiveCompare(process.displayName) == .orderedSame && $0.action == action
        }
        guard !duplicate else {
            addLog("Ya existe una regla equivalente para \(process.displayName).")
            return
        }
        rules.append(ProcessRule(enabled: true,
                                 nameContains: process.displayName,
                                 pathContains: "",
                                 trigger: .whileRunning,
                                 action: action,
                                 cpuLimitPercent: 80))
        addLog("Regla creada para \(process.displayName): \(action.title).")
        evaluateAutomations()
    }

    func addBlankRule() {
        rules.append(ProcessRule())
    }

    func removeRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        evaluateAutomations()
    }

    func addThermalTarget(for process: ProcessSnapshot, percent: Int = 80) {
        let duplicate = thermalTargets.contains {
            $0.nameContains.caseInsensitiveCompare(process.displayName) == .orderedSame
        }
        guard !duplicate else {
            addLog("\(process.displayName) ya es un objetivo térmico.")
            return
        }
        thermalTargets.append(ThermalTarget(enabled: true,
                                            nameContains: process.displayName,
                                            pathContains: "",
                                            cpuLimitPercent: percent))
        addLog("\(process.displayName): añadido como objetivo térmico.")
        evaluateAutomations()
    }

    func addBlankThermalTarget() {
        thermalTargets.append(ThermalTarget())
    }

    func removeThermalTargets(at offsets: IndexSet) {
        thermalTargets.remove(atOffsets: offsets)
        evaluateAutomations()
    }

    func removeThermalTarget(id: UUID) {
        thermalTargets.removeAll { $0.id == id }
        evaluateAutomations()
    }

    func scanCrossOverEnvironment() {
        guard !isScanningCrossOver else { return }
        isScanningCrossOver = true
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.crossOverDiscovery.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.crossOverInstallations = result.installations
                self.crossOverBottles = result.bottles
                self.lastCrossOverScanDate = Date()
                self.isScanningCrossOver = false
                self.addLog("CrossOver: detectadas \(result.installations.count) instalaciones y \(result.bottles.count) botellas.")
            }
        }
    }

    func addCrossOverProfile(preset: CrossOverPreset = .custom) {
        var profile = CrossOverProfile.presetProfile(preset)
        if preset == .custom {
            profile.name = "Nuevo perfil"
        }
        crossOverProfiles.append(profile)
        selectedCrossOverProfileID = profile.id
        addLog("CrossOver: perfil \(profile.name) creado.")
    }

    func duplicateCrossOverProfile(id: UUID) {
        guard var copy = crossOverProfiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " copia"
        copy.preset = .custom
        crossOverProfiles.append(copy)
        selectedCrossOverProfileID = copy.id
        addLog("CrossOver: perfil duplicado como \(copy.name).")
    }

    func removeCrossOverProfile(id: UUID) {
        if activeCrossOverProfileID == id {
            stopCrossOverProfile(clearAutoAttach: true)
        }
        crossOverProfiles.removeAll { $0.id == id }
        if selectedCrossOverProfileID == id {
            selectedCrossOverProfileID = crossOverProfiles.first?.id
        }
        addLog("CrossOver: perfil eliminado.")
    }

    func applyCrossOverPreset(_ preset: CrossOverPreset, to id: UUID) {
        guard let index = crossOverProfiles.firstIndex(where: { $0.id == id }) else { return }
        let originalName = crossOverProfiles[index].name
        let executable = crossOverProfiles[index].executableContains
        let path = crossOverProfiles[index].pathContains
        let bottle = crossOverProfiles[index].bottleName
        let autoAttach = crossOverProfiles[index].autoAttach
        let enabled = crossOverProfiles[index].enabled
        crossOverProfiles[index].applyPreset(preset)
        crossOverProfiles[index].name = originalName
        crossOverProfiles[index].executableContains = executable
        crossOverProfiles[index].pathContains = path
        crossOverProfiles[index].bottleName = bottle
        crossOverProfiles[index].autoAttach = autoAttach
        crossOverProfiles[index].enabled = enabled
        addLog("CrossOver: preset \(preset.title) aplicado sin cambiar el nombre ni el juego capturado.")
    }

    func captureCrossOverProcess(_ process: ProcessSnapshot, for profileID: UUID) {
        guard isCrossOverGameCandidate(process) else {
            addLog("CrossOver: \(process.displayName) no parece ser el ejecutable principal del juego.", isError: true)
            return
        }
        guard let index = crossOverProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        let executable = process.windowsExecutableName ?? process.displayName
        crossOverProfiles[index].executableContains = executable
        if let bottle = process.crossOverBottleName, !bottle.isEmpty {
            crossOverProfiles[index].bottleName = bottle
        }
        // No se guarda automáticamente la ruta del binario Wine: cambia entre versiones
        // de CrossOver y puede hacer que varios juegos coincidan con el mismo perfil.
        if crossOverProfiles[index].pathContains.lowercased().contains("crossover.app")
            || crossOverProfiles[index].pathContains.lowercased().contains("wine") {
            crossOverProfiles[index].pathContains = ""
        }
        selectedCrossOverProfileID = profileID
        selectedProcessID = process.identity
        selectForHistory(process)
        addLog("CrossOver: \(executable) capturado para \(crossOverProfiles[index].name)\(process.crossOverBottleName.map { " en la botella \($0)" } ?? "").")
    }

    func activateCrossOverProfile(profileID: UUID, processID: ProcessIdentity? = nil) {
        guard let profile = crossOverProfiles.first(where: { $0.id == profileID }), profile.enabled else {
            addLog("CrossOver: el perfil no existe o está desactivado.", isError: true)
            return
        }
        guard profile.hasTarget || processID != nil else {
            crossOverStatus = "Captura primero el ejecutable del juego"
            addLog("CrossOver: \(profile.name) no tiene un ejecutable definido.", isError: true)
            return
        }
        let chosen: ProcessSnapshot?
        if let processID, let explicit = process(for: processID), isCrossOverGameCandidate(explicit) {
            if profile.hasTarget && !profile.matches(explicit) {
                crossOverStatus = "El proceso seleccionado no coincide con el perfil"
                addLog("CrossOver: captura \(explicit.displayName) antes de aplicar \(profile.name), o usa selección automática.", isError: true)
                return
            }
            chosen = explicit
        } else {
            chosen = bestCrossOverMatch(for: profile)
        }
        guard let chosen else {
            crossOverStatus = "Esperando un proceso que coincida con \(profile.name)"
            addLog("CrossOver: no hay un juego coincidente para \(profile.name).", isError: true)
            return
        }
        activateCrossOverProfile(profile, root: chosen, autoAttached: false)
    }

    func stopCrossOverProfile(clearAutoAttach: Bool = false) {
        performCrossOverMutation {
            stopCrossOverProfileInternal(clearAutoAttach: clearAutoAttach)
        }
        scheduleCrossOverEvaluation()
    }

    private func stopCrossOverProfileInternal(clearAutoAttach: Bool) {
        let previousName = activeCrossOverProfile?.name
        clearCrossOverProfileRequests()
        if gpuGuardOwnedByCrossOverProfile {
            stopGPUGuard()
        }
        gpuGuardOwnedByCrossOverProfile = false
        activeCrossOverProfileID = nil
        activeCrossOverProcessID = nil
        activeCrossOverWasAutoAttached = false
        if clearAutoAttach && crossOverAutoAttachEnabled {
            crossOverAutoAttachEnabled = false
        }
        crossOverStatus = crossOverAutoAttachEnabled
            ? "Autoaplicación armada; esperando proceso"
            : "Sin perfil activo"
        if let previousName {
            addLog("CrossOver: perfil \(previousName) detenido y controles liberados.")
        }
    }

    func openCrossOverInstallation(_ installation: CrossOverInstallation) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: installation.path),
                                           configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                DispatchQueue.main.async { [weak self] in
                    self?.addLog("CrossOver: no se pudo abrir la aplicación: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    func revealCrossOverBottle(_ bottle: CrossOverBottle) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bottle.path)])
    }

    var gpuUtilizationText: String {
        guard let gpuUtilization else { return "No disponible" }
        return String(format: "%.1f %%", gpuUtilization)
    }

    var rendererUtilizationText: String {
        guard let rendererUtilization else { return "—" }
        return String(format: "%.1f %%", rendererUtilization)
    }

    var tilerUtilizationText: String {
        guard let tilerUtilization else { return "—" }
        return String(format: "%.1f %%", tilerUtilization)
    }

    var gpuMemoryText: String {
        guard let gpuMemoryBytes else { return "No disponible" }
        return ByteCountFormatter.string(fromByteCount: Int64(gpuMemoryBytes), countStyle: .memory)
    }

    var selectedTreeCPUText: String {
        guard let selectedProcess else { return "—" }
        return treeCPUText(for: selectedProcess)
    }

    var gpuAverage60Text: String {
        formattedAverage(points: gpuHistory, seconds: 60)
    }

    var gpuMaximumText: String {
        guard let maximum = gpuHistory.map(\.value).max() else { return "—" }
        return String(format: "%.1f %%", maximum)
    }

    var gpuGuardProcess: ProcessSnapshot? {
        guard let gpuGuardProcessID else { return nil }
        return process(for: gpuGuardProcessID)
    }

    var lastPowerCPUText: String { wattsText(lastPowerSnapshot?.cpuWatts) }
    var lastPowerGPUText: String { wattsText(lastPowerSnapshot?.gpuWatts) }
    var lastPowerTotalText: String { wattsText(lastPowerSnapshot?.totalWatts) }

    func startGPUGuard(for process: ProcessSnapshot) {
        guard validateControllable(process) else { return }
        if let previousID = gpuGuardProcessID,
           previousID != process.identity,
           let previous = self.process(for: previousID) {
            updateCPULimitRequest(previous, sourceKey: gpuGuardSourceKey, percent: nil)
        }
        gpuGuardProcessID = process.identity
        gpuGuardEnabled = true
        gpuGuardCurrentActivityPercent = 100
        gpuGuardHighSamples = 0
        gpuGuardLowSamples = 0
        lastGPUGuardEvaluation = .distantPast
        gpuGuardStatus = "Observando GPU y estado térmico"
        addLog("\(process.displayName): GPU Guard indirecto activado.")
        evaluateGPUGuard(force: true)
    }

    func stopGPUGuard() {
        if let identity = gpuGuardProcessID, let process = process(for: identity) {
            updateCPULimitRequest(process, sourceKey: gpuGuardSourceKey, percent: nil)
            addLog("\(process.displayName): GPU Guard desactivado.")
        }
        gpuGuardEnabled = false
        gpuGuardProcessID = nil
        gpuGuardCurrentActivityPercent = 100
        gpuGuardHighSamples = 0
        gpuGuardLowSamples = 0
        gpuGuardStatus = "Inactivo"
    }

    func capturePowerSnapshot() {
        guard !isCapturingPower else { return }
        isCapturingPower = true
        addLog("Iniciando captura de potencia con powermetrics; macOS solicitará autorización.")
        controlQueue.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.powerMetricsSampler.capture()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lastPowerSnapshot = snapshot
                    self.isCapturingPower = false
                    self.addLog("Potencia capturada: CPU \(self.wattsText(snapshot.cpuWatts)), GPU \(self.wattsText(snapshot.gpuWatts)), total \(self.wattsText(snapshot.totalWatts)).")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isCapturingPower = false
                    self?.addLog(error.localizedDescription, isError: true)
                }
            }
        }
    }

    func exportTelemetryCSV() {
        guard !telemetryRecords.isEmpty else {
            addLog("No hay telemetría para exportar.", isError: true)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exportar telemetría de ThermalBridge"
        panel.nameFieldStringValue = "ThermalBridge_telemetria.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,total_cpu_percent,selected_tree_cpu_percent,gpu_percent,renderer_percent,tiler_percent,gpu_guard_activity_percent,thermal_state"]
        rows.reserveCapacity(telemetryRecords.count + 1)
        for record in telemetryRecords {
            rows.append([
                formatter.string(from: record.date),
                csvNumber(record.totalCPUPercent),
                csvNumber(record.selectedTreeCPUPercent),
                csvNumber(record.gpuPercent),
                csvNumber(record.rendererPercent),
                csvNumber(record.tilerPercent),
                record.gpuActivityLimitPercent.map { String($0) } ?? "",
                record.thermalState.rawValue
            ].joined(separator: ","))
        }

        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            addLog("Telemetría exportada a \(url.path).")
        } catch {
            addLog("No se pudo exportar la telemetría: \(error.localizedDescription)", isError: true)
        }
    }

    func clearTelemetry() {
        telemetryRecords.removeAll()
        gpuHistory.removeAll()
        selectedTreeCPUHistory.removeAll()
        gpuGuardActivityHistory.removeAll()
        systemCPUHistory.removeAll()
        selectedProcessHistory.removeAll()
        processHistory.removeAll()
        addLog("Historial de telemetría limpiado.")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
            addLog("Inicio de sesión: \(launchAtLoginEnabled ? "activado" : "desactivado").")
        } catch {
            refreshLoginItemStatus()
            addLog("No se pudo cambiar el inicio de sesión: \(error.localizedDescription)", isError: true)
        }
    }

    func refreshLoginItemStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func restoreAll(preserveAutomations: Bool = false) {
        if automaticThermalEnabled {
            stopAutomaticThermalControl(keepAutoAttach: preserveAutomations)
        }
        restoreDisplayRefreshSafety(reason: "application_terminating")
        stopCrossOverProfile(clearAutoAttach: !preserveAutomations)
        let currentByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.identity, $0) })

        for identity in suspendedIDs {
            if let process = currentByID[identity] {
                try? controller.resume(process)
            } else if tb_identity_matches(identity.pid, identity.startID) == 1 {
                _ = tb_send_signal(identity.pid, SIGCONT)
            }
            watchdogs[identity]?.terminate()
        }
        watchdogs.removeAll()
        suspendedIDs.removeAll()

        for (identity, limiter) in cpuLimiters {
            limiter.terminate()
            if let root = currentByID[identity] {
                resumeProcessTreeSafety(root)
            } else if tb_identity_matches(identity.pid, identity.startID) == 1 {
                _ = tb_send_signal(identity.pid, SIGCONT)
            }
            cpuLimiterGuardians[identity]?.terminate()
            controller.removeCPULimiterControl(for: identity)
        }
        for guardian in cpuLimiterGuardians.values {
            guardian.terminate()
        }
        cpuLimiters.removeAll()
        cpuLimiterGuardians.removeAll()
        cpuLimitSources.removeAll()
        cpuLimitModeSources.removeAll()
        cpuLimiterModeByID.removeAll()
        cpuLimitByID.removeAll()
        gpuGuardEnabled = false
        gpuGuardProcessID = nil
        gpuGuardCurrentActivityPercent = 100
        gpuGuardStatus = "Inactivo"

        let identitiesToRestore = Set(backgroundSources.keys)
            .union(backgroundIDs)
            .union(backgroundSnapshots.keys)
        let backgroundTargets = ProcessRestorationResolver.targets(
            for: identitiesToRestore,
            current: processes,
            cached: backgroundSnapshots
        )
        backgroundSources.removeAll()
        backgroundTokens.removeAll()
        var failedBackgroundRestorations = Set<ProcessIdentity>()
        // Drena primero cualquier aplicación pendiente. La restauración queda
        // al final de la misma cola FIFO y ninguna solicitud anterior puede
        // volver a activar la política después de este punto.
        controlQueue.sync {
            for process in backgroundTargets where controller.identityStillMatches(process) {
                do {
                    try controller.setBackground(process, enabled: false)
                } catch {
                    failedBackgroundRestorations.insert(process.identity)
                }
            }
        }
        backgroundSnapshots = backgroundSnapshots.filter {
            failedBackgroundRestorations.contains($0.key)
        }
        backgroundIDs = failedBackgroundRestorations
        if !failedBackgroundRestorations.isEmpty {
            addLog("No se pudo restaurar Darwin Background en \(failedBackgroundRestorations.count) procesos.", isError: true)
        }

        if !lowPriorityIDs.isEmpty {
            addLog("Las prioridades nice reducidas no se restauran sin privilegios; vuelven a la normalidad al cerrar esos procesos.", isError: true)
        }
        addLog("Controles reversibles restaurados.")
    }

    func clearLog() {
        logEntries.removeAll()
    }

    private func loadPersistence() {
        searchText = UserDefaults.standard.string(forKey: Keys.processSearch) ?? ""
        if UserDefaults.standard.object(forKey: Keys.processShowProtected) != nil {
            showProtected = UserDefaults.standard.bool(forKey: Keys.processShowProtected)
        } else {
            showProtected = false
        }
        if let rawSort = UserDefaults.standard.string(forKey: Keys.processSortMode),
           let savedSort = SortMode(rawValue: rawSort) {
            sortMode = savedSort
        } else {
            sortMode = .stable
        }

        if let rawScope = UserDefaults.standard.string(forKey: Keys.processScope),
           let savedScope = ProcessScope(rawValue: rawScope) {
            processScope = savedScope
        } else {
            processScope = .applications
        }

        if let data = UserDefaults.standard.data(forKey: Keys.rules),
           let decoded = try? JSONDecoder().decode([ProcessRule].self, from: data) {
            rules = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Keys.thermalTargets),
           let decoded = try? JSONDecoder().decode([ThermalTarget].self, from: data) {
            thermalTargets = decoded
        }

        let savedTimeout = UserDefaults.standard.integer(forKey: Keys.suspensionTimeout)
        if savedTimeout >= 5 { suspensionTimeoutSeconds = savedTimeout }

        thermalAutomationEnabled = UserDefaults.standard.bool(forKey: Keys.thermalEnabled)
        if let raw = UserDefaults.standard.string(forKey: Keys.thermalThreshold),
           let threshold = ThermalThreshold(rawValue: raw) {
            thermalThreshold = threshold
        }

        let savedCycle = UserDefaults.standard.integer(forKey: Keys.limiterCycle)
        if savedCycle >= 20 && savedCycle <= 500 { limiterCycleMilliseconds = savedCycle }

        if UserDefaults.standard.object(forKey: Keys.automaticMacPolicyEnabled) != nil {
            automaticMacPolicyEnabled = UserDefaults.standard.bool(forKey: Keys.automaticMacPolicyEnabled)
        } else {
            automaticMacPolicyEnabled = true
        }
        if UserDefaults.standard.object(forKey: Keys.automaticPowerAnticipationEnabled) != nil {
            automaticPowerAnticipationEnabled = UserDefaults.standard.bool(forKey: Keys.automaticPowerAnticipationEnabled)
        } else {
            automaticPowerAnticipationEnabled = true
        }
        if UserDefaults.standard.object(forKey: Keys.automaticAudioProtectionEnabled) != nil {
            automaticAudioProtectionEnabled = UserDefaults.standard.bool(forKey: Keys.automaticAudioProtectionEnabled)
        } else {
            automaticAudioProtectionEnabled = true
        }
        if UserDefaults.standard.object(forKey: Keys.automaticEmergencyBackgroundEnabled) != nil {
            automaticEmergencyBackgroundEnabled = UserDefaults.standard.bool(forKey: Keys.automaticEmergencyBackgroundEnabled)
        } else {
            automaticEmergencyBackgroundEnabled = false
        }
        // RC3.5 conserva retirada la integración experimental de Game
        // Mode y limpia la preferencia que podía quedar guardada por Beta 10.
        UserDefaults.standard.removeObject(
            forKey: "ThermalBridge.automaticGameModeEnabled.beta10"
        )
        if UserDefaults.standard.object(forKey: Keys.automaticGPURefreshReductionEnabled) != nil {
            automaticGPURefreshReductionEnabled = UserDefaults.standard.bool(
                forKey: Keys.automaticGPURefreshReductionEnabled
            )
        } else {
            automaticGPURefreshReductionEnabled = false
        }
        let savedClamp = UserDefaults.standard.integer(forKey: Keys.crossOverLaunchQoSClamp)
        crossOverLaunchQoSClamp = MacLaunchQoSClamp(rawValue: savedClamp) ?? .utility

        let savedTarget = UserDefaults.standard.integer(forKey: Keys.gpuGuardTarget)
        if savedTarget >= 40 && savedTarget <= 95 { gpuGuardTargetPercent = savedTarget }
        let savedMinimum = UserDefaults.standard.integer(forKey: Keys.gpuGuardMinimum)
        if savedMinimum >= 20 && savedMinimum <= 95 { gpuGuardMinimumActivityPercent = savedMinimum }
        let savedStep = UserDefaults.standard.integer(forKey: Keys.gpuGuardStep)
        if savedStep >= 5 && savedStep <= 20 { gpuGuardStepPercent = savedStep }
        gpuGuardAllowsRecovery = UserDefaults.standard.bool(forKey: Keys.gpuGuardRecovery)

        if let data = UserDefaults.standard.data(forKey: Keys.crossOverProfiles),
           let decoded = try? JSONDecoder().decode([CrossOverProfile].self, from: data),
           !decoded.isEmpty {
            crossOverProfiles = decoded
        } else {
            crossOverProfiles = [
                .presetProfile(.performance),
                .presetProfile(.balanced),
                .presetProfile(.cool),
                .presetProfile(.compatibility)
            ]
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.crossOverSelectedProfile),
           let selected = UUID(uuidString: raw),
           crossOverProfiles.contains(where: { $0.id == selected }) {
            selectedCrossOverProfileID = selected
        } else {
            selectedCrossOverProfileID = crossOverProfiles.first(where: { $0.preset == .balanced })?.id
                ?? crossOverProfiles.first?.id
        }
        crossOverAutoAttachEnabled = UserDefaults.standard.bool(forKey: Keys.crossOverAutoAttach)
    }

    private func persistRules() {
        guard !loadingPersistence else { return }
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: Keys.rules)
        evaluateAutomations()
    }

    private func persistThermalTargets() {
        guard !loadingPersistence else { return }
        guard let data = try? JSONEncoder().encode(thermalTargets) else { return }
        UserDefaults.standard.set(data, forKey: Keys.thermalTargets)
        evaluateAutomations()
    }

    private func persistCrossOverProfiles() {
        guard !loadingPersistence else { return }
        guard let data = try? JSONEncoder().encode(crossOverProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Keys.crossOverProfiles)
        if let activeCrossOverProfileID,
           !crossOverProfiles.contains(where: { $0.id == activeCrossOverProfileID }) {
            stopCrossOverProfile(clearAutoAttach: false)
        } else {
            scheduleCrossOverEvaluation()
        }
    }

    private func installObservers() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFrontmostApplication()
            self?.evaluateAutomations()
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshThermalState()
            self?.evaluateAutomations()
        }
    }

    private func refreshFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        frontmostPID = app.processIdentifier
        frontmostName = app.localizedName ?? "PID \(app.processIdentifier)"
    }

    private func acceptSample(_ rawSnapshots: [ProcessSnapshot], metrics: SystemMetricsSample) {
        let snapshots = processObservationCache.merge(
            current: rawSnapshots,
            now: Date(),
            graceInterval: processObservationGraceInterval,
            shouldRetain: { [self] snapshot in
                snapshot.identity == automaticThermalProcessID
                    || snapshot.identity == automaticThermalPreferredProcessID
                    || automaticThermalSessionIDs.contains(snapshot.identity)
                    || selectedProcessID == snapshot.identity
                    || isCrossOverRelated(snapshot)
            },
            isIdentityAlive: { identity in
                tb_identity_matches(identity.pid, identity.startID) != 0
            }
        )
        let currentIDs = Set(snapshots.map(\.identity))
        let newProcesses = snapshots
            .filter { stableOrderByID[$0.identity] == nil }
            .sorted { lhs, rhs in
                let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                return comparison == .orderedSame ? lhs.pid < rhs.pid : comparison == .orderedAscending
            }
        for process in newProcesses {
            stableOrderByID[process.identity] = nextStableOrder
            nextStableOrder += 1
        }
        stableOrderByID = stableOrderByID.filter { currentIDs.contains($0.key) }
        smoothedCPUByID = smoothedCPUByID.filter { currentIDs.contains($0.key) }
        for process in snapshots {
            let previous = smoothedCPUByID[process.identity] ?? process.cpuPercent
            smoothedCPUByID[process.identity] = (previous * 0.65) + (process.cpuPercent * 0.35)
        }

        knownIdentities = currentIDs
        processes = snapshots
        processTopologyIndex = ProcessTopologyIndex(processes: snapshots)
        latestProcessResourceDeltas = processResourceObservationCache.update(snapshots)
        gpuUtilization = metrics.gpuUtilization
        rendererUtilization = metrics.rendererUtilization
        tilerUtilization = metrics.tilerUtilization
        gpuMemoryBytes = metrics.gpuMemoryBytes
        gpuMetricsSource = metrics.source
        refreshThermalState()
        appendHistory(snapshots, metrics: metrics)

        lowPriorityIDs.formIntersection(currentIDs)

        for process in snapshots where backgroundSnapshots[process.identity] != nil {
            backgroundSnapshots[process.identity] = process
        }
        let trackedBackgroundIDs = Set(backgroundSources.keys)
            .union(backgroundIDs)
            .union(backgroundSnapshots.keys)
        for identity in trackedBackgroundIDs.subtracting(currentIDs) {
            if let cached = backgroundSnapshots[identity],
               controller.identityStillMatches(cached) {
                // El censo puede omitir un proceso vivo. Conserva la evidencia
                // necesaria para retirar Darwin Background al cerrar.
                continue
            }
            backgroundSources.removeValue(forKey: identity)
            backgroundTokens.removeValue(forKey: identity)
            backgroundSnapshots.removeValue(forKey: identity)
            backgroundIDs.remove(identity)
        }
        for identity in Set(cpuLimitSources.keys).subtracting(currentIDs) {
            cpuLimitSources.removeValue(forKey: identity)
            cpuLimitModeSources.removeValue(forKey: identity)
            cpuLimiterModeByID.removeValue(forKey: identity)
            cpuLimiters[identity]?.terminate()
            cpuLimiters.removeValue(forKey: identity)
            cpuLimiterGuardians[identity]?.terminate()
            cpuLimiterGuardians.removeValue(forKey: identity)
            controller.removeCPULimiterControl(for: identity)
            cpuLimitByID.removeValue(forKey: identity)
        }

        let endedSuspensions = suspendedIDs.subtracting(currentIDs)
        for identity in endedSuspensions {
            watchdogs[identity]?.terminate()
            watchdogs.removeValue(forKey: identity)
        }
        suspendedIDs.formIntersection(currentIDs)

        processHistory = processHistory.filter { currentIDs.contains($0.key) }
        if let selectedProcessID, !currentIDs.contains(selectedProcessID) {
            self.selectedProcessID = nil
            selectedProcessHistory = []
            selectedTreeCPUHistory = []
        }
        if let gpuGuardProcessID, !currentIDs.contains(gpuGuardProcessID) {
            gpuGuardEnabled = false
            self.gpuGuardProcessID = nil
            gpuGuardCurrentActivityPercent = 100
            gpuGuardStatus = "El proceso controlado terminó"
        }

        evaluateAutomations()
        evaluateCrossOverIntegration()
        evaluateGPUGuard()
        evaluateAutomaticThermalMode()
    }

    private func appendHistory(_ snapshots: [ProcessSnapshot], metrics: SystemMetricsSample) {
        let now = Date()
        let totalCPU = snapshots.reduce(0) { $0 + $1.cpuPercent }
        systemCPUHistory.append(MetricPoint(date: now, value: totalCPU))
        trim(&systemCPUHistory, maximum: 600)

        if let gpu = metrics.gpuUtilization {
            gpuHistory.append(MetricPoint(date: now, value: gpu))
            trim(&gpuHistory, maximum: 600)
        }

        let guardActivity = gpuGuardEnabled ? gpuGuardCurrentActivityPercent : 100
        gpuGuardActivityHistory.append(MetricPoint(date: now, value: Double(guardActivity)))
        trim(&gpuGuardActivityHistory, maximum: 600)

        for process in snapshots where process.cpuPercent >= 0.2
            || controlledIdentity(process.identity)
            || process.identity == selectedProcessID {
            var history = processHistory[process.identity] ?? []
            history.append(MetricPoint(date: now, value: process.cpuPercent))
            trim(&history, maximum: 600)
            processHistory[process.identity] = history
        }

        var selectedTreeCPU: Double?
        if let selectedProcessID,
           let selected = snapshots.first(where: { $0.identity == selectedProcessID }) {
            selectedProcessHistory = processHistory[selectedProcessID] ?? []
            selectedTreeCPU = treeCPUValue(for: selected)
            selectedTreeCPUHistory.append(MetricPoint(date: now, value: selectedTreeCPU ?? 0))
            trim(&selectedTreeCPUHistory, maximum: 600)
        }

        telemetryRecords.append(TelemetryRecord(
            date: now,
            totalCPUPercent: totalCPU,
            selectedTreeCPUPercent: selectedTreeCPU,
            gpuPercent: metrics.gpuUtilization,
            rendererPercent: metrics.rendererUtilization,
            tilerPercent: metrics.tilerUtilization,
            gpuActivityLimitPercent: gpuGuardEnabled ? gpuGuardCurrentActivityPercent : nil,
            thermalState: thermalLabel
        ))
        if telemetryRecords.count > 3_600 {
            telemetryRecords.removeFirst(telemetryRecords.count - 3_600)
        }
    }

    private func trim(_ points: inout [MetricPoint], maximum: Int) {
        if points.count > maximum {
            points.removeFirst(points.count - maximum)
        }
    }

    private func controlledIdentity(_ identity: ProcessIdentity) -> Bool {
        backgroundIDs.contains(identity)
            || suspendedIDs.contains(identity)
            || lowPriorityIDs.contains(identity)
            || cpuLimitByID[identity] != nil
    }

    private func evaluateAutomations() {
        guard !processes.isEmpty else { return }
        evaluateProcessRules()
        evaluateThermalRules()
        evaluateCrossOverIntegration()
    }

    private func evaluateProcessRules() {
        let validRuleSourceKeys = Set(rules.map { "rule:\($0.id.uuidString)" })

        for process in processes where !isProtected(process) {
            var desiredBackground = Set<String>()
            var desiredLimits: [String: Int] = [:]

            for rule in rules where rule.matches(process) {
                let source = "rule:\(rule.id.uuidString)"
                let shouldApply: Bool
                switch rule.trigger {
                case .whileRunning:
                    shouldApply = true
                case .whenBackground:
                    shouldApply = process.pid != frontmostPID
                }

                guard shouldApply else { continue }
                switch rule.action {
                case .background:
                    desiredBackground.insert(source)
                case .cpuLimit:
                    desiredLimits[source] = rule.cpuLimitPercent
                case .lowPriority:
                    applyLowPriority(process, source: source)
                }
            }

            let currentBackground = Set((backgroundSources[process.identity] ?? []).filter { $0.hasPrefix("rule:") })
            for source in desiredBackground.subtracting(currentBackground) {
                updateBackgroundRequest(process, sourceKey: source, enabled: true)
            }
            for source in currentBackground.subtracting(desiredBackground) {
                updateBackgroundRequest(process, sourceKey: source, enabled: false)
            }

            let currentLimitSources = Set((cpuLimitSources[process.identity] ?? [:]).keys.filter { $0.hasPrefix("rule:") })
            for (source, percent) in desiredLimits {
                updateCPULimitRequest(process, sourceKey: source, percent: percent)
            }
            for source in currentLimitSources.subtracting(Set(desiredLimits.keys)) {
                updateCPULimitRequest(process, sourceKey: source, percent: nil)
            }
        }

        for (identity, sources) in Array(backgroundSources) {
            guard let process = process(for: identity) else { continue }
            for source in sources where source.hasPrefix("rule:") && !validRuleSourceKeys.contains(source) {
                updateBackgroundRequest(process, sourceKey: source, enabled: false)
            }
        }
        for (identity, sources) in Array(cpuLimitSources) {
            guard let process = process(for: identity) else { continue }
            for source in sources.keys where source.hasPrefix("rule:") && !validRuleSourceKeys.contains(source) {
                updateCPULimitRequest(process, sourceKey: source, percent: nil)
            }
        }
    }

    private func evaluateThermalRules() {
        let active = thermalAutomationEnabled && thermalLabel.rank >= thermalThreshold.rank
        thermalAutomationActive = active

        if active != lastThermalAutomationState {
            addLog(active
                   ? "Automatización térmica activada en estado \(thermalLabel.rawValue)."
                   : "Automatización térmica desactivada; se liberan sus límites.")
            lastThermalAutomationState = active
        }

        let validSources = Set(thermalTargets.map { "thermal:\($0.id.uuidString)" })
        for process in processes where !isProtected(process) && !suspendedIDs.contains(process.identity) {
            var desired: [String: Int] = [:]
            if active {
                for target in thermalTargets where target.matches(process) {
                    desired["thermal:\(target.id.uuidString)"] = target.cpuLimitPercent
                }
            }

            let current = Set((cpuLimitSources[process.identity] ?? [:]).keys.filter { $0.hasPrefix("thermal:") })
            for (source, percent) in desired {
                updateCPULimitRequest(process, sourceKey: source, percent: percent)
            }
            for source in current.subtracting(Set(desired.keys)) {
                updateCPULimitRequest(process, sourceKey: source, percent: nil)
            }
        }

        for (identity, sources) in Array(cpuLimitSources) {
            guard let process = process(for: identity) else { continue }
            for source in sources.keys where source.hasPrefix("thermal:") && !validSources.contains(source) {
                updateCPULimitRequest(process, sourceKey: source, percent: nil)
            }
        }
    }

    func crossOverMatches(for profile: CrossOverProfile) -> [ProcessSnapshot] {
        crossOverGameCandidates
            .compactMap { process -> (ProcessSnapshot, Int)? in
                guard let score = profile.matchScore(for: process) else { return nil }
                return (process, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return stableOrder(for: lhs.0) < stableOrder(for: rhs.0)
            }
            .map(\.0)
    }

    func crossOverMatchScore(_ process: ProcessSnapshot, for profile: CrossOverProfile) -> Int? {
        profile.matchScore(for: process)
    }

    func crossOverProfileWarnings(_ profile: CrossOverProfile) -> [String] {
        var warnings = profile.validationMessages
        let matches = crossOverMatches(for: profile)
        if profile.hasTarget && matches.count > 1 {
            warnings.append("La coincidencia actual encuentra \(matches.count) procesos; selecciona una botella o una ruta avanzada para evitar ambigüedad.")
        }
        if profile.gpuGuardEnabled && gpuUtilization == nil {
            warnings.append("GPU Guard se apoyará en el estado térmico porque macOS no está publicando uso de GPU.")
        }
        return warnings
    }

    private func bestCrossOverMatch(for profile: CrossOverProfile) -> ProcessSnapshot? {
        crossOverMatches(for: profile).first
    }

    private func activateCrossOverProfile(_ profile: CrossOverProfile,
                                          root: ProcessSnapshot,
                                          autoAttached: Bool) {
        guard validateControllable(root), isCrossOverGameCandidate(root) else { return }
        performCrossOverMutation {
            stopCrossOverProfileInternal(clearAutoAttach: false)
            activeCrossOverProfileID = profile.id
            activeCrossOverProcessID = root.identity
            activeCrossOverWasAutoAttached = autoAttached
            if selectedCrossOverProfileID != profile.id {
                selectedCrossOverProfileID = profile.id
            }
            selectForHistory(root)
            applyCrossOverProfileControls(profile, root: root)
            crossOverStatus = "\(profile.name) aplicado a \(root.displayName)"
            addLog("CrossOver: perfil \(profile.name) aplicado a \(root.displayName)\(autoAttached ? " automáticamente" : "").")
        }
    }

    private func scheduleCrossOverEvaluation(after delay: TimeInterval = 0.18) {
        guard !loadingPersistence, crossOverMutationDepth == 0 else { return }
        crossOverEvaluationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateCrossOverIntegration()
        }
        crossOverEvaluationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performCrossOverMutation(_ changes: () -> Void) {
        crossOverMutationDepth += 1
        changes()
        crossOverMutationDepth = max(0, crossOverMutationDepth - 1)
    }

    private func evaluateCrossOverIntegration() {
        guard crossOverMutationDepth == 0, !crossOverEvaluationInProgress else { return }
        crossOverEvaluationInProgress = true
        defer { crossOverEvaluationInProgress = false }

        if crossOverAutoAttachEnabled,
           let activeID = activeCrossOverProfileID,
           let selectedID = selectedCrossOverProfileID,
           activeID != selectedID {
            performCrossOverMutation { stopCrossOverProfileInternal(clearAutoAttach: false) }
        }

        if let activeID = activeCrossOverProfileID,
           let profile = crossOverProfiles.first(where: { $0.id == activeID }) {
            guard profile.enabled else {
                performCrossOverMutation { stopCrossOverProfileInternal(clearAutoAttach: false) }
                return
            }

            if let rootID = activeCrossOverProcessID,
               let root = process(for: rootID) {
                if activeCrossOverWasAutoAttached && !profile.matches(root) {
                    performCrossOverMutation { stopCrossOverProfileInternal(clearAutoAttach: false) }
                } else {
                    applyCrossOverProfileControls(profile, root: root)
                    return
                }
            } else {
                performCrossOverMutation {
                    clearCrossOverProfileRequests()
                    if gpuGuardOwnedByCrossOverProfile { stopGPUGuard() }
                    gpuGuardOwnedByCrossOverProfile = false
                    activeCrossOverProfileID = nil
                    activeCrossOverProcessID = nil
                    activeCrossOverWasAutoAttached = false
                    crossOverStatus = crossOverAutoAttachEnabled
                        ? "El juego terminó; esperando una nueva coincidencia"
                        : "El juego terminó"
                }
            }
        }

        guard crossOverAutoAttachEnabled,
              let profile = selectedCrossOverProfile,
              profile.enabled,
              profile.autoAttach else { return }

        guard profile.hasTarget else {
            crossOverStatus = "Autoaplicación detenida: captura el ejecutable"
            return
        }
        guard let root = bestCrossOverMatch(for: profile) else {
            crossOverStatus = "Autoaplicación armada · esperando \(profile.executableContains.isEmpty ? "ejecutable" : profile.executableContains)"
            return
        }
        activateCrossOverProfile(profile, root: root, autoAttached: true)
    }

    private func applyCrossOverProfileControls(_ profile: CrossOverProfile, root: ProcessSnapshot) {
        let base = "\(crossOverSourcePrefix)\(profile.id.uuidString)"
        let gameSource = "\(base):game"
        let thermalSource = "\(base):thermal"
        let launcherSource = "\(base):launcher"
        let externalSource = "\(base):external"

        if profile.gpuGuardEnabled {
            if gpuGuardTargetPercent != profile.gpuTargetPercent { gpuGuardTargetPercent = profile.gpuTargetPercent }
            if gpuGuardMinimumActivityPercent != profile.gpuMinimumActivityPercent { gpuGuardMinimumActivityPercent = profile.gpuMinimumActivityPercent }
            if gpuGuardStepPercent != profile.gpuStepPercent { gpuGuardStepPercent = profile.gpuStepPercent }
            if gpuGuardAllowsRecovery != profile.gpuAllowsRecovery { gpuGuardAllowsRecovery = profile.gpuAllowsRecovery }
            if !gpuGuardOwnedByCrossOverProfile || gpuGuardProcessID != root.identity {
                startGPUGuard(for: root)
                gpuGuardOwnedByCrossOverProfile = true
            }
        } else if gpuGuardOwnedByCrossOverProfile {
            stopGPUGuard()
            gpuGuardOwnedByCrossOverProfile = false
        }

        updateCPULimitRequest(root,
                              sourceKey: gameSource,
                              percent: profile.gameActivityPercent < 100 ? profile.gameActivityPercent : nil)

        let thermalActive = profile.thermalEmergencyEnabled
            && thermalLabel.rank >= profile.thermalThreshold.rank
        updateCPULimitRequest(root,
                              sourceKey: thermalSource,
                              percent: thermalActive ? profile.thermalActivityPercent : nil)

        let externalTokens = profile.externalNameTokens
        let gameTreeIDs = Set(processTree(for: root).map(\.identity))
        let launcherCandidates = processes.filter { process in
            profile.optimizeLaunchers
                && !isProtected(process)
                && !gameTreeIDs.contains(process.identity)
                && !isAncestor(process, of: root)
                && isCrossOverLauncher(process)
        }
        let externalCandidates = processes.filter { process in
            profile.optimizeExternalApps
                && !isProtected(process)
                && !isCrossOverRelated(process)
                && externalTokens.contains(where: {
                    process.displayName.localizedCaseInsensitiveContains($0)
                    || process.path.localizedCaseInsensitiveContains($0)
                    || process.commandLine.localizedCaseInsensitiveContains($0)
                })
        }
        let launcherRootIDs = topLevelIdentities(in: launcherCandidates)
        let externalRootIDs = topLevelIdentities(in: externalCandidates)

        for process in processes where !isProtected(process) && process.identity != root.identity {
            let isLauncherRoot = launcherRootIDs.contains(process.identity)
            let isExternalRoot = externalRootIDs.contains(process.identity)

            updateCPULimitRequest(process,
                                  sourceKey: launcherSource,
                                  percent: isLauncherRoot && profile.launcherActivityPercent < 100
                                      ? profile.launcherActivityPercent
                                      : nil)
            updateBackgroundRequest(process,
                                    sourceKey: launcherSource,
                                    enabled: isLauncherRoot && profile.launcherBackground)
            updateCPULimitRequest(process,
                                  sourceKey: externalSource,
                                  percent: isExternalRoot && profile.externalActivityPercent < 100
                                      ? profile.externalActivityPercent
                                      : nil)
        }

        let statusParts = [
            thermalActive ? "emergencia térmica \(profile.thermalActivityPercent)%" : nil,
            profile.gpuGuardEnabled ? "GPU Guard \(gpuGuardCurrentActivityPercent)%" : nil,
            profile.gameActivityPercent < 100 ? "juego \(profile.gameActivityPercent)%" : nil
        ].compactMap { $0 }
        if statusParts.isEmpty {
            crossOverStatus = "\(profile.name) activo · \(root.displayName)"
        } else {
            crossOverStatus = "\(profile.name) · " + statusParts.joined(separator: " · ")
        }
    }

    private func isAncestor(_ candidate: ProcessSnapshot, of descendant: ProcessSnapshot) -> Bool {
        var currentParent = descendant.parentPID
        var visited = Set<Int32>()
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        while currentParent > 0, visited.insert(currentParent).inserted {
            if currentParent == candidate.pid { return true }
            guard let parent = byPID[currentParent] else { return false }
            currentParent = parent.parentPID
        }
        return false
    }

    private func topLevelIdentities(in candidates: [ProcessSnapshot]) -> Set<ProcessIdentity> {
        let candidatePIDs = Set(candidates.map(\.pid))
        return Set(candidates
            .filter { !candidatePIDs.contains($0.parentPID) }
            .map(\.identity))
    }

    private func clearCrossOverProfileRequests() {
        for process in processes {
            let background = (backgroundSources[process.identity] ?? [])
                .filter { $0.hasPrefix(crossOverSourcePrefix) }
            for source in background {
                updateBackgroundRequest(process, sourceKey: source, enabled: false)
            }

            let limits = (cpuLimitSources[process.identity] ?? [:]).keys
                .filter { $0.hasPrefix(crossOverSourcePrefix) }
            for source in limits {
                updateCPULimitRequest(process, sourceKey: source, percent: nil)
            }
        }
    }

    func updateBackgroundRequest(_ process: ProcessSnapshot,
                                         sourceKey: String,
                                         enabled: Bool) {
        if enabled || backgroundIDs.contains(process.identity) {
            backgroundSnapshots[process.identity] = process
        }
        var sources = backgroundSources[process.identity] ?? []
        let previousDesired = !sources.isEmpty
        if enabled {
            sources.insert(sourceKey)
        } else {
            sources.remove(sourceKey)
        }
        if sources.isEmpty {
            backgroundSources.removeValue(forKey: process.identity)
        } else {
            backgroundSources[process.identity] = sources
        }
        let desired = !sources.isEmpty
        guard desired != previousDesired || backgroundIDs.contains(process.identity) != desired else { return }
        reconcileBackground(process, desired: desired)
    }

    private func reconcileBackground(_ process: ProcessSnapshot, desired: Bool) {
        let token = UUID()
        backgroundTokens[process.identity] = token
        controlQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.controller.setBackground(process, enabled: desired)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.backgroundTokens[process.identity] == token else {
                        if let latest = self.process(for: process.identity) {
                            self.reconcileBackground(latest, desired: !(self.backgroundSources[process.identity] ?? []).isEmpty)
                        }
                        return
                    }
                    if desired {
                        self.backgroundIDs.insert(process.identity)
                        self.backgroundSnapshots[process.identity] = process
                    } else {
                        self.backgroundIDs.remove(process.identity)
                        if (self.backgroundSources[process.identity] ?? []).isEmpty {
                            self.backgroundSnapshots.removeValue(forKey: process.identity)
                        }
                    }
                    self.addLog("\(process.displayName): política \(desired ? "de fondo" : "normal") aplicada.")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.addLog("\(process.displayName): \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    func updateCPULimitRequest(_ process: ProcessSnapshot,
                               sourceKey: String,
                               percent: Int?,
                               pulseMode: ActivityLimiterPulseMode = .burst) {
        var sources = cpuLimitSources[process.identity] ?? [:]
        var modes = cpuLimitModeSources[process.identity] ?? [:]
        if let percent {
            sources[sourceKey] = min(max(percent, 10), 100)
            modes[sourceKey] = pulseMode
        } else {
            sources.removeValue(forKey: sourceKey)
            modes.removeValue(forKey: sourceKey)
        }
        if sources.isEmpty {
            cpuLimitSources.removeValue(forKey: process.identity)
            cpuLimitModeSources.removeValue(forKey: process.identity)
        } else {
            cpuLimitSources[process.identity] = sources
            cpuLimitModeSources[process.identity] = modes
        }
        reconcileCPULimit(process)
    }

    private func reconcileCPULimit(_ process: ProcessSnapshot) {
        guard !suspendedIDs.contains(process.identity) else { return }
        let desired = cpuLimitSources[process.identity]?.values.min()
        // Si cualquier fuente exige el modo por bloques, prevalece. El modo
        // protegido se usa solo cuando todas las fuentes activas lo solicitan.
        let desiredMode = cpuLimitModeSources[process.identity]?.values.min() ?? .burst
        let current = cpuLimitByID[process.identity]
        let currentMode = cpuLimiterModeByID[process.identity]
        let runningLimiter = cpuLimiters[process.identity]
        let runningGuardian = cpuLimiterGuardians[process.identity]

        if desired == nil, current == nil, runningLimiter == nil, runningGuardian == nil { return }
        if desired == current, desiredMode == currentMode,
           runningLimiter?.isRunning == true, runningGuardian?.isRunning == true { return }

        if let desired,
           let runningLimiter,
           runningLimiter.isRunning,
           runningGuardian?.isRunning == true {
            do {
                try controller.updateCPULimiter(process,
                                                activityPercent: desired,
                                                pulseMode: desiredMode)
                cpuLimitByID[process.identity] = desired
                cpuLimiterModeByID[process.identity] = desiredMode
                return
            } catch {
                cpuLimiterGuardians.removeValue(forKey: process.identity)?.terminate()
                runningLimiter.terminate()
                resumeProcessTreeSafety(process)
                cpuLimiters.removeValue(forKey: process.identity)
                cpuLimitByID.removeValue(forKey: process.identity)
                cpuLimiterModeByID.removeValue(forKey: process.identity)
                controller.removeCPULimiterControl(for: process)
                addLog("\(process.displayName): no se pudo actualizar el limitador; se reiniciará. \(error.localizedDescription)", isError: true)
            }
        } else if let staleLimiter = cpuLimiters.removeValue(forKey: process.identity) {
            staleLimiter.terminate()
            cpuLimiterGuardians.removeValue(forKey: process.identity)?.terminate()
            resumeProcessTreeSafety(process)
            cpuLimitByID.removeValue(forKey: process.identity)
            cpuLimiterModeByID.removeValue(forKey: process.identity)
            controller.removeCPULimiterControl(for: process)
        } else if let staleGuardian = cpuLimiterGuardians.removeValue(forKey: process.identity) {
            staleGuardian.terminate()
            resumeProcessTreeSafety(process)
        }

        guard let desired else {
            controller.removeCPULimiterControl(for: process)
            if current != nil {
                addLog("\(process.displayName): control de actividad retirado.")
            }
            return
        }

        do {
            let limiter = try controller.startCPULimiter(process,
                                                         activityPercent: desired,
                                                         cycleMilliseconds: limiterCycleMilliseconds,
                                                         pulseMode: desiredMode)
            let helperPID = limiter.processIdentifier
            let guardian: Process
            do {
                guardian = try controller.startCPULimiterGuardian(
                    process,
                    limiterPID: helperPID
                )
            } catch {
                limiter.terminate()
                resumeProcessTreeSafety(process)
                throw error
            }
            let guardianPID = guardian.processIdentifier
            cpuLimiters[process.identity] = limiter
            cpuLimiterGuardians[process.identity] = guardian
            cpuLimitByID[process.identity] = desired
            cpuLimiterModeByID[process.identity] = desiredMode
            limiter.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.cpuLimiters[process.identity]?.processIdentifier == helperPID else { return }
                    self.cpuLimiters.removeValue(forKey: process.identity)
                    self.cpuLimiterGuardians.removeValue(forKey: process.identity)?.terminate()
                    self.cpuLimitByID.removeValue(forKey: process.identity)
                    self.cpuLimiterModeByID.removeValue(forKey: process.identity)
                    self.controller.removeCPULimiterControl(for: process)
                    self.resumeProcessTreeSafety(process)
                    if self.process(for: process.identity) != nil,
                       self.cpuLimitSources[process.identity]?.isEmpty == false {
                        self.sessionTelemetryWriter.recordSafetyEvent(
                            operation: "limiter_guardian",
                            status: "recovered",
                            reason: "El limitador terminó y el árbol fue reanudado"
                        )
                        self.addLog("\(process.displayName): el limitador terminó inesperadamente; se intentará reactivar.", isError: true)
                        self.reconcileCPULimit(process)
                    }
                }
            }
            guardian.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.cpuLimiterGuardians[process.identity]?.processIdentifier == guardianPID else { return }
                    self.cpuLimiterGuardians.removeValue(forKey: process.identity)
                    let limiter = self.cpuLimiters.removeValue(forKey: process.identity)
                    limiter?.terminate()
                    self.cpuLimitByID.removeValue(forKey: process.identity)
                    self.cpuLimiterModeByID.removeValue(forKey: process.identity)
                    self.controller.removeCPULimiterControl(for: process)
                    self.resumeProcessTreeSafety(process)
                    self.sessionTelemetryWriter.recordSafetyEvent(
                        operation: "limiter_guardian",
                        status: "recovered",
                        reason: "El guardián terminó; se detuvo el limitador y se reanudó el árbol"
                    )
                    if self.process(for: process.identity) != nil,
                       self.cpuLimitSources[process.identity]?.isEmpty == false {
                        self.addLog("\(process.displayName): el guardián terminó; control restaurado y reinicio solicitado.", isError: true)
                        self.reconcileCPULimit(process)
                    }
                }
            }
            addLog("\(process.displayName): control dinámico iniciado en \(desired)% · \(desiredMode.title).")
        } catch {
            cpuLimitSources.removeValue(forKey: process.identity)
            cpuLimitModeSources.removeValue(forKey: process.identity)
            cpuLimiterModeByID.removeValue(forKey: process.identity)
            controller.removeCPULimiterControl(for: process)
            addLog("\(process.displayName): \(error.localizedDescription)", isError: true)
        }
    }

    private func clearAllCPULimitRequests(for process: ProcessSnapshot) {
        cpuLimitSources.removeValue(forKey: process.identity)
        cpuLimitModeSources.removeValue(forKey: process.identity)
        cpuLimiterModeByID.removeValue(forKey: process.identity)
        if let limiter = cpuLimiters.removeValue(forKey: process.identity) {
            limiter.terminate()
        }
        cpuLimiterGuardians.removeValue(forKey: process.identity)?.terminate()
        resumeProcessTreeSafety(process)
        controller.removeCPULimiterControl(for: process)
        cpuLimitByID.removeValue(forKey: process.identity)
    }

    private func resumeProcessTreeSafety(_ root: ProcessSnapshot) {
        let tree = processTree(for: root)
        for process in tree where controller.identityStillMatches(process) {
            _ = tb_send_signal(process.pid, SIGCONT)
        }
    }

    private func evaluateGPUGuard(force: Bool = false) {
        guard gpuGuardEnabled,
              let identity = gpuGuardProcessID,
              let root = process(for: identity),
              !suspendedIDs.contains(identity) else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastGPUGuardEvaluation) >= 2.0 else { return }
        lastGPUGuardEvaluation = now

        let target = min(max(gpuGuardTargetPercent, 40), 95)
        let minimum = min(max(gpuGuardMinimumActivityPercent, 20), 95)
        let step = min(max(gpuGuardStepPercent, 5), 20)
        let current = gpuGuardCurrentActivityPercent
        var desired = current
        var reason = "Estable"

        if thermalLabel == .critical {
            desired = max(minimum, current - max(step, 10))
            gpuGuardHighSamples = 0
            gpuGuardLowSamples = 0
            reason = "Estado térmico crítico"
        } else if thermalLabel == .serious {
            gpuGuardHighSamples += 1
            gpuGuardLowSamples = 0
            if gpuGuardHighSamples >= 2 {
                desired = max(minimum, current - step)
                gpuGuardHighSamples = 0
            }
            reason = "Estado térmico serio"
        } else if let gpu = gpuUtilization {
            if gpu > Double(target + 4) {
                gpuGuardHighSamples += 1
                gpuGuardLowSamples = 0
                if gpuGuardHighSamples >= 2 {
                    desired = max(minimum, current - step)
                    gpuGuardHighSamples = 0
                }
                reason = "GPU por encima del objetivo"
            } else if gpu < Double(max(0, target - 12)) && thermalLabel.rank <= ThermalLabel.fair.rank {
                gpuGuardHighSamples = 0
                if gpuGuardAllowsRecovery {
                    gpuGuardLowSamples += 1
                    if gpuGuardLowSamples >= 8 {
                        desired = min(100, current + step)
                        gpuGuardLowSamples = 0
                    }
                    reason = "Margen disponible; recuperación muy lenta"
                } else {
                    gpuGuardLowSamples = 0
                    reason = "Margen disponible; límite retenido"
                }
            } else {
                gpuGuardHighSamples = 0
                gpuGuardLowSamples = 0
                reason = "Dentro de la banda de histéresis"
            }
        } else {
            if thermalLabel.rank <= ThermalLabel.fair.rank {
                if gpuGuardAllowsRecovery {
                    gpuGuardLowSamples += 1
                    if gpuGuardLowSamples >= 12 {
                        desired = min(100, current + step)
                        gpuGuardLowSamples = 0
                    }
                    reason = "Sin lectura GPU; recuperación térmica lenta"
                } else {
                    gpuGuardLowSamples = 0
                    reason = "Sin lectura GPU; límite retenido"
                }
            }
        }

        desired = min(max(desired, minimum), 100)
        if desired != current {
            gpuGuardCurrentActivityPercent = desired
            updateCPULimitRequest(root,
                                  sourceKey: gpuGuardSourceKey,
                                  percent: desired < 100 ? desired : nil)
            addLog("\(root.displayName): GPU Guard ajustó la actividad a \(desired)% (\(reason)).")
        } else if desired < 100 && !hasCPULimitRequest(root, source: gpuGuardSourceKey) {
            updateCPULimitRequest(root, sourceKey: gpuGuardSourceKey, percent: desired)
        } else if desired == 100 && hasCPULimitRequest(root, source: gpuGuardSourceKey) {
            updateCPULimitRequest(root, sourceKey: gpuGuardSourceKey, percent: nil)
        }

        let gpuText = gpuUtilization.map { String(format: "%.1f%%", $0) } ?? "sin lectura"
        gpuGuardStatus = "\(reason) · GPU \(gpuText) · actividad \(gpuGuardCurrentActivityPercent)%"
    }

    private func formattedAverage(points: [MetricPoint], seconds: TimeInterval) -> String {
        let cutoff = Date().addingTimeInterval(-seconds)
        let values = points.lazy.filter { $0.date >= cutoff }.map(\.value)
        guard !values.isEmpty else { return "—" }
        return String(format: "%.1f %%", values.reduce(0, +) / Double(values.count))
    }

    private func wattsText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f W", value)
    }

    private func csvNumber(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func csvNumber(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    func process(for identity: ProcessIdentity) -> ProcessSnapshot? {
        processes.first { $0.identity == identity }
    }

    private func validateControllable(_ process: ProcessSnapshot) -> Bool {
        if isProtected(process) {
            addLog("\(process.displayName): bloqueado por la lista de seguridad.", isError: true)
            return false
        }
        if !controller.identityStillMatches(process) {
            addLog("\(process.displayName): el PID cambió o el proceso terminó.", isError: true)
            return false
        }
        return true
    }

    private func refreshThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalLabel = .nominal
        case .fair: thermalLabel = .fair
        case .serious: thermalLabel = .serious
        case .critical: thermalLabel = .critical
        @unknown default: thermalLabel = .unknown
        }
    }

    func addLog(_ message: String, isError: Bool = false) {
        logEntries.insert(LogEntry(date: Date(), message: message, isError: isError), at: 0)
        if logEntries.count > 500 {
            logEntries.removeLast(logEntries.count - 500)
        }
    }
}
