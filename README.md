# Ollama Adreno Termux

**Ollama con aceleración Qualcomm Adreno en Android sin root: OpenCL nativo y Vulkan.**

Estado: experimental, probado por un usuario en **POCO F8 Ultra / Adreno 840 / Android 16 / Termux ARM64**. No se promete compatibilidad con otros teléfonos. No requiere PC ni root. No incluye modelos, binarios ni drivers Qualcomm.

## Resultado observado en hardware real

Modelo local Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf, importado como `qwen35-4b-uncensored`; contexto configurado: 73.728.

| Backend | Capas GPU | Prefill | Generación | GPU busy | CPU runner |
|---|---:|---:|---:|---:|---:|
| Vulkan | 33/33 | 2,36 tok/s | 12,79 tok/s | 94,9% | 81,7% |
| OpenCL | 33/33 | 99,43 tok/s | 17,33 tok/s | 95,1% | 207,5% |

Ambos procesos abrieron `/dev/kgsl-3d0`, cargaron drivers Qualcomm y completaron inferencia. OpenCL fue ~35,5% más rápido en generación en esa pasada. **Una sola medición, sin línea base CPU: no es un benchmark universal.** La diferencia de prefill requiere repetición. Contexto configurado no significa haber probado un prompt de 73.728 tokens. Ver [evidencia y límites](docs/VALIDATION.md).

## Requisitos

- Termux ARM64 con repositorios mantenidos; acceso a Internet para paquetes y fuentes.
- Android con `/system/lib64/libvulkan.so` y `/dev/kgsl-3d0` accesibles. OpenCL depende de los drivers del fabricante y los namespaces Android.
- Espacio para fuentes, compilación, cachés y modelos. Importar un GGUF puede copiar sus pesos: reserva al menos otro tanto como su tamaño, además del espacio de compilación.
- Modelo GGUF compatible con llama.cpp b12177 y su licencia aceptada por ti.
- Mantén Termux en primer plano al compilar, evita sobrecalentamiento y restricciones de batería. No se garantiza evitar cierres de Android.

## Instalación desde un clon o ZIP

No ejecutes comandos desde una URL desconocida mediante `curl | bash`. Descarga o clona este repositorio, revisa los scripts y entra en su carpeta.

```bash
bash install.sh
```

Instala dependencias y compila en `~/ollama-vulkan-exp`. **No descarga ningún modelo y no ejecuta aún la auditoría.** No reemplaza `$PREFIX/bin/ollama`; sí instala/actualiza dependencias de Termux. No uses `--recompilar` salvo que quieras forzar el build.

Si tu instalación anterior ya funciona, el build intenta reutilizar artefactos; conserva un respaldo antes de cambiar de versión.

### Importar tu GGUF

Concede acceso a almacenamiento si aún no lo hiciste:

```bash
termux-setup-storage
bash scripts/import-gguf.sh \
  "$HOME/storage/downloads/models/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf" \
  qwen35-4b-uncensored
```

El nombre y la carpeta distinguen mayúsculas. Puedes importar otro GGUF con otro nombre. El almacén predeterminado es `~/.ollama/models`; también se respeta `OLLAMA_MODELS`. Usa la misma variable al importar, medir y servir.

### Verificar GPU

```bash
bash scripts/benchmark.sh qwen35-4b-uncensored
```

Prueba Vulkan y OpenCL si está disponible; CPU solo si existe `$PREFIX/bin/ollama`. Produce `~/ollama-vulkan-exp/evidencia-adreno840.txt` y logs. Puede escribir también una copia del informe en `~/storage/downloads/`.

Para cambiar el contexto de la medición:

```bash
CTX_TARGET=32768 bash scripts/benchmark.sh qwen35-4b-uncensored
```

Esto cambia esa solicitud, no el Modelfile ni la configuración de otros programas. La selección automática prioriza generación, no consumo energético ni prefill.

### Servir con OpenCL (recomendado en el dispositivo probado)

Servidor en primer plano, puerto local 11435:

```bash
~/ollama-vulkan-exp/bin/ollama-adreno-opencl-serve
```

En otra sesión de Termux:

```bash
OLLAMA_HOST=127.0.0.1:11435 \
  ~/ollama-vulkan-exp/bin/ollama run qwen35-4b-uncensored
```

Vulkan: usa `ollama-adreno-vulkan-serve`. No habilites ambos backends como dos GPUs independientes: son la misma Adreno.

Para integrar con un agente, configura su endpoint y modelo. El proyecto **no instala un agente**. El helper heredado `conectar-poco-agent-gpu --opencl` usa el puerto 11434 y puede detener servidores Ollama existentes: revisa el script antes de usarlo.

## Diseño y seguridad

- Fuentes: Ollama `v0.40.16`, llama.cpp `b12177`, parches Vulkan y puente OpenCL SPHAL.
- Concurrencia reducida: Ninja `-j2`, generador de shaders con dos workers, Go `-p 2`. Mitiga presión de recursos; no prueba la causa de un SIGKILL.
- OpenCL: carga bibliotecas del fabricante por namespace `sphal`; si falla, puede intentar copias locales y RPATH en la carpeta experimental. **Nunca modifica `/vendor`.** No distribuyas esas copias propietarias.
- OpenGL ES es solo diagnóstico: este proyecto no tiene backend GGML GLES.
- El build modifica fuentes dentro del árbol experimental con `git checkout`/`git clean`; no guardes ahí cambios personales sin respaldo.
- Los modelos locales no se envían a un servicio de inferencia externo por estos scripts. Las descargas de fuentes/paquetes sí requieren red.
- No expongas Ollama a Internet: usa loopback. Un modelo “uncensored” no garantiza calidad ni seguridad.

## Detener y retirar

Un servidor en primer plano se detiene con Ctrl+C. Antes de retirar archivos, detén también servidores lanzados en segundo plano. El helper `restaurar-poco-agent-cpu` detiene el experimental, pero **no inicia automáticamente un servidor CPU**.

La instalación experimental está en `~/ollama-vulkan-exp`. Si quieres retirarla, respalda informes y confirma que no guardaste datos propios ahí antes de borrar esa carpeta. **No borres `~/.ollama`**: contiene los modelos. No hay desinstalación automática de dependencias compartidas.

## Documentación

- [Solución de problemas](docs/TROUBLESHOOTING.md)
- [Validación y limitaciones](docs/VALIDATION.md)
- [Publicación desde Termux](docs/PUBLISH.md)
- [Fuentes y licencias de terceros](THIRD_PARTY_NOTICES.md)

Licencia MIT para scripts/documentación originales del proyecto; dependencias bajo sus propias licencias. Proyecto independiente, no afiliado a Ollama, Qualcomm o Xiaomi.
