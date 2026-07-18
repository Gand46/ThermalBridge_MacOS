# Informe de auditoría e integración — RC3.10 build 37

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.9 build 36  
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.9 build 36 de selector manual amplio.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC310_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 37.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales

- El selector manual queda filtrado únicamente por nombre de proceso que contenga `.exe`.
- No se exige que el proceso publique argumentos, ruta CrossOver, botella ni ancestro CrossOver para aparecer en el selector.
- Tras detectar instalaciones, ThermalBridge intenta abrir CrossOver con el clamp QoS configurado usando la ruta existente de lanzamiento.
- Si CrossOver ya está abierto o el sistema no soporta clamp de lanzamiento, se informa el estado y no se promete afinidad ni herencia confirmada.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
