# ThermalBridge Auto 0.7.0 RC3.12

Candidata intermedia de estabilización ARM64 para controlar térmicamente juegos de CrossOver en Apple Silicon. No modifica Wine, D3DMetal, DXVK, botellas ni archivos del juego.

## Alcance de RC3.12

RC3.12 build 39 parte de RC3.11 build 38 e inicia la etapa B1 con un analizador offline de telemetría para puntuar sesiones térmicas antes de modificar el motor. Además ajusta la casilla de auto-selección para que, mientras esté activada, no diligencie ni persista el campo `.exe`; la confirmación controla el PID elegido solo durante la sesión. No cambia el motor térmico, el limitador, sensores, políticas macOS ni los valores predeterminados térmicos.

Permanecen sin cambios:

- motor térmico basado en la línea estable Beta 6;
- porcentajes, objetivos, histéresis, integral y recuperación gradual;
- anticipación por potencia;
- Audio Safe y freno burst;
- Utility inicial y Maintenance explícito;
- rusage, energía, evidencia QoS y telemetría JSONL;
- guardianes de suspensión, limitador y pantalla.

## Autoaplicar al `.exe` más demandante

- La casilla **Autoaplicar al proceso .exe más demandante** está activada por defecto.
- Al estar activada, la lista preselecciona el proceso `.exe` detectado con mayor CPU; si hay empate, usa memoria y CPU del árbol como desempate.
- Mientras está activada, el campo de texto del `.exe` permanece vacío y deshabilitado para evitar guardar una aplicación persistente por accidente.
- **Usar selección** con la casilla activada controla el PID elegido y su sesión visible, pero no persiste `executableContains`.
- Al desactivarla, ThermalBridge conserva la selección manual del usuario en la lista y permite escribir o guardar un `.exe` manualmente.


## Etapa B1: puntuación offline de telemetría

- `Tools/Analizar_Telemetria_B1.py` lee sesiones JSONL de esquema 2 y genera una tabla Markdown con métricas comparables por sesión.
- Calcula duración, °C·s por encima de objetivo CPU/GPU, pico de sobretemperatura, actividad media, variabilidad de actividad, porcentaje de emergencia, sensor obsoleto, uso de `burst`, confirmación QoS y energía directa.
- Es una herramienta de análisis offline: no participa en el control en vivo ni cambia decisiones térmicas.
- Uso esperado: `Tools/Analizar_Telemetria_B1.py ~/Library/Application\ Support/ThermalBridge/Telemetry`.

## Selector manual filtrado por nombre `.exe`

- El selector manual muestra procesos no protegidos cuyo nombre publicado o nombre visible contiene `.exe`.
- No se exige evidencia CrossOver, argv reconocible, ruta de botella ni ancestro Wine para aparecer.
- **Usar selección** conserva la asociación explícita de sesión; para autoaplicación persistente sigue siendo necesario escribir o elegir un `.exe` válido.
- La búsqueda automática y la recuperación fuerte continúan evitando procesos ajenos o ambiguos si no hay confirmación explícita del usuario.

## Apertura posterior de CrossOver con QoS

- Después de iniciar ThermalBridge y detectar instalaciones, la app intenta abrir CrossOver con el clamp QoS configurado.
- Si CrossOver ya está abierto o el sistema no soporta `posix_spawnattr_set_qos_clamp_np`, se informa el estado y no se promete herencia confirmada.
- La evidencia QoS sigue midiéndose posteriormente con contadores del sistema cuando están disponibles.

## Infraestructura de Fase B

- `Prevalidar.command` permite ejecutar una puerta estática portable antes de disponer de una Mac Apple Silicon.
- `.gitignore` evita versionar `.build`, `dist`, `releases`, ZIP generados y registros locales de validación.
- Los artefactos generados dejan de formar parte del repositorio fuente; `Validar.command` y `Empaquetar_Proyecto.command` los regeneran cuando corresponde.

## Endurecimiento heredado de RC3.5

- Conserva una instantánea por identidad de cada proceso con Darwin Background solicitado o aplicado.
- Restaura esa política aunque el proceso falte transitoriamente del último censo.
- Drena la cola FIFO de control antes de retirar Darwin Background al cerrar, evitando que una solicitud pendiente vuelva a activarlo después.
- Refuerza las comprobaciones de punteros cargados dinámicamente para IOHID.
- Tolera identidades duplicadas en una muestra de restauración sin cerrar la aplicación.
- Añade una regresión para esa condición y un análisis estático robusto de la ruta IOHID.
- Elimina UI histórica, protocolos beta y el manifiesto RC3 obsoleto del paquete publicable.

## Detección degradada segura heredada de RC3

- Construye una vez por muestra un índice PID→proceso para recorrer la topología sin diccionarios repetidos.
- Considera seleccionable un host neutro cuando desciende inequívocamente de un runtime CrossOver/Wine.
- Mantiene fuera procesos ajenos aunque tengan nombres similares.
- Permite asociar al host el `.exe` escrito manualmente mediante **Usar selección**.
- No autoactiva un host ambiguo sin evidencia del ejecutable, la botella o una selección confirmada.
- El diagnóstico incluye todos los descendientes, aunque sus nombres y argumentos no contengan `.exe`.
- Precompila una sola vez las expresiones regulares de ejecutables y botellas.

## Eficiencia interna heredada de RC2

- Reutiliza el búfer de 4096 registros `TBProcessInfo` durante toda la vida de `ProcessSampler`.
- Evita reservar e inicializar aproximadamente 21,5 MiB de almacenamiento transitorio en cada muestra.
- Consulta `PROC_PIDTASKINFO` únicamente cuando todas las versiones disponibles de `proc_pid_rusage` fallan.
- Conserva una sola vez el UID actual y el límite de CPU derivado del número de procesadores activos.
- No modifica Maintenance, Audio Safe, Burst, objetivos, histéresis, integral, políticas ni intervalos.

