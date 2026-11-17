#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
AGENT="${1:-}"
case "$AGENT" in hermes|dsh|opencode) shift ;; *) echo 'Uso: connect-local.sh hermes|dsh|opencode [argumentos]' >&2; exit 1 ;; esac
# Selector al abrir cualquier agente. --no-menu reutiliza el perfil guardado.
PROFILE_TOOL="$HOME/.config/adreno-agents/runtime-profile.py"
if [[ "${1:-}" == --no-menu ]]; then
  shift
elif [[ -t 0 && -f "$PROFILE_TOOL" ]]; then
  python3 "$PROFILE_TOOL" menu
fi
# MODEL_TARGET gana sobre el coordinador del catalogo. No aplica auto-routing.
if [[ -z "${MODEL_TARGET:-}" ]]; then
  MODEL_TARGET="$(python3 - <<'PYMODEL'
import json,os
from pathlib import Path
p=Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'adreno-agents/models.json'
if p.exists():
    c=json.loads(p.read_text()); ident=c.get('routes',{}).get('general')
    candidates=[m for m in c['models'] if m['id']==ident and ident in c.get('selected',[]) and 'general' in m.get('roles',[]) and 'embedding' not in m.get('roles',[])]
    if not candidates: raise SystemExit('Catalogo sin coordinador general valido; usa route general ID.')
    print(candidates[0]['model'])
else:
    print('qwen35-4b-uncensored:latest')
PYMODEL
)"
fi
MODEL="$MODEL_TARGET"
EXP="$HOME/ollama-vulkan-exp"
PROFILE_TOOL="$HOME/.config/adreno-agents/runtime-profile.py"
MODE=original
if [[ -f "$PROFILE_TOOL" ]]; then
  MODE="$(python3 -c 'import json,pathlib; p=pathlib.Path.home()/".config/adreno-agents/runtime.json"; print(json.loads(p.read_text())["mode"] if p.exists() else "original")')"
fi
BASE=http://127.0.0.1:11434
if [[ "$MODE" != original ]]; then
  LOCAL_BASE_URL="$(python3 "$PROFILE_TOOL" endpoint --model "$MODEL")"
  echo "Perfil solicitado: $MODE — $LOCAL_BASE_URL (verifica activacion en logs)" >&2
else
if ! curl -fsS "$BASE/api/version" >/dev/null 2>&1; then
  [[ -x "$EXP/bin/ollama-adreno-opencl-serve" ]] || { echo 'Falta servidor OpenCL: instala Ollama primero.' >&2; exit 1; }
  mkdir -p "$EXP/logs"
  OLLAMA_HOST=127.0.0.1:11434 nohup "$EXP/bin/ollama-adreno-opencl-serve" > "$EXP/logs/agents-ollama.log" 2>&1 &
  PID=$!
  for ((i=0;i<40;i++)); do
    curl -fsS "$BASE/api/version" >/dev/null 2>&1 && break
    kill -0 "$PID" 2>/dev/null || { tail -50 "$EXP/logs/agents-ollama.log"; exit 1; }
    sleep 1
  done
fi
export MODEL
python3 - <<'PY'
import json,os,urllib.request
with urllib.request.urlopen('http://127.0.0.1:11434/api/tags',timeout=10) as r:
    names=[m['name'] for m in json.load(r).get('models',[])]
m=os.environ['MODEL']
if m not in names and m+':latest' not in names:
    raise SystemExit(f'Modelo no registrado: {m}. Disponibles: {names}. Importa primero tu GGUF.')
PY
LOCAL_BASE_URL="$BASE/v1"
fi
# No sustituye configuraciones existentes: perfil local independiente para Hermes y DSH.
# PRoot comparte red con Termux. No publica puertos en otras interfaces.
exec proot-distro login adreno-agents \
  --bind "$HOME/AgentWorkspace:/workspace" --work-dir /workspace \
  --env LOCAL_MODEL="$MODEL" \
  --env LOCAL_BASE_URL="$LOCAL_BASE_URL" \
  --env OPENCODE_CONFIG_STYLE="${OPENCODE_CONFIG_STYLE:-}" \
  -- /bin/bash /opt/local-agents/run.sh "$AGENT" "$@"
