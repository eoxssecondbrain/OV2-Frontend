#!/usr/bin/env bash
#
# Local development stack: two MCP bridges + the backend API.
#
#   bash start-dev.sh      then, in another terminal:  npm run dev
#
# Differs from start-cruz.sh deliberately:
#   - no Cloudflare tunnel (nothing is exposed publicly)
#   - no built frontend; `npm run dev` serves :5173 with hot reload
#
# Production runs on Render and is unaffected by anything here. The local
# backend/data/webui.db is now a DIVERGED COPY -- treat it as scratch, and
# never copy it up to Render, which is the source of truth.

set -uo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
LOGS="$ROOT/.run"
mkdir -p "$LOGS"

# Parse .env without sourcing it -- values may contain characters the shell
# would interpret (see start-cruz.sh for the full explanation).
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in *=*) ;; *) continue ;; esac
  key=${line%%=*}
  val=${line#*=}
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  val=${val%$'\r'}
  val=$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                 -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")
  printf -v "$key" '%s' "$val"
  export "${key?}"
done < .env

for v in VAULT_MCP_URL THREADS_MCP_URL; do
  case "${!v:-}" in
    '')      echo "FATAL: $v is empty in .env" >&2; exit 1 ;;
    *'<'*|*'>'*) echo "FATAL: $v still holds a <...> placeholder" >&2; exit 1 ;;
  esac
done

PY="$ROOT/.venv/Scripts/python.exe"
PYW=$(cygpath -w "$PY")
BRIDGEW=$(cygpath -w "$ROOT/vault_bridge.py")
LOGSW=$(cygpath -w "$LOGS")
BACKENDW=$(cygpath -w "$ROOT/backend")

echo "==> stopping anything on 8080/9090/9091"
for port in 8080 9090 9091; do
  pid=$(netstat -ano 2>/dev/null | grep "LISTENING" | grep ":$port " | awk '{print $NF}' | head -1)
  [ -n "${pid:-}" ] && taskkill //PID "$pid" //F >/dev/null 2>&1
done

ps_run() { powershell -NoProfile -NonInteractive -Command "$1" >/dev/null; }

echo "==> MCP bridge  :9090  -> EOXS vault"
ps_run "\$env:VAULT_BRIDGE_PORT='9090'; Start-Process -FilePath '$PYW' -ArgumentList '$BRIDGEW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\bridge-vault.out' -RedirectStandardError '$LOGSW\\bridge-vault.log'"

echo "==> MCP bridge  :9091  -> Threads OV"
ps_run "\$env:VAULT_MCP_URL=\$env:THREADS_MCP_URL; \$env:VAULT_BRIDGE_PORT='9091'; Start-Process -FilePath '$PYW' -ArgumentList '$BRIDGEW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\bridge-threads.out' -RedirectStandardError '$LOGSW\\bridge-threads.log'"

echo "==> backend     :8080  (API only -- frontend comes from npm run dev)"
ps_run "Start-Process -FilePath '$PYW' -ArgumentList '-m','uvicorn','open_webui.main:app','--host','127.0.0.1','--port','8080','--reload' -WorkingDirectory '$BACKENDW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\backend.out' -RedirectStandardError '$LOGSW\\backend.log'"

curl -s --retry 60 --retry-all-errors --retry-delay 2 -m 5 http://127.0.0.1:8080/health >/dev/null \
  && echo "    backend healthy" \
  || echo "!!! backend did not come up -- see .run/backend.log" >&2

echo
echo "  Backend  http://127.0.0.1:8080   (--reload: restarts on Python changes)"
echo "  Next     npm run dev             -> http://localhost:5173"
echo "  Stop     bash stop-cruz.sh"
echo
