# Solución de problemas

## curl: cannot locate symbol SSL_set_quic_tls_early_data_enabled

Paquetes curl/OpenSSL desincronizados. No copies bibliotecas .so de otras instalaciones.

```bash
apt update && apt full-upgrade
```

Revisa cambios antes de aceptar: puede actualizar otros paquetes, incluido Ollama. Si persiste:

```bash
apt install --reinstall openssl libcurl curl
curl --version
```

No continúes si apt falla: conserva la salida completa.

## clang: command not found

El instalador actual instala clang antes de las sondas. Si falla la instalación, revisa repositorios/conexión. `pkg install clang` debe funcionar antes de seguir.

## binutils-is-llvm no disponible

La lista actual usa `llvm lld`, no el paquete antiguo.

## HTTP 404 / modelo no encontrado

Un GGUF descargado no es un modelo registrado. Usa `scripts/import-gguf.sh`. Verifica nombre exacto y `OLLAMA_MODELS`. El auditor actual muestra modelos disponibles y el cuerpo de errores HTTP de arranque/calentamiento; revisa también `logs/audit-*.log`.

## SIGKILL / signal 9

No permite atribuir por sí solo la causa a PhantomProcessKiller: también puede ser memoria u otra política Android. La compilación limita concurrencia. Mantén la app visible; revisa batería y temperatura. No se requiere root ni desactivar protecciones del sistema. Reintenta sin borrar el build incremental.

## OpenCL no disponible

El acceso depende de firmware y políticas del linker. Consulta `logs/01-cl-probe.txt`. Vulkan puede funcionar aunque OpenCL no lo haga. No instales drivers obtenidos de terceros ni reemplaces archivos del sistema.

## Sin fila CPU

No hay un binario original en `$PREFIX/bin/ollama`; no se puede afirmar mejora frente a CPU. El proyecto no instala otro Ollama solo para esta prueba.

## Memoria o respuestas incorrectas

Primero guarda el log, contexto y nombre del modelo. Prueba menor contexto explícitamente y verifica la compatibilidad del GGUF. Un texto generado y GPU busy no demuestran exactitud numérica. Valida tareas conocidas antes de confiar en un backend.

## Puertos

Importación: 11439. Auditoría: 11435/11436/11437. Servidores manuales: 11435 por defecto. Detén el servidor antes de medir. Los wrappers de benchmark e importación comprueban conflictos; el auditor interno debe invocarse preferentemente a través del wrapper.
