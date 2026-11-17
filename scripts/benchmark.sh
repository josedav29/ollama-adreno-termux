#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export MODEL_TARGET="${1:-${MODEL_TARGET:-qwen35-4b-uncensored}}"
export CTX_TARGET="${CTX_TARGET:-73728}"
AUDIT="$HOME/ollama-vulkan-exp/bin/probar-adreno-real"
[[ -x "$AUDIT" ]] || { echo 'Ejecuta primero bash install.sh.' >&2; exit 1; }
# El auditor usa estos puertos. Evitar medir o detener servidores ajenos.
python3 - <<'PY'
import socket
for port in (11435,11436,11437):
    with socket.socket() as s:
        try: s.bind(('127.0.0.1',port))
        except OSError: raise SystemExit(f'Puerto {port} ocupado: detén primero ese servidor.')
PY
exec "$AUDIT"
