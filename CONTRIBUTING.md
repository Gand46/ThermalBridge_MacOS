# Contribuir a ThermalBridge

Gracias por ayudar a mejorar ThermalBridge. Esta rama representa una candidata congelada: **0.7.0 RC3.5 build 32**.

## Regla de congelación

No se deben modificar silenciosamente los archivos incluidos en `RC35_FROZEN_SHA256.txt`. Cualquier cambio funcional posterior debe:

1. partir de una rama nueva;
2. incrementar la candidata o la versión;
3. actualizar el changelog y los manifiestos correspondientes;
4. completar nuevamente la validación nativa y el protocolo de aceptación.

## Entorno necesario

- Mac con Apple Silicon.
- macOS 14.0 o posterior.
- Command Line Tools de Xcode.
- CrossOver únicamente para las pruebas físicas de detección y control.

## Validación

Antes de proponer cambios, ejecuta:

```text
Validar.command
```

La validación completa compila exclusivamente para ARM64, ejecuta las suites Swift y C, comprueba firmas y arquitectura, valida los sensores físicos y genera un ZIP reproducible del proyecto.

En otros sistemas solo pueden comprobarse los manifiestos SHA-256 y la sintaxis de los scripts. Esto no sustituye la validación nativa.

## Pull requests

Describe con claridad:

- qué cambió y por qué;
- qué comportamiento puede verse afectado;
- qué validaciones se ejecutaron;
- modelo de Mac, versión de macOS, Swift y CrossOver usados en pruebas físicas.

No incluyas telemetría, nombres de usuario, rutas personales, nombres de botellas o juegos privados sin depurarlos previamente.
