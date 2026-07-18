# Informe de auditoría e integración — RC3.6 build 33

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.5 build 32  
Resultado: prevalidación estática portable incorporada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.5 build 32 ya auditado.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC36_FROZEN_SHA256.txt` cubre fuentes, scripts operativos, documentación de release y configuración de bundle de build 33.
- El cambio no modifica el motor térmico, el limitador, la selección CrossOver, sensores, políticas macOS ni telemetría de sesión.

## Cambios de infraestructura de Fase B

- Se añadió `Prevalidar.command`, una prevalidación portable para entornos no macOS.
- La prevalidación comprueba estructura, versión, manifiestos SHA-256, sintaxis Bash, ausencia de artefactos generados versionados y exclusiones funcionales críticas.
- Se añadió `.gitignore` para impedir que `.build`, `dist`, `releases`, ZIP generados y `validation_build.log` vuelvan al control de versiones.
- Se retiraron del índice Git los artefactos generados que estaban versionados.
- `Validar.command` queda como validación nativa completa obligatoria en Apple Silicon.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
