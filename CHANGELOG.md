# Changelog

## 0.7.0 RC3.7 build 34 — selección manual ampliada por árbol CrossOver

- Parte de RC3.6 build 33 sin modificar el motor térmico, el limitador ni los valores predeterminados.
- Permite seleccionar manualmente procesos relacionados del árbol CrossOver aunque estén clasificados como launcher o ayudante.
- Permite confirmar un proceso del árbol sin `.exe` como asociación explícita de sesión; no arma autoaplicación persistente hasta tener un `.exe` válido.
- Conserva la protección contra autoactivar helpers ambiguos: la recuperación automática sigue filtrando launchers y ayudantes salvo selección explícita.
- Actualiza avisos de UI para distinguir autoaplicación por `.exe` de control manual por árbol en la sesión actual.
- Compilación 34.

## 0.7.0 RC3.6 build 33 — prevalidación portable y limpieza de artefactos

- Parte de RC3.5 build 32 sin modificar el motor térmico, el limitador, la selección CrossOver ni los defaults de usuario.
- Añade `Prevalidar.command` para ejecutar comprobaciones estáticas portables antes de la validación nativa en Apple Silicon.
- Separa explícitamente prevalidación de build/firma/sensores/pruebas físicas para evitar declarar como nativo un resultado de contenedor.
- Añade `.gitignore` y retira del control de versiones `.build`, `dist`, `releases`, ZIP generados y `validation_build.log`.
- Sustituye el manifiesto congelado por `RC36_FROZEN_SHA256.txt`, incluyendo fuentes, pruebas, scripts operativos, documentación de release y configuración de bundle.
- Compilación 33.

## 0.7.0 RC3.5 build 32 — integración auditada y paquete limpio

- Parte de RC3 build 30 sin modificar objetivos, histéresis, integral, recuperación ni porcentajes del motor térmico.
- Integra los cambios funcionales auditados del build 31 sin incorporar artefactos generados ni código legado.
- Conserva instantáneas por identidad para retirar Darwin Background aunque un proceso vivo falte transitoriamente del último censo.
- Drena la cola FIFO de control antes de la restauración final, impidiendo que una solicitud pendiente reactive Darwin Background durante el cierre.
- Mantiene rastreados los fallos de restauración y los registra explícitamente.
- Evita un cierre por identidades duplicadas en el censo y prueba que la muestra más reciente prevalece sobre el respaldo cacheado.
- Refuerza las comprobaciones de los punteros IOHID cargados mediante `dlsym`.
- Ejecuta el analizador estático de Clang sobre el sensor y distingue fallos reales de salida informativa.
- Alinea el protocolo de instalación con la ruta real `~/Applications/ThermalBridge.app`.
- Genera automáticamente un ZIP versionado del proyecto fuente después de cada validación correcta.
- Sustituye el manifiesto congelado RC3 por `RC35_FROZEN_SHA256.txt` y elimina protocolos beta/UI histórica del paquete.
- Endurece GitHub Actions con permisos mínimos, credenciales no persistentes y una acción fijada a SHA completo.
- Compilación 32.

## 0.7.0 RC3 — selección fiable de hosts CrossOver opacos

- Parte de RC2 build 29 sin modificar el motor térmico ni los mecanismos de control.
- Corrige la exclusión de procesos cuyo host no publica `.exe`, `wine`, una ruta CrossOver ni argv reconocible.
- Construye un índice PID→proceso por muestra y clasifica descendientes de un runtime CrossOver/Wine.
- Mantiene seleccionables los hosts neutros para asociar un `.exe` escrito manualmente mediante **Usar selección**.
- Conserva la exigencia de evidencia o selección explícita antes de controlar un host ambiguo.
- Precompila las expresiones regulares de ejecutables y botellas usadas por `ProcessSnapshot`.
- Amplía `Diagnostico_CrossOver.command` con todos los descendientes de los árboles detectados.
- Corrige el falso negativo de firma provocado por `pipefail` y `grep -q` después de `codesign`.
- Elimina el warning Swift por resultado ignorado al restaurar la pantalla en `deinit`.
- Compilación 30.

## 0.7.0 RC2 — eficiencia interna del censo de procesos

- Parte de RC1 build 28 sin modificar el motor térmico ni los mecanismos de control.
- Reutiliza durante toda la sesión el búfer de 4096 registros `TBProcessInfo`.
- Elimina la reserva e inicialización repetida de aproximadamente 21,5 MiB por muestra.
- Consulta `PROC_PIDTASKINFO` únicamente como fallback cuando `proc_pid_rusage` V6, V3 y V2 no están disponibles para el proceso.
- Cachea por instancia el UID actual y el máximo de CPU calculado desde los procesadores activos.
- Mantiene sin cambios Maintenance, Audio Safe, Burst, porcentajes, objetivos, histéresis, integral, políticas y temporización.
- Sustituye el manifiesto congelado de RC1 por `RC2_FROZEN_SHA256.txt`.
- Compilación 29.

