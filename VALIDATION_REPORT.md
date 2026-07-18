# Informe de auditoría e integración — RC3.7 build 34

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.6 build 33  
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.6 build 33 ya preparado para Fase B.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC37_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 34.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales de selección CrossOver

- La lista manual conserva procesos relacionados del árbol CrossOver aunque estén clasificados como launcher o ayudante.
- `Usar selección` puede confirmar un proceso del árbol sin `.exe` como asociación explícita de sesión.
- Las asociaciones sin `.exe` no arman autoaplicación persistente; al terminar el proceso se desarma la sesión manual.
- La autoaplicación por `.exe`, la recuperación fuerte y la selección automática siguen descartando launchers y ayudantes ambiguos.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
