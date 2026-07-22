# Protocolo de aceptación — ThermalBridge 0.7.0 RC3.13

## Regla de la candidata

RC3.13 es una versión congelada. Si se modifica cualquier fuente después de iniciar este protocolo, el resultado deja de pertenecer a RC3.13 y debe publicarse como una nueva candidata o volver a beta.

## 1. Validación nativa obligatoria

1. Cierra cualquier ThermalBridge anterior.
2. Ejecuta `Validar.command` mediante clic derecho → **Abrir**.
3. Conserva `validation_build.log`.
4. Confirma que `releases/` contiene el ZIP versionado del proyecto.
5. Exige como última línea de resultado:

```text
VALIDACIÓN COMPLETADA: ThermalBridge 0.7.0 RC3.13 (40)
```

La candidata queda bloqueada si falla un hash, typecheck, prueba, helper, arquitectura, firma o muestra térmica.

## 2. Instalación limpia sobre la versión anterior

1. Detén el control de la versión instalada.
2. Cierra ThermalBridge normalmente.
3. Ejecuta `Instalar_en_Aplicaciones.command` desde RC3.13.
4. Abre `~/Applications/ThermalBridge.app`.
5. Confirma que se conservan el juego objetivo, botella, perfil, objetivos térmicos y toggles compatibles.
6. Confirma que Game Mode no aparece como opción activa.

No elimines preferencias antes de esta prueba: la migración forma parte de la aceptación.

## 3. Selección de proceso anidado sin `.exe`

1. Abre un juego o launcher que cree procesos anidados dentro de CrossOver.
2. Pulsa **Actualizar** y confirma que aparecen procesos relacionados del árbol aunque estén clasificados como launcher o ayudante.
3. Selecciona el proceso estable que corresponda al contenedor real del juego y pulsa **Usar selección**.
4. Sin escribir `.exe`, inicia el control y confirma que se controla esa sesión y sus descendientes.
5. Cierra el proceso seleccionado y confirma que ThermalBridge desarma la sesión manual sin rearmar autoaplicación persistente.
6. Repite con el `.exe` escrito o elegido mediante **Buscar .exe…** y confirma que la autoaplicación queda armada solo entonces.

## 4. Selección de un juego con `.exe` oculto

1. Abre el juego que RC2 no mostraba.
2. Pulsa **Actualizar** y verifica que aparece al menos un `Proceso CrossOver sin .exe` asociado al árbol correcto.
3. Escribe el nombre exacto del ejecutable con extensión `.exe`.
4. Selecciona el host que corresponde al juego y pulsa **Usar selección**.
5. Inicia el control y confirma que el PID elegido permanece asociado durante la sesión.
6. Ejecuta `Diagnostico_CrossOver.command` y conserva la sección de árboles completos.

No se debe seleccionar automáticamente un helper ambiguo. Si aparecen varios hosts neutros, usa CPU, PID y árbol del diagnóstico para confirmar el principal.

## 5. Sesión de referencia Utility

Usa el mismo juego, botella, escena, resolución y límites empleados para aprobar Beta 11.

1. Selecciona Utility como clamp de lanzamiento.
2. Mantén apagada la reducción de refresco.
3. Ejecuta una sesión continua de 30 minutos.
4. Registra temperatura máxima CPU/GPU, actividad aplicada, estabilidad de audio y ritmo visible.
5. Detén el control y confirma que actividad, políticas y procesos quedan liberados.

Criterio: no debe aparecer una caída abrupta nueva ni quedar un proceso suspendido.

## 6. Sesión Maintenance explícita

Solo si Maintenance forma parte de tu uso previsto:

1. Selecciónalo manualmente antes de abrir CrossOver.
2. Ejecuta la misma escena durante 30 minutos.
3. Compara con Utility y con la referencia Beta 6/Beta 11/RC1/RC2.
4. Detén el control y cierra la aplicación.

Criterio: no se admite la regresión de Beta 7. Maintenance puede cambiar la planificación, pero no debe provocar una caída abrupta introducida por ThermalBridge.

## 6. Guardián de pantalla

Ejecuta esta sección únicamente si la pantalla publica un modo compatible de hasta 60 Hz. Guarda previamente tu trabajo.

1. Anota resolución y refresco originales.
2. Activa la palanca GPU y provoca dominancia térmica GPU.
3. Confirma que aparece el guardián activo y que la resolución no cambia.
4. Detén el control: el modo original debe volver.
5. Repite la reducción y fuerza la salida únicamente de `ThermalBridge` desde Monitor de Actividad.
6. Espera hasta dos segundos y confirma la restauración por `TBDisplayGuardian`.

Si no existe un modo compatible, registra `SKIP` con el modelo de pantalla. Un fallo de restauración es bloqueante.

## 7. Sensores y degradación

1. Ejecuta `Diagnostico_Temperatura.command`.
2. Conserva la lista de sensores y valores máximos.
3. Confirma que una capacidad IOHID o IOReport ausente no impide funcionar con las fuentes restantes.
4. Reinicia el sensor desde la aplicación y comprueba que la lectura vuelve.

## 8. Telemetría y privacidad

Revisa el JSONL más reciente en:

```text
~/Library/Application Support/ThermalBridge/Telemetry
```

Debe contener decisiones, energía/QoS cuando estén disponibles y eventos de seguridad. No debe contener rutas de usuario, argumentos completos, imágenes o contenido visual. No debe crear eventos nuevos de Game Mode.

## 9. Periodo de observación

Mantén RC3.13 instalada durante al menos tres sesiones reales adicionales o 24 horas de uso normal, lo que ocurra después. Registra:

- cierres inesperados;
- procesos que no se reanudan;
- restauraciones fallidas;
- pérdida permanente de sensores;
- caída abrupta de ritmo no observada en Beta 11;
- crecimiento anormal de telemetría o consumo en reposo.

## Decisión

Promover a `0.7.0 final` solo si:

- todos los pasos obligatorios pasan;
- los `SKIP` corresponden exclusivamente a capacidades físicas ausentes;
- no existe ningún fallo crítico o de restauración;
- no se requiere cambiar una fuente.

Si una fuente debe cambiar, abrir RC4 con un nuevo manifiesto SHA-256.