## 0.7.0 RC1 — candidata congelada

- Promueve Beta 11 build 27 a candidata de lanzamiento sin añadir mecanismos térmicos nuevos.
- Conserva retirado Game Mode y mantiene la preferencia heredada como dato eliminado durante la migración.
- Conserva la palanca GPU desactivada por defecto y protegida por `TBDisplayGuardian`.
- Mantiene IOReport como sonda observacional sin suscripción ni entrada al controlador.
- Añade `RC1_FROZEN_SHA256.txt`, que verifica todas las fuentes ejecutables de la candidata.
- Conserva además el manifiesto de la línea térmica Beta 6 para detectar cualquier regresión histórica.
- Exige binarios exclusivamente ARM64 para la aplicación y sus cinco helpers.
- Verifica firma individual de cada ejecutable, firma profunda de la aplicación e identificador del bundle.
- El validador confirma que Game Mode y QoS-first permanecen ausentes.
- Añade protocolo de aceptación y lista de bloqueo para decidir la promoción a 0.7.0 final.
- Compilación 28.

## 0.7.0 Beta 11 — retirada de Game Mode y restauración reforzada

- Retira de la interfaz y de las fuentes ejecutables toda invocación experimental de Game Mode.
- Elimina al iniciar la preferencia de Game Mode que podía quedar guardada por Beta 10.
- No busca ni ejecuta herramientas de Xcode para modificar políticas globales de juego.
- Conserva la palanca opcional de refresco GPU, desactivada por defecto y aislada del motor térmico.
- Añade `TBDisplayGuardian`, un proceso independiente que conserva las características del modo original.
- El guardián detecta la terminación del proceso principal mediante su relación de proceso padre e intenta restaurar la pantalla.
- Si el guardián no puede iniciarse, ThermalBridge revierte inmediatamente la reducción; la palanca no queda activa sin protección.
- La restauración normal ocurre antes de terminar el guardián, evitando una ventana sin responsable de recuperación.
- Mantiene IOReport como sonda de símbolos sin suscripción, muestreo o entrada al controlador.
- Añade autoprueba del parser y selector de modo del guardián, además de pruebas de dominancia GPU e histéresis.
- Amplía el validador para fallar si reaparece código ejecutable de Game Mode.
- Compilación 27.

## 0.7.0 Beta 10 — integraciones opcionales y reversibles

- Conserva byte a byte el motor térmico, `TBCPULimiter`, `TBWatchdog` y el planificador de políticas de la línea estable Beta 6.
- Añade una solicitud experimental de Game Mode mediante `gamepolicyctl` cuando Xcode publica la herramienta.
- Devuelve Game Mode a `auto` al desactivar la opción, detener el control, terminar el juego o cerrar normalmente la aplicación.
- Añade una palanca GPU opcional que reduce la pantalla principal a un modo de hasta 60 Hz con la misma resolución mediante CoreGraphics.
- La palanca de pantalla solo entra cuando la GPU alcanza su objetivo y domina el exceso térmico; usa la histéresis existente para restaurar el modo original.
- Ante pérdida de sensores, fin del juego o detención del control, intenta restaurar inmediatamente el modo de pantalla original.
- Ambas integraciones nuevas permanecen desactivadas por defecto y no participan en el cálculo de actividad del motor térmico.
- Registra aplicaciones, indisponibilidad y restauraciones como eventos de seguridad en la telemetría JSONL.
- Añade una sonda de capacidad IOReport mediante `dlopen`/`dlsym`; no crea suscripciones ni usa IOReport como entrada de control en esta versión.
- Añade pruebas deterministas para dominancia GPU, histéresis, desactivación y pérdida del sensor.
- Amplía `Validar.command` con typecheck de los nuevos archivos, suite Beta 10 y auditoría de restauración.
- Compilación 26.

## 0.7.0 Beta 9 — evidencia y seguridad

