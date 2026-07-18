import AppKit
import SwiftUI

final class StoreRegistry {
    static var shared: ProcessStore?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        StoreRegistry.shared?.restoreAll(preserveAutomations: true)
    }
}

@main
struct ThermalBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: ProcessStore

    init() {
        let createdStore = ProcessStore()
        _store = StateObject(wrappedValue: createdStore)
        StoreRegistry.shared = createdStore
    }

    var body: some Scene {
        WindowGroup("ThermalBridge Auto para CrossOver", id: "main") {
            AutomaticThermalView(store: store)
        }
        .defaultSize(width: 840, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Detener control térmico") {
                    store.stopAutomaticThermalControl()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!store.automaticThermalEnabled)

                Button("Reiniciar sensor") {
                    store.restartTemperatureSensor()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }

        MenuBarExtra("ThermalBridge", systemImage: "thermometer.medium") {
            MenuBarView(store: store)
        }
    }
}
