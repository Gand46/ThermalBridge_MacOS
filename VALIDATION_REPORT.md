# Informe de auditoría e integración — RC3.13 build 40

Fecha de preparación: 18 de julio de 2026
Base inmediata: ThermalBridge 0.7.0 RC3.12 build 39
Resultado: prevalidación estática portable aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- La candidata parte del árbol RC3.12 build 39 con analizador B1 y no persistencia del `.exe` automático.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- `RC313_FROZEN_SHA256.txt` cubre fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de build 40.
- El cambio añade un gobernador predictivo B1 en modo sombra sin control manual de ventiladores/frecuencias y sin dependencia obligatoria de energía/IOReport.

## Cambios funcionales

- Se añade `B1PredictiveThermalGovernor` con filtro, pendiente robusta, predicción, PI anti-windup, slew asimétrico y máquina de estados con histéresis.
- El modo sombra registra decisiones B1 y no aplica `SIGSTOP/SIGCONT` salvo emergencia.
- La telemetría conserva esquema 2 y añade campos opcionales para señal, predicción, control, actuador e identidad efímera.
- `Tools/Analizar_Telemetria_B1.py` sigue leyendo sesiones antiguas y muestra `no medido` para frame pacing/campos ausentes.

## Límites de esta validación

La prevalidación portable no compila SwiftUI/AppKit/CoreGraphics con el SDK de macOS, no firma binarios, no verifica arquitectura ARM64 real, no lee sensores físicos y no ejecuta CrossOver. Es una puerta temprana para detectar desviaciones de proyecto antes de la validación nativa.

La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