- Mantiene byte a byte el motor térmico, `TBCPULimiter`, `TBWatchdog` y el planificador de políticas de Beta 6.
- Amplía `proc_pid_rusage` con fallback V6 → V3 → V2.
- Registra `ri_energy_nj` como energía directa y conserva energía facturada/servida como métricas separadas.
- Calcula deltas de QoS efectivo por identidad PID+fecha de inicio y los agrega sobre el árbol del juego.
- Solo declara QoS `confirmed` cuando los contadores del kernel observan tiempo CPU en la clase solicitada.
- Añade los estados `confirmed`, `inferred`, `not_observed`, `unavailable` y `failed`.
- Eleva la telemetría JSONL al esquema 2 con energía, QoS efectivo, versión rusage y eventos de seguridad.
- Hace síncrona e idempotente la restauración de tiers, esperando también cualquier aplicación pendiente.
- Añade `TBLimiterGuardian`, que reanuda el árbol si el limitador o el controlador desaparecen.
- Carga dinámicamente las funciones privadas IOHID con `dlopen`/`dlsym` y conserva SMC como degradación segura.
- Añade pruebas de deltas, reutilización de PID, evidencia QoS, privacidad JSONL y recuperación del guardián.
- Corrige la inferencia genérica de `compactMap`/`max` con Swift 6.3 mediante tuplas tipadas explícitamente.
- Corrige la fixture V2: energía y las siete clases QoS quedan ausentes (`nil`) como en la ruta real.
- Añade una regresión V3 que exige QoS efectivo disponible y energía V6 ausente.
- Compilación 25.

## 0.7.0 Beta 8 — recuperación de la línea base Beta 6

- Reconstruida directamente desde Beta 6; Beta 7 no es ancestro de esta versión.
- Conserva byte a byte el motor térmico, `TBCPULimiter`, `TBWatchdog`, `ProcessController` y `MacProcessPolicy` de Beta 6.
- Mantiene Utility como clamp inicial y Maintenance como elección explícita del usuario.
- Excluye la gracia QoS-first, su integral durante la espera, el matcher de herencia y la omisión de tiers introducidos en Beta 7.
- Añade cinco trazas doradas para respuesta ascendente, pérdida de sensor, recuperación, potencia predictiva y emergencia crítica.
- Añade un manifiesto SHA-256 de la línea base y hace que `Validar.command` falle si cambia un componente congelado.
- Añade telemetría JSONL de observación por sesión, en cola independiente y sin rutas, argumentos, nombres de usuario ni imágenes.
- Registra configuración, temperatura, potencia disponible, estado térmico, actividad solicitada/aplicada, modo del limitador y motivo.
- Conserva hasta 20 sesiones en `~/Library/Application Support/ThermalBridge/Telemetry`.
- Corrige `MacPolicyProbe`: PASS/DEGRADED/SKIP/FAIL y fallo no cero cuando una política aplicada no puede restaurarse.
- Añade protocolo A/B Beta 6–Beta 8 para validar Maintenance y frame pacing en la Mac.
- Corrige el acceso al estado de telemetría desde la extensión de control automático sin exponer el setter públicamente.
- La validación temprana usa `swiftc -typecheck` sobre la aplicación completa para detectar errores semánticos entre archivos antes del build.
- Compilación 22.

## 0.7.0 Beta 6 — QoS validado y protección de audio

- Corrige la afirmación de que QoS fuerza un proceso a E-cores: se documenta como orientación de prioridad, throughput, latencia y eficiencia.
- Conserva el clamp QoS de lanzamiento y los tiers sobre procesos existentes como capa opcional y tolerante a fallos.
- Mantiene todos los controles térmicos y de detección desarrollados hasta Beta 5.
- Añade `ActivityLimiterPulseMode` con modos `audioSafe` y `burst`.
- El modo protegido detiene solo el host principal y mantiene activos los descendientes separados de audio/red.
- Sustituye la pausa de hasta 26 ms del ciclo de 40 ms por pulsos protegidos de hasta 2 ms.
- Usa `mach_absolute_time` y `mach_wait_until` para temporización monotónica en Apple Silicon.
- Permite cambiar porcentaje y modo sin reiniciar el helper.
- Restaura todo el árbol cuando cambia el modo o termina el controlador.
- En estado térmico serio/crítico prevalece automáticamente el freno completo del árbol.
- Añade pruebas matemáticas del ratio de actividad y de la pausa máxima.
- Añade autoprueba C `TBCPULimiter --self-test` a `Validar.command`.
- Compilación 19.

## 0.7.0 Beta 5 — detección CrossOver estable

