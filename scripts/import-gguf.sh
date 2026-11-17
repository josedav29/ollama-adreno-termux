#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Uso: bash scripts/import-gguf.sh /ruta/modelo.gguf [nombre-ollama]' >&2
  exit 1
fi
GGUF="$(realpath -- "$1")"
NAME="${2:-qwen35-4b-uncensored}"
[[ -r "$GGUF" ]] || { echo "GGUF no legible: $GGUF" >&2; exit 1; }
[[ "$GGUF" != *'"'* && "$GGUF" != *$'\n'* ]] || { echo 'Ruta con caracteres no admitidos.' >&2; exit 1; }
[[ "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$ ]] || { echo 'Nombre de modelo no valido.' >&2; exit 1; }
CTX="${CTX_TARGET:-73728}"
[[ "$CTX" =~ ^[1-9][0-9]*$ ]] || { echo 'CTX_TARGET debe ser entero positivo.' >&2; exit 1; }
EXP="$HOME/ollama-vulkan-exp"
[[ -x "$EXP/bin/ollama" ]] || { echo 'Ejecuta primero bash install.sh.' >&2; exit 1; }
export OLLAMA_MODELS="${OLLAMA_MODELS:-$HOME/.ollama/models}"
# Puerto dedicado. No reutilizar ni detener un servidor ajeno.
export OLLAMA_HOST=127.0.0.1:11439
python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(('127.0.0.1',11439))
PY
mkdir -p "$EXP/logs"
MODFILE="$(mktemp "$EXP/Modelfile.XXXXXX")"
printf 'FROM "%s"\nPARAMETER num_ctx %s\n' "$GGUF" "$CTX" > "$MODFILE"
"$EXP/bin/ollama" serve > "$EXP/logs/import-gguf.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true; rm -f "$MODFILE"' EXIT
READY=0
for ((i=0; i<30; i++)); do
  kill -0 "$PID" 2>/dev/null || { cat "$EXP/logs/import-gguf.log"; exit 1; }
  if curl -fsS http://127.0.0.1:11439/api/version >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
[[ "$READY" == 1 ]] || { cat "$EXP/logs/import-gguf.log"; exit 1; }
"$EXP/bin/ollama" create "$NAME" -f "$MODFILE"
"$EXP/bin/ollama" list
printf '\nModelo registrado: %s\nAlmacen: %s\n' "$NAME" "$OLLAMA_MODELS"
