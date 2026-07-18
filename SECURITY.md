# Seguridad

ThermalBridge actúa sobre procesos locales mediante políticas de macOS y señales `SIGSTOP`/`SIGCONT`. También puede cambiar temporalmente el modo de refresco de la pantalla. Aunque incorpora restauración y guardianes independientes, debe tratarse como software candidato y probarse de forma controlada.

## Reportar una vulnerabilidad

No publiques en una incidencia abierta información que permita explotar el sistema, datos personales, telemetría sin depurar ni rutas privadas. Utiliza la opción **Report a vulnerability** de la pestaña **Security** del repositorio cuando esté habilitada. Si todavía no está disponible, contacta al mantenedor por un canal privado antes de divulgar detalles.

Incluye, cuando sea seguro hacerlo:

- versión y build exactos;
- modelo de Mac y versión de macOS;
- condiciones mínimas para reproducir el problema;
- impacto observado;
- registros depurados de datos personales.

## Recuperación operativa

Si un juego queda suspendido, cierra ThermalBridge y vuelve a abrir el juego. Si el problema persiste, termina los procesos afectados desde Monitor de Actividad o reinicia macOS. No ejecutes comandos de señales sobre PID desconocidos.

Los binarios generados localmente usan firma ad-hoc. Revisa el código y ejecuta `Validar.command` en Apple Silicon antes de instalar una compilación propia.