- Corrige el tamaño real entregado a `proc_listpids` para impedir muestras truncadas.
- Añade caché de nombre, ruta y argumentos por identidad de proceso.
- Captura argumentos de todos los descendientes de un árbol CrossOver en una segunda fase.
- Lee `WINEPREFIX`, `CX_BOTTLE`, `CX_BOTTLE_PATH` y `CX_ROOT` para identificar la botella.
- Conserva procesos omitidos durante 3,5 s solo mientras PID y fecha de inicio sigan siendo válidos.
- Añade cinco muestras de gracia durante reemplazos de host Wine.
- Elimina la captura automática del `.exe` al cambiar la selección.
- Conserva el ejecutable escrito manualmente al asociar un preloader.
- Empareja el objetivo contra todos los `.exe` hallados en el comando.
- Mantiene rechazo estricto de botellas distintas en el matcher base y añade recuperación no ambigua para asociaciones erróneas heredadas de Beta 4.
- Selecciona de forma determinista un host dentro de la botella cuando argv oculta el juego.
- Recuerda el host confirmado con **Usar selección** durante la sesión, incluso si el `.exe` queda oculto después.
- Repara una botella heredada incorrectamente solo cuando el `.exe` exacto es único y añade **Olvidar botella**.
- Mantiene el selector en orden estable de primera aparición para evitar saltos visuales.
- Añade `ProcessObservationCacheTests` y amplía las pruebas de detección y matching.
- `Diagnostico_CrossOver.command` toma ocho muestras consecutivas con argumentos sin truncar.
- Compilación 18.

# Cambios

## 0.7.0 Beta 3 — validación JSON nativa

- Corrige el falso error `Unexpected character { at line 1` al validar una muestra JSON real del sensor.
- Sustituye `plutil -lint -` por `Foundation.JSONSerialization`.
- Añade `Tests/SensorOutputProbe.swift`, que comprueba estructura, campos y tipos del JSON térmico.
- Separa explícitamente el diagnóstico de sensores (`stderr`) de la muestra JSON (`stdout`).
- Exige exactamente una línea JSON no vacía para `--samples 1`.
- Conserva la selección manual/automática del `.exe`, `TCMb`, las políticas macOS opcionales y el limitador térmico existente.
- Versión 0.7.0 Beta 3, compilación 16.

## 0.7.0 Beta 1 — políticas macOS y catálogo térmico MacThermal

- Añade control adaptativo mediante tiers de throughput y latencia de macOS.
- Aplica `TASK_OVERRIDE_QOS_POLICY` directamente al árbol del juego, sin modificar Wine ni D3DMetal.
- Restaura los overrides a `unspecified` al detener el control.
- Conserva el limitador dinámico de actividad, el estado térmico de macOS y la optimización de launchers.
- Añade cuatro niveles: Normal, Eficiencia, Restringida y Emergencia.
- Añade pruebas del planificador y una sonda real que aplica tier 4 al propio proceso y lo restaura.
- Corrige la exclusión de `TCMb`: la familia `TC*` entra ahora en CPU.
- Excluye `TCGC` de CPU y lo clasifica como GPU.
- Incorpora sensores IOHID `pACC`, `eACC`, `mACC` y `GPU MTR`.
- Permite funcionar con SMC, IOHID o ambas fuentes para M1–M5.
- Añade `--self-test` y `--list-sensors` al helper térmico.
- Amplía `Diagnostico_Temperatura.command` con validación específica de TCMb.
- Versión 0.7.0 Beta 1, compilación 14.

## 0.6.1 — control por máximo instantáneo de cada grupo térmico

- Sustituye la temperatura promedio como factor principal por el sensor individual más caliente de CPU y GPU en cada muestra.
- Añade el helper ARM64 integrado `TBTemperatureSensor`.
- Enumera claves AppleSMC y clasifica CPU mediante prefijos `Tp`, `Te`, `Ts`; GPU mediante `Tg`.
- Publica máximo, promedio, cantidad de sensores y nombre del sensor máximo para CPU/GPU.
- Conserva `macmon` como fuente opcional de potencia, uso y respaldo por promedio.
- Añade advertencia visible cuando el control cae al respaldo por promedio.
- Cambia la lógica a reducción preservando picos: el máximo instantáneo nunca se diluye mediante el promedio exponencial.
- Mantiene el suavizado únicamente para tendencia y recuperación térmica.
- Cambia los objetivos nuevos a 90 °C CPU y 85 °C GPU.
- Migra objetivos de 0.6.0 sumando 8 °C CPU y 7 °C GPU para compensar el cambio de semántica promedio→máximo.
- Muestra el nombre del sensor más caliente y el número de sensores leídos.
- Añade prueba específica que verifica que un pico de 101 °C reduce actividad aunque el suavizado previo sea bajo.
- Añade prueba real del helper SMC al final de `Validar.command`.
- Actualiza diagnóstico, documentación y menú de barra.
- Versión 0.6.1, compilación 13.

## 0.6.0 — control automático por temperatura CPU/GPU

- Reestructura la aplicación alrededor de un único modo térmico automático para CrossOver.
- Sustituye los perfiles fijos por objetivos independientes de temperatura promedio para CPU y GPU.
- Integra `macmon pipe` para temperatura, potencia y uso.
- Añade suavizado, tendencia, histéresis, reducción proporcional y recuperación lenta.
- Conserva detección de ejecutables, botellas, árboles y launchers de CrossOver.
