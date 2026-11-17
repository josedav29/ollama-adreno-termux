# Comandos cortos y perfiles

## Actualizar instalacion existente sin recompilar ni reinstalar agentes

Desde la raiz del proyecto, en Termux:

```bash
bash scripts/setup-shortcuts.sh
```

Se crean ejecutables en `$PREFIX/bin`, que normalmente ya esta en PATH:

- `dsh`: DeepSeek Harness, navegador con URL/token impreso.
- `hrm`: Hermes, terminal.
- `oc`: OpenCode, terminal.
- `agentes-config menu`: selector y configuracion interactiva.
- `agentes-config show`: ver perfil solicitado y parametros.

Funcionan desde `~` o cualquier carpeta. Si hay un comando existente ajeno al proyecto, no se sobrescribe. `type -a dsh hrm oc` permite revisar conflictos, incluyendo aliases del shell. Estos atajos no instalan agentes: instala los que falten con `bash scripts/install-agents.sh`. El instalador ya ejecuta setup-shortcuts al finalizar.

## Original (predeterminado, probado con tu Qwen)

```bash
agentes-config select original
dsh
```

Conserva Ollama OpenCL en 11434. No introduce flags especulativos nuevos ni desactiva lo que Ollama pudiera autodetectar. No modifica pesos ni contexto original.

## MTP, DFlash y DFlash2: experimentales

```bash
agentes-config menu
```

Selecciona el perfil, escribe ruta GGUF objetivo, borrador cuando corresponda, contexto y cantidad de tokens propuestos. No descarga modelos. Se comprueba existencia de archivos, pero **no se verifica compatibilidad interna ni formato GGUF por su mera existencia**. MTP requiere cabeza integrada compatible o borrador apropiado. DFlash/DFlash2 requieren su borrador compatible. Ambos usan `draft-dflash`: el motor distingue la variante del checkpoint; no cambia DFlash a DFlash2 por elegir otro nombre en el menu.

Alternativa no interactiva (sustituye rutas por archivos REALES):

```bash
agentes-config set mtp --target /ruta/modelo-con-mtp.gguf --context 8192 --draft-tokens 2
agentes-config select mtp
```

Para DFlash/DFlash2, `set dflash` o `set dflash2` y agrega `--draft /ruta/borrador-compatible.gguf`.

**No se afirma compatibilidad del borrador oficial Qwen con tu HauhauCS. No descargar un borrador Qwen3.8-27B para tu 4B.** No se ha probado ninguna ruta especulativa en tu telefono; solo el descubrimiento del backend y presencia de flags.

### Como funcionan realmente

Original usa Ollama. Los experimentales usan **llama-server directo**, con OpenCL/plugin explicito, una ranura y puertos locales 11441/11442/11443. Los agentes reciben su endpoint `/v1`, con un alias equivalente al nombre de modelo seleccionado. El contexto experimental proviene de ese perfil, no del catalogo de especialistas. Los perfiles de agentes pueden seguir anunciando 73728: no enviar historiales mayores al contexto experimental configurado; probar primero en una conversacion nueva. No es una implementacion uniforme de MTP/DFlash a traves de la API Ollama.

No reinician ni matan tu Ollama. Para evitar cargar dos objetivos sobre la GPU, bloquean un arranque experimental cuando `/api/ps` de Ollama lista modelos o hay otro perfil experimental en sus puertos. Esa comprobacion no es un monitor completo de todos los procesos/GPU ni garantiza memoria suficiente.

Antes del experimento:

1. Termina tareas del agente y cierra su interfaz.
2. Mira los modelos activos:

```bash
OLLAMA_HOST=127.0.0.1:11434 ~/ollama-vulkan-exp/bin/ollama ps
```

3. Descarga el modelo cuando ya no este trabajando:

```bash
OLLAMA_HOST=127.0.0.1:11434 ~/ollama-vulkan-exp/bin/ollama stop qwen35-4b-uncensored:latest
```

4. Configura perfil y abre un agente en conversacion de prueba nueva.

El lanzamiento experimental falla si el runner no arranca; **no sustituye silenciosamente por original**. Que `/v1/models` responda confirma servidor disponible, NO aceptacion de borradores ni aceleracion. Revisa `~/ollama-vulkan-exp/logs/profile-MODO.log`.

## Detener experimento y volver

Los servidores experimentales quedan en segundo plano al salir del agente. `agentes-config show` no los detiene. Revisa el PID/argumentos/log registrados en `~/.config/adreno-agents/MODO-server.json`; confirma con `ps -p PID -o args=` y termina **ese PID** con `kill PID` cuando no haya trabajo. No uses `killall`.

Despues:

```bash
agentes-config select original
dsh
```

No cambies perfiles durante una respuesta ni esperes migracion del chat abierto: el cambio se aplica al **proximo lanzamiento**. Persistir/transferir una sesion entre motores requiere trabajo adicional. Los archivos del workspace no se borran.

Configuracion en `~/.config/adreno-agents/runtime.json`, respaldo `.json.bak`. No modifica el catalogo. OpenCL del borrador y todas las operaciones especulativas quedan pendientes de prueba; no se garantizan velocidad, exactitud ni estabilidad.

## Selector al abrir cada agente

Los comandos `dsh`, `hrm` y `oc` muestran ahora el menu de perfiles cuando se ejecutan en una terminal interactiva. Tambien lo muestran los lanzadores `*-local`. Elegir un perfil experimental no evita sus comprobaciones de archivos y memoria; si faltan requisitos, se detiene y no afirma que se activo.

Para reutilizar el perfil guardado sin preguntas: `dsh --no-menu`, `hrm --no-menu` u `oc --no-menu`. Coloca esa opcion inmediatamente despues del comando. En ejecucion no interactiva se usa el perfil guardado.

Tras actualizar archivos ejecuta `bash scripts/setup-shortcuts.sh` para copiar el conector actualizado a la instalacion.