## Funciones candidatas

- Detección y asociación persistente de juegos CrossOver.
- Temperatura máxima CPU/GPU mediante AppleSMC, IOHID tolerante a fallos y macmon opcional.
- Control de actividad mediante `SIGSTOP`/`SIGCONT` con pulsos Audio Safe.
- Políticas macOS opcionales y reversibles cuando el sistema las permite.
- Evidencia de energía y QoS efectivo por identidad PID+fecha de inicio.
- `TBLimiterGuardian` para reanudar procesos si desaparece el limitador.
- Reducción opcional de refresco cuando domina la GPU.
- `TBDisplayGuardian` para restaurar el modo original si termina ThermalBridge.

## Funciones excluidas

Game Mode permanece retirado. RC3.12 no contiene su controlador ni ejecuta herramientas de Xcode para modificarlo.

También permanecen excluidos:

- QoS-first y la regresión de Mantenimiento de Beta 7;
- control de ventiladores o escritura SMC;
- IOReport como proveedor de muestras;
- captura de pantalla o medición automática de frame pacing;
- afirmaciones de que QoS fija procesos a E-cores.

IOReport continúa únicamente como sonda de disponibilidad por carga dinámica y no participa en el controlador.

## Congelación de la candidata

RC3.12 incluye dos manifiestos activos:

- `BASELINE_BETA6_SHA256.txt`: protege los componentes térmicos históricos.
- `RC312_FROZEN_SHA256.txt`: protege fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle de la candidata.

El manifiesto RC3 anterior no se distribuye porque marca correctamente como distintos los archivos integrados y producía falsos fallos fuera de su candidata original. La procedencia inmediata se documenta en este README y en `CHANGELOG.md`. `Validar.command` y `Prevalidar.command` fallan si cambia la línea Beta 6 o cualquier archivo incluido en `RC312_FROZEN_SHA256.txt`.

## Prevalidación estática portable

En cualquier entorno con Bash y utilidades SHA, ejecuta:

```text
Prevalidar.command
```

Debe finalizar con:

```text
PREVALIDACIÓN COMPLETADA: ThermalBridge 0.7.0 RC3.12 (39)
```

Esta comprobación verifica estructura fuente, manifiestos congelados, sintaxis Bash, ausencia de artefactos generados versionados y exclusiones funcionales críticas. No sustituye el build nativo, la firma, los sensores ni las pruebas físicas.

## Validación nativa

En una Mac Apple Silicon, ejecuta mediante clic derecho → **Abrir**:

```text
Validar.command
```

Debe finalizar con:

```text
VALIDACIÓN COMPLETADA: ThermalBridge 0.7.0 RC3.12 (39)
```

El validador comprueba:

- hashes Beta 6 y RC3.12;
- ausencia de Game Mode y QoS-first;
- typecheck Swift completo;
- suites de lógica, sensores, CrossOver, energía, QoS y telemetría;
- sintaxis C y scripts;
- análisis estático de la carga IOHID;
- autopruebas de los guardianes;
- capacidad IOReport sin suscripción;
- aplicación y helpers exclusivamente ARM64;
- firma individual, firma profunda e identificador del bundle;
- muestra física del sensor;
- ZIP versionado y verificable del proyecto fuente.

Después ejecuta `PROTOCOLO_ACEPTACION_RC312.md`. El build y las pruebas físicas requieren macOS y una Mac Apple Silicon.

## Instalación

Solo después de aprobar la validación:

```text
Instalar_en_Aplicaciones.command
```

La aplicación se instala en `~/Applications/ThermalBridge.app`. La firma es local ad-hoc y la primera apertura puede requerir clic derecho → **Abrir**.

## ZIP del proyecto

Cada validación correcta genera automáticamente un ZIP versionado del proyecto fuente en `releases/`. El nombre contiene la versión, la candidata y el build, por ejemplo:

```text
ThermalBridge_v0.7.0-RC3.12-build39-project.zip
```

El paquete excluye `.build`, `dist`, metadatos locales, el registro transitorio de compilación y ZIP anteriores. También puede generarse manualmente mediante:

```text
Empaquetar_Proyecto.command
```

## Criterio para 0.7.0 final

RC3.12 puede promoverse sin cambios cuando:

- compila y firma correctamente en el equipo objetivo;
- no reproduce la regresión de Beta 7;
- permite seleccionar y asociar el nuevo juego aunque CrossOver oculte su `.exe`;
- completa sesiones Utility y Maintenance sin caída abrupta nueva;
- restaura procesos, políticas y pantalla en las rutas probadas;
- no aparecen fallos críticos durante el periodo de aceptación.

Cualquier cambio de fuente exige una nueva candidata.

## Desarrollo y reportes

- Consulta `CONTRIBUTING.md` antes de modificar una fuente congelada o abrir un pull request.
- Usa la plantilla de incidencias para reportar errores reproducibles sin exponer rutas personales ni telemetría privada.
- Consulta `SECURITY.md` para informar vulnerabilidades y conocer las medidas básicas de recuperación.
- La comprobación automática de GitHub valida integridad SHA-256, sintaxis de scripts, permisos ejecutables y ausencia de funciones excluidas. No reemplaza `Validar.command` en Apple Silicon.

## Versión

- Aplicación: `0.7.0 RC3.12`.
- Compilación: `39`.
- Base inmediata: RC3.11 build 38.
- Base térmica: Beta 6 build 19.
- Arquitectura: Apple Silicon ARM64.
- macOS mínimo: 14.0.
