# Informe de auditoría e integración — RC3.11 build 38

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.10 build 37  
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.10 build 37 con filtro único por nombre `.exe` y autoapertura QoS.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC311_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 38.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales

- Se añade una casilla para preseleccionar automáticamente el proceso `.exe` detectado con mayor uso de CPU.
- La preselección se recalcula cuando cambia la lista de procesos o cuando se reactiva la casilla.
- Al desactivar la casilla, la selección manual del usuario se conserva como override.
- La preferencia se persiste en `UserDefaults` y queda activada por defecto.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
