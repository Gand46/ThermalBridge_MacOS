# Informe de auditoría e integración — RC3.8 build 35

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3.7 build 34  
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.7 build 34 de selección manual ampliada.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC38_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 35.
- El cambio no modifica el motor térmico, el limitador, sensores, políticas macOS ni telemetría de sesión.

## Cambios funcionales de selección CrossOver

- El selector manual pasa de mostrar candidatos filtrados a mostrar el árbol CrossOver completo no protegido.
- Los nodos de infraestructura Wine, launchers y ayudantes quedan visibles para selección explícita cuando cuelgan de CrossOver.
- Las asociaciones sin `.exe` continúan limitadas a la sesión actual y no arman autoaplicación persistente.
- La búsqueda automática por `.exe` y la recuperación por botella siguen evitando infraestructura, launchers y ayudantes ambiguos sin confirmación explícita.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
