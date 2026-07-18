import Foundation

private func makeSnapshot(pid: Int32,
                          parentPID: Int32 = 100,
                          name: String,
                          path: String,
                          command: String) -> ProcessSnapshot {
    ProcessSnapshot(identity: ProcessIdentity(pid: pid, startID: UInt64(pid) * 1000),
                    parentPID: parentPID,
                    name: name,
                    path: path,
                    commandLine: command,
                    cpuPercent: 25,
                    memoryBytes: 4096,
                    niceValue: 0)
}

@main
private enum CrossOverDetectionTests {
    static func main() {
        let quotedUnix = makeSnapshot(
            pid: 501,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/x86_64-unix/wine64-preloader",
            command: #"wine64-preloader "/Users/test/Library/Application Support/CrossOver/Bottles/Pragmata/drive_c/Program Files/PRAGMATA/PRAGMATA.exe""#
        )
        precondition(quotedUnix.windowsExecutableName == "PRAGMATA.exe")
        precondition(quotedUnix.displayName == "PRAGMATA.exe")
        precondition(quotedUnix.crossOverBottleName == "Pragmata")

        let windowsPath = makeSnapshot(
            pid: 502,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader "C:\Program Files\Game Studio\My Game.exe""#
        )
        precondition(windowsPath.windowsExecutableName == "My Game.exe")

        let chain = makeSnapshot(
            pid: 503,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader cmd.exe /c start.exe "Z:\Games\PRAGMATA.exe""#
        )
        precondition(chain.windowsExecutableName == "PRAGMATA.exe")
        precondition(chain.windowsExecutableCandidates.contains("cmd.exe"))
        precondition(chain.windowsExecutableCandidates.contains("start.exe"))

        let directName = makeSnapshot(
            pid: 504,
            name: "PRAGMATA.exe",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: ""
        )
        precondition(directName.windowsExecutableName == "PRAGMATA.exe")

        let longPrefix = String(repeating: "argumento-largo ", count: 240)
        let longCommand = makeSnapshot(
            pid: 505,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: longPrefix + #""/Users/test/Games/DEEP_GAME.exe""#
        )
        precondition(longCommand.commandLine.count > 2048)
        precondition(longCommand.windowsExecutableName == "DEEP_GAME.exe")


        let helperArgument = makeSnapshot(
            pid: 507,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader "C:\Program Files\Foo\My Game.exe" --helper.exe"#
        )
        precondition(helperArgument.windowsExecutableName == "My Game.exe")
        precondition(!helperArgument.windowsExecutableCandidates.contains("--helper.exe"))

        let uppercaseQuoted = makeSnapshot(
            pid: 508,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader "/Users/test/Game Folder/UPPER.EXE""#
        )
        precondition(uppercaseQuoted.windowsExecutableName == "UPPER.EXE")


        let environmentBottle = makeSnapshot(
            pid: 509,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader "CX_BOTTLE=Pragmata Demo" WINEPREFIX="/Users/test/Library/Application Support/CrossOver/Bottles/Pragmata Demo""#
        )
        precondition(environmentBottle.crossOverBottleName == "Pragmata Demo")

        let multipleExecutables = makeSnapshot(
            pid: 510,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: #"wine64-preloader helper.exe "C:\Games\PRAGMATA.exe" crashreporter.exe"#
        )
        precondition(multipleExecutables.containsWindowsExecutable(named: "PRAGMATA.exe"))
        precondition(multipleExecutables.windowsExecutableEvidenceScore(named: "PRAGMATA.exe") == 1_100)

        let unresolved = makeSnapshot(
            pid: 506,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/wine/wine64-preloader",
            command: "wine64-preloader --some-runtime-token"
        )
        precondition(unresolved.windowsExecutableName == nil)

        // Algunos juegos recientes no publican .exe, Wine ni CrossOver en el
        // nombre, la ruta o argv del host real. La relación padre-hijo debe
        // mantenerlos visibles para que el usuario pueda asociar manualmente el
        // ejecutable sin clasificar procesos ajenos al árbol.
        let runtimeRoot = makeSnapshot(
            pid: 520,
            parentPID: 1,
            name: "wine64-preloader",
            path: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64-preloader",
            command: "wine64-preloader --opaque-launch"
        )
        let hiddenGameHost = makeSnapshot(
            pid: 521,
            parentPID: 520,
            name: "GameMain",
            path: "/private/tmp/GameMain",
            command: ""
        )
        let unrelatedHost = makeSnapshot(
            pid: 522,
            parentPID: 1,
            name: "GameMain",
            path: "/private/tmp/OtherGameMain",
            command: ""
        )
        let topology = ProcessTopologyIndex(
            processes: [runtimeRoot, hiddenGameHost, unrelatedHost]
        )
        precondition(runtimeRoot.hasDirectCrossOverRuntimeEvidence)
        precondition(!hiddenGameHost.hasDirectCrossOverRuntimeEvidence)
        precondition(topology.hasCrossOverRuntimeAncestor(of: hiddenGameHost))
        precondition(!topology.hasCrossOverRuntimeAncestor(of: unrelatedHost))

        let nestedLauncherHost = makeSnapshot(
            pid: 523,
            parentPID: 521,
            name: "LauncherHelper",
            path: "/private/tmp/LauncherHelper",
            command: ""
        )
        let nestedHelperTopology = ProcessTopologyIndex(
            processes: [runtimeRoot, hiddenGameHost, nestedLauncherHost]
        )
        precondition(!nestedLauncherHost.hasDirectCrossOverRuntimeEvidence)
        precondition(nestedHelperTopology.hasCrossOverRuntimeAncestor(of: nestedLauncherHost))

        let wineInfrastructureChild = makeSnapshot(
            pid: 524,
            parentPID: 521,
            name: "services.exe",
            path: "/private/tmp/services.exe",
            command: ""
        )
        let fullTreeTopology = ProcessTopologyIndex(
            processes: [runtimeRoot, hiddenGameHost, wineInfrastructureChild]
        )
        precondition(fullTreeTopology.hasCrossOverRuntimeAncestor(of: wineInfrastructureChild))

        print("CrossOverDetectionTests: OK")
    }
}
