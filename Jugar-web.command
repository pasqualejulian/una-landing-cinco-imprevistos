#!/bin/zsh
set -e
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v node >/dev/null 2>&1; then
  echo "Instalá Node.js 22 o superior para servir los archivos localmente."
  read -r "?Presioná Enter para cerrar."
  exit 1
fi
export PORT=4173
if curl -fsS "http://127.0.0.1:$PORT/mission-config.json" 2>/dev/null | /usr/bin/grep -q 'Dale lugar a tu idea'; then
  open "http://127.0.0.1:$PORT/"
  exit 0
fi
node serve.mjs &
GAME_SERVER_PID=$!
trap 'kill "$GAME_SERVER_PID" 2>/dev/null || true' EXIT INT TERM
for attempt in {1..30}; do
  if curl -fsS "http://127.0.0.1:$PORT/mission-config.json" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$GAME_SERVER_PID" 2>/dev/null; then
    echo "No pude iniciar el servidor. Revisá si el puerto 4173 está ocupado."
    read -r "?Presioná Enter para cerrar."
    exit 1
  fi
  sleep 0.2
done
open "http://127.0.0.1:$PORT/"
wait "$GAME_SERVER_PID"
