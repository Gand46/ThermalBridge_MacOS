import CoreGraphics
import Darwin
import Foundation

private struct DisplayGuardianOptions: Equatable {
    let controllerPID: pid_t
    let displayID: CGDirectDisplayID
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
}

private struct DisplayGuardianModeDescriptor: Equatable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
}

@main
struct TBDisplayGuardian {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--self-test"] {
            runSelfTest()
            return
        }
        guard let options = parse(arguments) else {
            writeError("TBDisplayGuardian: argumentos inválidos\n")
            exit(64)
        }

        while getppid() == options.controllerPID {
            usleep(100_000)
        }

        guard restore(options) else {
            writeError("TBDisplayGuardian: no se pudo restaurar el modo original\n")
            exit(1)
        }
    }

    private static func parse(_ arguments: [String]) -> DisplayGuardianOptions? {
        guard arguments.count == 14 else { return nil }
        var values: [String: String] = [:]
        var index = 0
        while index + 1 < arguments.count {
            values[arguments[index]] = arguments[index + 1]
            index += 2
        }
        guard let controllerRaw = values["--watch"],
              let controllerPID = Int32(controllerRaw), controllerPID > 1,
              let displayRaw = values["--display"],
              let displayID = UInt32(displayRaw),
              let widthRaw = values["--width"], let width = Int(widthRaw), width > 0,
              let heightRaw = values["--height"], let height = Int(heightRaw), height > 0,
              let pixelWidthRaw = values["--pixel-width"],
              let pixelWidth = Int(pixelWidthRaw), pixelWidth > 0,
              let pixelHeightRaw = values["--pixel-height"],
              let pixelHeight = Int(pixelHeightRaw), pixelHeight > 0,
              let refreshRaw = values["--refresh"],
              let refreshRate = Double(refreshRaw), refreshRate.isFinite,
              refreshRate >= 0 else { return nil }
        return DisplayGuardianOptions(
            controllerPID: controllerPID,
            displayID: displayID,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate
        )
    }

    private static func restore(_ options: DisplayGuardianOptions) -> Bool {
        guard let rawModes = CGDisplayCopyAllDisplayModes(options.displayID, nil),
              let modes = rawModes as? [CGDisplayMode] else { return false }
        let descriptors: [DisplayGuardianModeDescriptor] = modes.map {
            (mode: CGDisplayMode) -> DisplayGuardianModeDescriptor in
            DisplayGuardianModeDescriptor(
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate
            )
        }
        guard let selectedIndex = bestModeIndex(
            descriptors: descriptors,
            width: options.width,
            height: options.height,
            pixelWidth: options.pixelWidth,
            pixelHeight: options.pixelHeight,
            refreshRate: options.refreshRate
        ) else { return false }
        return CGDisplaySetDisplayMode(options.displayID, modes[selectedIndex], nil) == .success
    }

    private static func bestModeIndex(
        descriptors: [DisplayGuardianModeDescriptor],
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double
    ) -> Int? {
        let compatible: [(index: Int, mode: DisplayGuardianModeDescriptor)] = descriptors
            .enumerated()
            .compactMap { (entry: (offset: Int, element: DisplayGuardianModeDescriptor))
                -> (index: Int, mode: DisplayGuardianModeDescriptor)? in
                let mode = entry.element
                guard mode.width == width,
                      mode.height == height,
                      mode.pixelWidth == pixelWidth,
                      mode.pixelHeight == pixelHeight else { return nil }
                return (entry.offset, mode)
            }
        guard !compatible.isEmpty else { return nil }
        if refreshRate <= 1,
           let dynamic = compatible.first(where: {
               (entry: (index: Int, mode: DisplayGuardianModeDescriptor)) -> Bool in
               entry.mode.refreshRate <= 1
           }) {
            return dynamic.index
        }
        return compatible.min(by: {
            (lhs: (index: Int, mode: DisplayGuardianModeDescriptor),
             rhs: (index: Int, mode: DisplayGuardianModeDescriptor)) -> Bool in
            abs(lhs.mode.refreshRate - refreshRate)
                < abs(rhs.mode.refreshRate - refreshRate)
        })?.index
    }

    private static func runSelfTest() {
        let parsed = parse([
            "--watch", "123",
            "--display", "1",
            "--width", "1728",
            "--height", "1117",
            "--pixel-width", "3456",
            "--pixel-height", "2234",
            "--refresh", "120.0"
        ])
        precondition(parsed?.controllerPID == 123)
        precondition(parsed?.refreshRate == 120)

        let modes = [
            DisplayGuardianModeDescriptor(
                width: 1728, height: 1117,
                pixelWidth: 3456, pixelHeight: 2234,
                refreshRate: 60
            ),
            DisplayGuardianModeDescriptor(
                width: 1728, height: 1117,
                pixelWidth: 3456, pixelHeight: 2234,
                refreshRate: 120
            )
        ]
        precondition(bestModeIndex(
            descriptors: modes,
            width: 1728, height: 1117,
            pixelWidth: 3456, pixelHeight: 2234,
            refreshRate: 120
        ) == 1)
        precondition(parse(["--watch", "1"]) == nil)
        print("TBDisplayGuardian: SELF-TEST OK")
    }

    private static func writeError(_ message: String) {
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
