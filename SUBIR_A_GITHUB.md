# Subir ThermalBridge RC3.5 a GitHub

Este paquete está preparado para usarse como raíz de un repositorio. Conserva las fuentes congeladas de **ThermalBridge 0.7.0 RC3.5 build 32** y los archivos mínimos de colaboración y comprobación para GitHub.

## Crear el repositorio

1. Crea un repositorio vacío en GitHub; se recomienda el nombre `ThermalBridge`.
2. No marques las opciones para generar README, licencia ni `.gitignore`, porque ya están incluidos.
3. Descomprime este ZIP y abre Terminal dentro de la carpeta resultante.
4. Ejecuta, sustituyendo la URL por la del repositorio creado:

```bash
git init -b main
git add .
git commit -m "Publicar ThermalBridge 0.7.0 RC3.5 build 32"
git remote add origin https://github.com/USUARIO/ThermalBridge.git
git push -u origin main
```

Si Git solicita identidad antes del commit, configura tu nombre y el correo asociado a GitHub con `git config user.name` y `git config user.email`.

## Comprobaciones incluidas

Al recibir un push o pull request, GitHub Actions verifica:

- los manifiestos SHA-256 de Beta 6 y RC3.5;
- la sintaxis de todos los scripts;
- los permisos ejecutables;
- la ausencia en las fuentes de funciones retiradas.

La comprobación automática no sustituye `Validar.command`, que debe ejecutarse en una Mac Apple Silicon para compilar, probar sensores, revisar arquitectura y validar las rutas físicas de restauración.

## Publicar una descarga

Después de completar la aceptación física, crea una Release en GitHub y adjunta el ZIP de proyecto generado por `Empaquetar_Proyecto.command`. No publiques una compilación `.app` como validada si sus firmas, arquitectura y pruebas físicas no fueron comprobadas en el equipo objetivo.
