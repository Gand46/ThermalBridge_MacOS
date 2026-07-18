# Informe de auditoría e integración — RC3.5 build 32

Fecha de preparación: 18 de julio de 2026  
Base inmediata: ThermalBridge 0.7.0 RC3 build 30  
Fuente auditada: RC3.5 build 31  
Resultado: integración estática aprobada; validación nativa pendiente en Apple Silicon

## Procedencia e integridad

- El ZIP RC3.5 build 31 recibido superó la prueba de integridad del contenedor.
- La comparación se realizó contra la RC3 original conservada, no contra ramas posteriores.
- `BASELINE_BETA6_SHA256.txt` continúa validando los cuatro componentes históricos congelados.
- El manifiesto RC3 del build 30 se retiró del paquete porque, después de integrar cambios legítimos, sus hashes dejan de representar esta candidata.
- `RC35_FROZEN_SHA256.txt` cubre todas las fuentes ejecutables del build 32.

## Cambios funcionales aceptados del build 31

- Caché de instantáneas por identidad para restaurar Darwin Background cuando un proceso vivo falta transitoriamente del censo.
- Restauración final serializada después de drenar la cola FIFO de control.
- Registro explícito de restauraciones que no pudieron completarse.
- Comprobación defensiva de los punteros IOHID obtenidos con `dlsym`.
- Prueba de preferencia de la muestra actual y respaldo mediante caché.

## Correcciones añadidas durante la auditoría

- `ProcessRestorationResolver` ya no usa `Dictionary(uniqueKeysWithValues:)`; una muestra anómala con identidades repetidas no provoca una precondición fatal.
- La regresión comprueba que, ante duplicados, prevalece la instantánea más reciente.
- El analizador de Clang distingue entre fallo de ejecución, diagnósticos reales y salida informativa.
- El empaquetador excluye cualquier ZIP previo para impedir paquetes recursivos.
- GitHub Actions usa permisos de solo lectura, no persiste credenciales y fija `actions/checkout` a un SHA completo.

## Limpieza aplicada

- Retirado `LegacyUI/`, que no forma parte de la compilación actual.
- Retirados los protocolos Beta 8–11 ya superados.
- Retirados el protocolo, checklist y manifiesto congelado exclusivos de RC3.
- No se incluyen `.app`, binarios, `.build`, `dist`, `releases`, registros de validación, metadatos Git ni ZIP anidados.

## Límites de esta validación

El paquete build 31 incluía un informe que declaraba validación nativa en macOS, pero no incluía el registro bruto necesario para reproducirla. Además, el build 32 modifica una fuente y una prueba, por lo que aquella declaración no se transfiere automáticamente.

En este entorno se verifican integridad, diferencias, manifiestos, sintaxis Bash, estructura GitHub y contenido del paquete. La compilación Swift/C con SDK de macOS, las firmas ARM64, los sensores físicos y las pruebas de restauración reales deben completarse ejecutando `Validar.command` en una Mac Apple Silicon antes de publicar o instalar como candidata validada.
