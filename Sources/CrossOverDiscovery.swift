import Foundation

struct CrossOverDiscoveryResult {
    let installations: [CrossOverInstallation]
    let bottles: [CrossOverBottle]
}

final class CrossOverDiscovery {
    private let fileManager = FileManager.default

    func scan() -> CrossOverDiscoveryResult {
        CrossOverDiscoveryResult(
            installations: scanInstallations(),
            bottles: scanBottles()
        )
    }

    private func scanInstallations() -> [CrossOverInstallation] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]

        var found: [String: CrossOverInstallation] = [:]
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children where child.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let lower = child.deletingPathExtension().lastPathComponent.lowercased()
                guard lower.contains("crossover") else { continue }
                let infoURL = child.appendingPathComponent("Contents/Info.plist")
                let dictionary: [String: Any]?
                if let data = try? Data(contentsOf: infoURL),
                   let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    dictionary = value as? [String: Any]
                } else {
                    dictionary = nil
                }
                let displayName = (dictionary?["CFBundleDisplayName"] as? String)
                    ?? (dictionary?["CFBundleName"] as? String)
                    ?? child.deletingPathExtension().lastPathComponent
                let version = (dictionary?["CFBundleShortVersionString"] as? String) ?? "Versión desconocida"
                found[child.path] = CrossOverInstallation(path: child.path,
                                                          displayName: displayName,
                                                          version: version)
            }
        }
        return found.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func scanBottles() -> [CrossOverBottle] {
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        var roots: [URL] = [
            applicationSupport.appendingPathComponent("CrossOver/Bottles", isDirectory: true)
        ]

        if let children = try? fileManager.contentsOfDirectory(
            at: applicationSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where child.lastPathComponent.lowercased().contains("crossover") {
                roots.append(child.appendingPathComponent("Bottles", isDirectory: true))
            }
        }

        var found: [String: CrossOverBottle] = [:]
        for root in Set(roots) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard values?.isDirectory == true else { continue }
                found[child.path] = CrossOverBottle(path: child.path,
                                                    name: child.lastPathComponent,
                                                    modifiedAt: values?.contentModificationDate)
            }
        }
        return found.values.sorted { lhs, rhs in
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
