#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == --help ]]; then
  echo 'Uso: bash install.sh [--recompilar] [--solo-pruebas]'
  echo 'Compila sin descargar modelos. Luego usa scripts/import-gguf.sh y scripts/benchmark.sh.'
  exit 0
fi
# No actualizar silenciosamente todos los paquetes: puede modificar el Ollama original.
if command -v curl >/dev/null 2>&1 && ! curl --version >/dev/null 2>&1; then
  echo 'curl no arranca: repara Termux con apt update && apt full-upgrade.' >&2
  echo 'Revisa los cambios propuestos antes de aceptarlos. Luego repite la instalacion.' >&2
  exit 1
fi
exec bash "$ROOT/scripts/build-adreno.sh" --skip-audit "$@"
