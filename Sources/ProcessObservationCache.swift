import Foundation

/// Suaviza ausencias transitorias del muestreador de procesos. macOS puede
/// devolver una lista incompleta durante una creación/exec o mientras un
/// proceso cambia de estado. Una identidad solo se conserva si el PID sigue
/// perteneciendo al mismo proceso, por lo que nunca se reutiliza un PID nuevo.
struct ProcessObservationCache {
    private struct Entry {
        var snapshot: ProcessSnapshot
        var lastSeen: Date
    }

    private var entries: [ProcessIdentity: Entry] = [:]

    mutating func merge(current: [ProcessSnapshot],
                        now: Date,
                        graceInterval: TimeInterval,
                        shouldRetain: (ProcessSnapshot) -> Bool,
                        isIdentityAlive: (ProcessIdentity) -> Bool) -> [ProcessSnapshot] {
        var mergedByID: [ProcessIdentity: ProcessSnapshot] = [:]
        mergedByID.reserveCapacity(current.count + 8)

        for snapshot in current {
            entries[snapshot.identity] = Entry(snapshot: snapshot, lastSeen: now)
            mergedByID[snapshot.identity] = snapshot
        }

        let missingEntries = entries.filter { mergedByID[$0.key] == nil }
        var identitiesToRemove: [ProcessIdentity] = []
        for (identity, entry) in missingEntries {
            let age = now.timeIntervalSince(entry.lastSeen)
            guard shouldRetain(entry.snapshot),
                  age <= graceInterval,
                  isIdentityAlive(identity) else {
                identitiesToRemove.append(identity)
                continue
            }

            // Una muestra retenida no debe repetir el consumo anterior; solo
            // conserva identidad y metadatos para impedir parpadeos de la UI y
            // desprendimientos prematuros del controlador.
            let retained = ProcessSnapshot(
                identity: entry.snapshot.identity,
                parentPID: entry.snapshot.parentPID,
                name: entry.snapshot.name,
                path: entry.snapshot.path,
                commandLine: entry.snapshot.commandLine,
                cpuPercent: 0,
                memoryBytes: entry.snapshot.memoryBytes,
                niceValue: entry.snapshot.niceValue,
                resourceCounters: nil
            )
            mergedByID[identity] = retained
        }
        for identity in identitiesToRemove {
            entries.removeValue(forKey: identity)
        }

        // Purga defensiva de entradas antiguas aunque no hayan aparecido en el
        // recorrido anterior (por ejemplo, tras un cambio grande de reloj).
        entries = entries.filter { identity, entry in
            mergedByID[identity] != nil || now.timeIntervalSince(entry.lastSeen) <= graceInterval
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.identity.startID < rhs.identity.startID
        }
    }
}
