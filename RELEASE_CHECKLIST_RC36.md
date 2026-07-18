# Release checklist — RC3.6

## Completado en preparación

- [x] Base inmediata RC3.5 build 32.
- [x] Build incrementado a 33 para los cambios de infraestructura de Fase B.
- [x] Instantáneas persistentes para restaurar Darwin Background.
- [x] Cola FIFO drenada antes de la restauración final.
- [x] Resolución tolerante a identidades duplicadas y regresión asociada.
- [x] Analizador estático Clang para la carga dinámica IOHID.
- [x] UI histórica, protocolos beta y manifiesto RC3 obsoleto retirados.
- [x] Empaquetador ZIP versionado integrado al final de la validación.
- [x] Motor térmico Beta 6 preservado.
- [x] Búfer `TBProcessInfo` persistente y reutilizable.
- [x] `PROC_PIDTASKINFO` limitado al fallback de rusage.
- [x] UID y límite máximo de CPU cacheados por `ProcessSampler`.
- [x] Índice de topología PID construido una vez por muestra.
- [x] Hosts neutros descendientes de CrossOver visibles en el selector.
- [x] Expresiones regulares de `.exe` y botellas precompiladas.
- [x] Diagnóstico ampliado a todos los descendientes del árbol Wine.
- [x] Falso negativo de `codesign | grep -q` eliminado.
- [x] Game Mode ausente de fuentes ejecutables.
- [x] QoS-first de Beta 7 ausente.
- [x] Fuentes, scripts operativos, documentación de release y configuración incluidos en `RC36_FROZEN_SHA256.txt`.
- [x] Validación exige aplicación y helpers ARM64.
- [x] Validación exige firmas individuales y profunda.
- [x] Protocolo de aceptación actualizado.
- [x] Prevalidación estática portable añadida.
- [x] Artefactos generados retirados del control de versiones y cubiertos por `.gitignore`.

## Validación nativa pendiente para build 33

- [ ] Typecheck con Apple Swift 6.3.3 o posterior compatible.
- [ ] Suites Swift y sondas C completas.
- [ ] Build ARM64 y firma ad-hoc.
- [ ] Sensor físico SMC/IOHID.
- [ ] ZIP generado por `Validar.command` verificado en macOS.

## Pendiente en aceptación física

- [ ] Juego con `.exe` oculto visible y asociable mediante selección manual.
- [ ] Sesión Utility de 30 minutos.
- [ ] Sesión Maintenance de 30 minutos, si aplica.
- [ ] Restauración normal del refresco.
- [ ] Restauración del refresco tras cierre forzado.
- [ ] Migración sobre la versión instalada.
- [ ] Revisión de telemetría y privacidad.
- [ ] Tres sesiones reales adicionales o 24 horas de observación.

## Bloqueadores de lanzamiento

- Cualquier hash RC3.6 distinto.
- Error de compilación, firma o arquitectura.
- Reaparición de la caída abrupta de Beta 7.
- Juego o helper dejado en `SIGSTOP`.
- Política o pantalla que no se restaura.
- Lectura térmica permanentemente ausente sin degradación segura.
- Cambio de fuente posterior a la congelación.
