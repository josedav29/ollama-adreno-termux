# Publicar desde Termux

Este archivo no crea nada automáticamente ni requiere compartir credenciales con el asistente.

1. Extrae el ZIP y entra en `ollama-adreno-termux`.
2. Revisa contenido, licencia y el alcance experimental.
3. Instala herramientas e inicia sesión usando el flujo de GitHub CLI:

```bash
pkg install git gh
 gh auth login
```

No pegues tokens en el chat. Si usas autenticación web, sigue las instrucciones de tu propia terminal.

```bash
python3 tests/check.py
git init -b main
git add .
git commit -m "Initial experimental Adreno Termux installer"
gh repo create ollama-adreno-termux --public --source=. --remote=origin --push
```

Git puede pedir tu nombre y correo: configúralos localmente con los datos que decidas hacer públicos. Para un repositorio privado, cambia `--public` por `--private`. Si ese nombre ya existe, elige otro. No subas GGUF, bibliotecas vendor, credenciales ni logs privados.

Opcional: tras volver a probar esta versión en Android, crea una etiqueta/release experimental. No la anuncies como versión estable solo porque pase la prueba estática.
