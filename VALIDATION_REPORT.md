# Informe de auditoría e integración — RC3.12 build 39

Fecha de preparación: 18 de julio de 2026
Base inmediata: ThermalBridge 0.7.0 RC3.11 build 38
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.11 build 38 con preselección del `.exe` más demandante, filtro único por nombre `.exe` y autoapertura QoS.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC312_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 39.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales

- La casilla de preselección automática ya no diligencia ni persiste el campo `.exe` mientras está activada.
- Al confirmar una selección con el automático activo, la asociación queda limitada al PID/sesión visible y no arma autoaplicación persistente.
- Al desactivar la casilla, la selección manual del usuario se conserva como override y el campo `.exe` vuelve a estar disponible.
- Se inicia la etapa B1 con `Tools/Analizar_Telemetria_B1.py`, analizador offline de sesiones JSONL para medir °C·s sobre objetivo, picos, variabilidad de actividad, emergencia, sensor obsoleto, burst, QoS confirmado y energía directa.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
