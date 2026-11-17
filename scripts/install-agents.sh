#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -d /data/data/com.termux ]] || { echo 'Ejecutar en Termux.' >&2; exit 1; }
CHOICE="${1:-}"
if [[ -z "$CHOICE" ]]; then
  printf '\nAgentes locales, sin API de pago:\n  1 Hermes\n  2 DeepSeek Harness\n  3 OpenCode\n  4 Todos\n  0 Ninguno\n'
  read -r -p 'Elige uno o varios separados por espacios (ej. 1 3): ' CHOICE
fi
SELECTED=''
for n in ${CHOICE//,/ }; do
  case "$n" in
    1|hermes) SELECTED+=" hermes" ;;
    2|dsh) SELECTED+=" dsh" ;;
    3|opencode) SELECTED+=" opencode" ;;
    4|all) SELECTED=' hermes dsh opencode'; break ;;
    0|none) exit 0 ;;
    *) echo "Seleccion invalida: $n" >&2; exit 1 ;;
  esac
done
[[ -n "$SELECTED" ]] || exit 0
pkg install -y proot-distro curl
CONTAINER=adreno-agents
if ! proot-distro login "$CONTAINER" -- /bin/sh -c "exit 0" >/dev/null 2>&1; then
  proot-distro install --override-alias "$CONTAINER" ubuntu
fi
CONFIG="$HOME/.config/adreno-agents"
mkdir -p "$CONFIG" "$HOME/AgentWorkspace" "$HOME/.local/bin"
cp "$ROOT/scripts/connect-local.sh" "$CONFIG/connect-local.sh"
# Instalar scripts dentro del contenedor sin rutas compartidas temporales predecibles.
proot-distro login "$CONTAINER" -- /bin/bash -c 'mkdir -p /opt/local-agents'
cat "$ROOT/scripts/agents-inner.sh" | proot-distro login "$CONTAINER" -- /bin/bash -c 'cat > /opt/local-agents/install.sh'
cat "$ROOT/scripts/agents-run.sh" | proot-distro login "$CONTAINER" -- /bin/bash -c 'cat > /opt/local-agents/run.sh'
# Cada agente se instala por separado: informar fallos y permitir los siguientes.
FAILED=0
for agent in $SELECTED; do
  if proot-distro login "$CONTAINER" -- /bin/bash /opt/local-agents/install.sh "$agent"; then
    printf '#!%s/bin/bash\nexec bash "$HOME/.config/adreno-agents/connect-local.sh" %s "$@"\n' "$PREFIX" "$agent" > "$HOME/.local/bin/$agent-local"
    chmod +x "$HOME/.local/bin/$agent-local"
    echo "Instalado: $HOME/.local/bin/$agent-local"
  else
    echo "Fallo instalando $agent; los demas pueden continuar." >&2
    FAILED=1
  fi
done
echo 'Lanza con ~/.local/bin/hermes-local, dsh-local u opencode-local segun seleccion.'
exit "$FAILED"
