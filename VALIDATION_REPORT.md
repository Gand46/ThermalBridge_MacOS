# Informe de auditoría e integración — RC3.9 build 36

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.8 build 35  
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.8 build 35 de selector completo CrossOver.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC39_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 36.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales de selección manual

- El selector manual ya no exige que el proceso publique `.exe` ni evidencia CrossOver directa o por ancestros.
- Todos los procesos no protegidos quedan visibles para permitir escoger el PID que el usuario ve en Monitor de Actividad.
- Los procesos con evidencia CrossOver se ordenan primero; el resto queda como fallback de selección explícita.
- La autoaplicación por `.exe` y la recuperación automática siguen usando únicamente candidatos con evidencia CrossOver.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
