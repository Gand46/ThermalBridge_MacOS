import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ProcessStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("CPU máx. \(store.cpuTemperatureText)", systemImage: "cpu")
                Label("GPU máx. \(store.gpuTemperatureText)", systemImage: "square.stack.3d.up")
            }
            .font(.caption.monospacedDigit())

            if store.automaticThermalEnabled {
                Label(store.automaticThermalEmergency ? "Protección térmica" : "Control automático activo",
                      systemImage: store.automaticThermalEmergency
                        ? "exclamationmark.shield.fill"
                        : "thermometer.medium")
                    .font(.headline)
                    .foregroundColor(store.automaticThermalEmergency ? Color.red : Color.primary)
                Text(store.automaticThermalProcess?.displayName ?? "Esperando juego")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                HStack {
                    Text("Actividad")
                    Spacer()
                    Text(store.automaticThermalActivityText)
                        .monospacedDigit()
                }
                Text(store.automaticThermalReason)
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
                    .lineLimit(3)
                Label("Política macOS: \(store.automaticMacPolicyText)",
                      systemImage: store.automaticMacPolicyLevel.symbolName)
                    .font(.caption2)
            } else if store.automaticThermalConfiguration.autoAttach,
                      store.automaticThermalConfiguration.hasTarget {
                Label("Preparado", systemImage: "bolt.badge.clock")
                    .font(.headline)
                Text(store.automaticThermalConfiguration.executableContains)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            } else {
                Label("Control detenido", systemImage: "pause.circle")
                    .foregroundColor(Color.secondary)
            }

            Divider()

            Button("Abrir ThermalBridge") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Detener control") {
                store.stopAutomaticThermalControl()
            }
            .disabled(!store.automaticThermalEnabled)

            Button("Reiniciar sensor") {
                store.restartTemperatureSensor()
            }

            Divider()

            Button("Salir") {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 310)
    }
}
