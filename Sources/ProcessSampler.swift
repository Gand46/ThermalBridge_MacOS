import Foundation

final class ProcessSampler {
    private static let processCapacity = 4096

    private struct CachedMetadata {
        var name: String
        var path: String
        var commandLine: String
        var lastSeenNanoseconds: UInt64
    }

    private var previousTotals: [ProcessIdentity: UInt64] = [:]
    private var previousTimestamp: UInt64?
    private var metadataByIdentity: [ProcessIdentity: CachedMetadata] = [:]
    private let currentUID = tb_current_uid()
    private let maximumCPUPercent = Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) * 100.0
    private var processBuffer = Array(
        repeating: TBProcessInfo(),
        count: ProcessSampler.processCapacity
    )

    func sample() -> [ProcessSnapshot] {
        // TBProcessInfo incluye buffers amplios para ruta y argv. Conservar la
        // reserva evita reconstruir e inicializar aproximadamente 21,5 MiB en
        // cada tick del monitor; el puente C sobrescribe todas las entradas
        // publicadas antes de devolver el conteo.
        let count = processBuffer.withUnsafeMutableBufferPointer { buffer in
            tb_list_user_processes(buffer.baseAddress, Int32(buffer.count), currentUID)
        }
        guard count >= 0 else { return [] }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousTimestamp.map { Double(now - $0) / 1_000_000_000.0 } ?? 0
        var nextTotals: [ProcessIdentity: UInt64] = [:]
        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            let item = processBuffer[index]
            let identity = ProcessIdentity(pid: item.pid, startID: item.start_id)
            let total = item.user_time_ns &+ item.system_time_ns
            nextTotals[identity] = total

            let cpuPercent: Double
            if elapsed > 0, let previous = previousTotals[identity], total >= previous {
                cpuPercent = min(Double(total - previous) / 1_000_000_000.0 / elapsed * 100.0,
                                 maximumCPUPercent)
            } else {
                cpuPercent = 0
            }

            let sampledName = decodeCString(item.name)
            let sampledPath = decodeCString(item.path)
            let sampledCommand = decodeCString(item.command)
            let cached = metadataByIdentity[identity]

            // KERN_PROCARGS2 y proc_pidpath pueden fallar de forma transitoria
            // mientras Wine ejecuta o reemplaza una imagen. No se debe borrar
            // una identificación .exe válida por una sola lectura vacía.
            let resolvedName = sampledName.isEmpty ? (cached?.name ?? "") : sampledName
            let resolvedPath = sampledPath.isEmpty ? (cached?.path ?? "") : sampledPath
            let resolvedCommand = sampledCommand.isEmpty ? (cached?.commandLine ?? "") : sampledCommand
            metadataByIdentity[identity] = CachedMetadata(
                name: resolvedName,
                path: resolvedPath,
                commandLine: resolvedCommand,
                lastSeenNanoseconds: now
            )

            snapshots.append(ProcessSnapshot(
                identity: identity,
                parentPID: item.parent_pid,
                name: resolvedName,
                path: resolvedPath,
                commandLine: resolvedCommand,
                cpuPercent: max(0, cpuPercent),
                memoryBytes: item.resident_size,
                niceValue: item.nice_value,
                resourceCounters: resourceCounters(from: item)
            ))
        }

        previousTotals = nextTotals
        previousTimestamp = now

        // Conserva metadatos durante 30 s para sobrevivir una omisión breve del
        // listado, pero la identidad incluye fecha de inicio y evita heredar
        // datos cuando macOS reutiliza un PID.
        let metadataTTL: UInt64 = 30_000_000_000
        metadataByIdentity = metadataByIdentity.filter { _, value in
            now >= value.lastSeenNanoseconds
                && now - value.lastSeenNanoseconds <= metadataTTL
        }
        return snapshots
    }

    private func resourceCounters(from item: TBProcessInfo) -> ProcessResourceCounters? {
        guard item.rusage_version > 0 else { return nil }
        let hasQoS = (item.resource_flags & UInt32(TB_RESOURCE_HAS_QOS_COUNTERS)) != 0
        let hasDirectEnergy = (item.resource_flags & UInt32(TB_RESOURCE_HAS_DIRECT_ENERGY)) != 0
        let hasBilledEnergy = (item.resource_flags & UInt32(TB_RESOURCE_HAS_BILLED_ENERGY)) != 0
        return ProcessResourceCounters(
            rusageVersion: Int(item.rusage_version),
            directEnergyNJ: hasDirectEnergy ? item.energy_nj : nil,
            billedEnergyNJ: hasBilledEnergy ? item.billed_energy_nj : nil,
            servicedEnergyNJ: hasBilledEnergy ? item.serviced_energy_nj : nil,
            qosDefaultNS: hasQoS ? item.qos_default_ns : nil,
            qosMaintenanceNS: hasQoS ? item.qos_maintenance_ns : nil,
            qosBackgroundNS: hasQoS ? item.qos_background_ns : nil,
            qosUtilityNS: hasQoS ? item.qos_utility_ns : nil,
            qosLegacyNS: hasQoS ? item.qos_legacy_ns : nil,
            qosUserInitiatedNS: hasQoS ? item.qos_user_initiated_ns : nil,
            qosUserInteractiveNS: hasQoS ? item.qos_user_interactive_ns : nil
        )
    }

    private func decodeCString<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { chars in
                String(cString: chars)
            }
        }
    }
}
