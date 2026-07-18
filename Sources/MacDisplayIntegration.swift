import AppKit
import CoreGraphics
import Foundation

struct MacDisplayIntegrationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DisplayRefreshResult: Equatable {
    case unchanged(refreshRate: Double)
    case applied(refreshRate: Double)
}

final class DisplayRefreshController {
    private var originalDisplayID: CGDirectDisplayID?
    private var originalMode: CGDisplayMode?
    private var guardianProcess: Process?
    private(set) var appliedRefreshRate: Double?

    var isReduced: Bool { originalDisplayID != nil && originalMode != nil }
    var guardianActive: Bool { guardianProcess?.isRunning == true }

    @discardableResult
    func reduceMainDisplay(maximumRefreshRate: Double) throws -> DisplayRefreshResult {
        if let appliedRefreshRate, isReduced {
            return .unchanged(refreshRate: appliedRefreshRate)
        }
        let displayID = CGMainDisplayID()
        guard let current = CGDisplayCopyDisplayMode(displayID) else {
            throw MacDisplayIntegrationError(
                message: "No se pudo leer el modo de la pantalla principal"
            )
        }
        let requested = min(max(30, maximumRefreshRate), 120)
        if current.refreshRate > 1, current.refreshRate <= requested + 0.5 {
            return .unchanged(refreshRate: current.refreshRate)
        }
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            throw MacDisplayIntegrationError(
                message: "La pantalla principal no publicó modos configurables"
            )
        }
        let compatible: [CGDisplayMode] = modes.filter { (mode: CGDisplayMode) -> Bool in
            mode.width == current.width
                && mode.height == current.height
                && mode.pixelWidth == current.pixelWidth
                && mode.pixelHeight == current.pixelHeight
                && mode.refreshRate > 1
                && mode.refreshRate <= requested + 0.5
        }
        guard let target = compatible.max(by: {
            (lhs: CGDisplayMode, rhs: CGDisplayMode) -> Bool in
            lhs.refreshRate < rhs.refreshRate
        }) else {
            throw MacDisplayIntegrationError(
                message: "No existe un modo de hasta \(Int(requested)) Hz con la resolución actual"
            )
        }

        let applyResult = CGDisplaySetDisplayMode(displayID, target, nil)
        guard applyResult == .success else {
            throw MacDisplayIntegrationError(
                message: "CoreGraphics rechazó el modo de pantalla (\(applyResult.rawValue))"
            )
        }

        originalDisplayID = displayID
        originalMode = current
        appliedRefreshRate = target.refreshRate
        do {
            try startGuardian(displayID: displayID, originalMode: current)
        } catch {
            let rollbackResult = CGDisplaySetDisplayMode(displayID, current, nil)
            if rollbackResult == .success {
                clearAppliedState()
                throw MacDisplayIntegrationError(
                    message: "La reducción se revirtió porque no inició el guardián: \(error.localizedDescription)"
                )
            }
            throw MacDisplayIntegrationError(
                message: "El refresco cambió, pero fallaron el guardián y la restauración inmediata"
            )
        }
        return .applied(refreshRate: target.refreshRate)
    }

    @discardableResult
    func restore() throws -> Double? {
        guard let displayID = originalDisplayID, let mode = originalMode else {
            stopGuardian()
            appliedRefreshRate = nil
            return nil
        }
        let result = CGDisplaySetDisplayMode(displayID, mode, nil)
        guard result == .success else {
            throw MacDisplayIntegrationError(
                message: "No se pudo restaurar el modo de pantalla (\(result.rawValue))"
            )
        }
        let restoredRate = mode.refreshRate
        stopGuardian()
        clearAppliedState()
        return restoredRate
    }

    private func startGuardian(displayID: CGDirectDisplayID,
                               originalMode: CGDisplayMode) throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("TBDisplayGuardian")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw MacDisplayIntegrationError(message: "Falta TBDisplayGuardian en el paquete")
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "--watch", String(ProcessInfo.processInfo.processIdentifier),
            "--display", String(displayID),
            "--width", String(originalMode.width),
            "--height", String(originalMode.height),
            "--pixel-width", String(originalMode.pixelWidth),
            "--pixel-height", String(originalMode.pixelHeight),
            "--refresh", String(format: "%.6f", originalMode.refreshRate)
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw MacDisplayIntegrationError(message: error.localizedDescription)
        }
        guard process.isRunning else {
            throw MacDisplayIntegrationError(message: "TBDisplayGuardian terminó durante el arranque")
        }
        guardianProcess = process
    }

    private func stopGuardian() {
        if let guardianProcess, guardianProcess.isRunning {
            guardianProcess.terminate()
        }
        guardianProcess = nil
    }

    private func clearAppliedState() {
        originalDisplayID = nil
        originalMode = nil
        appliedRefreshRate = nil
    }
}
