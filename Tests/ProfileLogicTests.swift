import Foundation

private func snapshot(pid: Int32,
                      executable: String,
                      bottle: String,
                      cpu: Double = 10) -> ProcessSnapshot {
    let command = "wine64-preloader \"/Users/test/Library/Application Support/CrossOver/Bottles/\(bottle)/drive_c/Games/\(executable)\""
    return ProcessSnapshot(identity: ProcessIdentity(pid: pid, startID: UInt64(pid) * 1_000),
                           parentPID: 100,
                           name: "wine64-preloader",
                           path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/x86_64-unix/wine64-preloader",
                           commandLine: command,
                           cpuPercent: cpu,
                           memoryBytes: 1_024,
                           niceValue: 0)
}

@main
private enum ProfileLogicTests {
    static func main() {
        let game = snapshot(pid: 200, executable: "PRAGMATA.exe", bottle: "Pragmata")
        let wrongBottle = snapshot(pid: 201, executable: "PRAGMATA.exe", bottle: "Pragmata-Test")
        let otherGame = snapshot(pid: 202, executable: "OTHER.exe", bottle: "Pragmata")
        let unknownBottle = ProcessSnapshot(identity: ProcessIdentity(pid: 203, startID: 203_000),
                                            parentPID: 100,
                                            name: "wine64-preloader",
                                            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
                                            commandLine: "wine64-preloader PRAGMATA.exe",
                                            cpuPercent: 10,
                                            memoryBytes: 1_024,
                                            niceValue: 0)

        precondition(game.normalizedExecutableName == "pragmata.exe")
        precondition(game.crossOverBottleName == "Pragmata")

        var profile = CrossOverProfile.presetProfile(.balanced)
        profile.executableContains = "PRAGMATA.exe"
        profile.bottleName = "Pragmata"

        precondition(profile.matches(game))
        precondition(!profile.matches(wrongBottle))
        precondition(!profile.matches(otherGame))
        precondition(!profile.matches(unknownBottle))
        precondition(profile.effectivePreset == .balanced)

        profile.gameActivityPercent = 95
        precondition(profile.effectivePreset == .custom)

        var cool = CrossOverProfile.presetProfile(.cool)
        precondition(cool.effectivePreset == .cool)
        cool.externalNames += "\nDiscord"
        precondition(cool.effectivePreset == .custom)

        var empty = CrossOverProfile.presetProfile(.cool)
        empty.executableContains = ""
        precondition(!empty.hasTarget)
        precondition(!empty.validationMessages.isEmpty)

        let staleGame = snapshot(pid: 204,
                                 executable: "STALE.exe",
                                 bottle: "Pragmata",
                                 cpu: 2)
        let refreshedGame = snapshot(pid: 204,
                                     executable: "STALE.exe",
                                     bottle: "Pragmata",
                                     cpu: 33)
        let cachedOnly = snapshot(pid: 205,
                                  executable: "CACHED.exe",
                                  bottle: "Pragmata")
        let duplicateCurrent = snapshot(pid: 204,
                                        executable: "STALE.exe",
                                        bottle: "Pragmata",
                                        cpu: 44)
        let restorationTargets = ProcessRestorationResolver.targets(
            for: [staleGame.identity, cachedOnly.identity],
            current: [refreshedGame, duplicateCurrent],
            cached: [staleGame.identity: staleGame, cachedOnly.identity: cachedOnly]
        )
        let restorationByIdentity = Dictionary(
            uniqueKeysWithValues: restorationTargets.map { ($0.identity, $0) }
        )
        precondition(restorationByIdentity[staleGame.identity]?.cpuPercent == 44)
        precondition(restorationByIdentity[cachedOnly.identity] == cachedOnly)

        print("ProfileLogicTests: OK")
    }
}
