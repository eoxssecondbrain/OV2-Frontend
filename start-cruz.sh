#!/usr/bin/env bash
# Start the full Cruz stack and publish it on a public HTTPS URL.
#
#   bash start-cruz.sh
#
# Runs everything on this machine and tunnels port 8080 out through Cloudflare.
# The laptop must stay awake and online for the link to work.
#
# Secrets come from .env (gitignored). Nothing here writes a secret to disk
# or to a log.

set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
LOGS="$ROOT/.run"
mkdir -p "$LOGS"

# Parse .env WITHOUT sourcing it. Values may contain characters the shell would
# interpret -- a leftover "<secret>" placeholder reads as input redirection and
# aborts the whole script with a confusing "No such file or directory".
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

for v in WEBUI_SECRET_KEY VAULT_MCP_URL THREADS_MCP_URL; do
  val="${!v:-}"
  if [ -z "$val" ]; then
    echo "FATAL: $v is empty in .env" >&2; exit 1
  fi
  case "$val" in
    *'<'*|*'>'*)
      echo "FATAL: $v still contains the <...> placeholder. Paste the real URL," >&2
      echo "       with no angle brackets." >&2
      exit 1 ;;
  esac
done

PY="$ROOT/.venv/Scripts/python.exe"
BRIDGE="$ROOT/vault_bridge.py"

echo "==> stopping anything already running"
for port in 8080 9090 9091; do
  pid=$(netstat -ano 2>/dev/null | grep "LISTENING" | grep ":$port " | awk '{print $NF}' | head -1 || true)
  [ -n "${pid:-}" ] && taskkill //PID "$pid" //F >/dev/null 2>&1 || true
done
# cloudflared makes only outbound connections, so it never appears in the port
# scan above. Without this, every re-run leaves the old tunnel alive and starts
# a second one -- two live URLs, and cruz-url.sh reporting the wrong one.
taskkill //IM cloudflared.exe //F >/dev/null 2>&1 || true
rm -f "$LOGS/tunnel.log" "$LOGS/tunnel.out"

PYW=$(cygpath -w "$PY")
BRIDGEW=$(cygpath -w "$BRIDGE")
LOGSW=$(cygpath -w "$LOGS")
BACKENDW=$(cygpath -w "$ROOT/backend")
CFW=$(cygpath -w "$HOME/bin/cloudflared.exe")

# Everything is launched detached via Start-Process, so closing this terminal
# does not kill the demo. Secrets travel in the environment, never on a command
# line (command lines are visible to other processes and land in logs).
ps_run() { powershell -NoProfile -NonInteractive -Command "$1" >/dev/null; }

echo "==> MCP bridge  :9090  -> EOXS vault (OV2)"
ps_run "\$env:VAULT_BRIDGE_PORT='9090'; Start-Process -FilePath '$PYW' -ArgumentList '$BRIDGEW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\bridge-vault.out' -RedirectStandardError '$LOGSW\\bridge-vault.log'"

echo "==> MCP bridge  :9091  -> Threads OV"
ps_run "\$env:VAULT_MCP_URL=\$env:THREADS_MCP_URL; \$env:VAULT_BRIDGE_PORT='9091'; Start-Process -FilePath '$PYW' -ArgumentList '$BRIDGEW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\bridge-threads.out' -RedirectStandardError '$LOGSW\\bridge-threads.log'"

echo "==> backend     :8080  (serves the built frontend from ./build)"
ps_run "Start-Process -FilePath '$PYW' -ArgumentList '-m','uvicorn','open_webui.main:app','--host','127.0.0.1','--port','8080' -WorkingDirectory '$BACKENDW' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\backend.out' -RedirectStandardError '$LOGSW\\backend.log'"

curl -s --retry 60 --retry-all-errors --retry-delay 2 -m 5 http://127.0.0.1:8080/health >/dev/null
echo "    backend healthy"

echo "==> cloudflare tunnel"
ps_run "Start-Process -FilePath '$CFW' -ArgumentList 'tunnel','--url','http://127.0.0.1:8080','--no-autoupdate' -WindowStyle Hidden -RedirectStandardOutput '$LOGSW\\tunnel.out' -RedirectStandardError '$LOGSW\\tunnel.log'"

for _ in $(seq 1 60); do
  URL=$(grep -ohE "https://[a-z0-9-]+\.trycloudflare\.com" "$LOGS/tunnel.log" "$LOGS/tunnel.out" 2>/dev/null | head -1 || true)
  [ -n "${URL:-}" ] && break
  curl -s -m 1 http://127.0.0.1:1 >/dev/null 2>&1 || true
done

echo
echo "  Cruz is live:  ${URL:-<tunnel URL not found - see .run/tunnel.log>}"
echo
echo "  NOTE: this URL is new on every restart. Update WEBUI_URL in .env to match."
echo "  Logs: .run/{backend,bridge-vault,bridge-threads,tunnel}.log"
echo "  Stop: bash stop-cruz.sh"
