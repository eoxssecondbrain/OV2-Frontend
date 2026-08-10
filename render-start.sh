#!/usr/bin/env bash
#
# Container entrypoint: two MCP bridges + the Open WebUI backend.
#
# The bridges listen on 127.0.0.1:9090 / :9091 inside this container, which is
# exactly what the tool-server URLs in the database already point at -- so the
# stored configuration works unchanged in production.
#
# Each bridge is supervised: if one dies (an upstream Render vault going away,
# say) it is restarted rather than silently leaving the assistant with no tools.
# The backend runs in the foreground as PID 1's child, so if IT dies the
# container exits and Render restarts the service.

set -uo pipefail

fail() { echo "FATAL: $*" >&2; exit 1; }

[ -n "${VAULT_MCP_URL:-}" ]   || fail "VAULT_MCP_URL is not set"
[ -n "${THREADS_MCP_URL:-}" ] || fail "THREADS_MCP_URL is not set"
[ -n "${WEBUI_SECRET_KEY:-}" ] || fail "WEBUI_SECRET_KEY is not set"

# DB_MCP_URL is optional: the database-backed vault is registered in the
# database as server:mcp:eoxs-db on :9092. If the variable is absent the bridge
# is simply not started -- but any model attached to that server will then have
# tools that silently fail, so set it in the Render environment.
if [ -z "${DB_MCP_URL:-}" ]; then
  echo "WARN: DB_MCP_URL not set -- the eoxs-db tool server will be unreachable." >&2
fi

# USERS_MCP_URL is the general-scope vault: the same corpus with sensitive
# material removed, for ordinary users. Registered as server:mcp:eoxs-users on
# :9093. Optional for the same reason as DB_MCP_URL -- absent, the bridge is
# simply not started.
#
# It MUST point at the eoxs-wiki-db-general endpoint, not the -full one. The two
# are indistinguishable by tool list, tool count and version; only the row
# counts differ. Crossing them wires the unredacted corpus to ordinary users
# with no error and no visible symptom. See PROJECT_SOT.md 7m.
if [ -z "${USERS_MCP_URL:-}" ]; then
  echo "WARN: USERS_MCP_URL not set -- the eoxs-users tool server will be unreachable." >&2
fi

# INTERN_MCP_URL is the intern-scope vault, for MBA interns. Registered as
# server:mcp:eoxs-intern on :9094. Optional like the two above.
#
# It MUST point at the eoxs-wiki-db-intern endpoint. All the tiers on that host
# expose the same tool names and the same version string, so a crossed pair
# fails silently -- the tools work, they just serve the wrong scope. Verify with
# get_index through the bridge after any change. See PROJECT_SOT.md 7p.
if [ -z "${INTERN_MCP_URL:-}" ]; then
  echo "WARN: INTERN_MCP_URL not set -- the eoxs-intern tool server will be unreachable." >&2
fi

case "$VAULT_MCP_URL$THREADS_MCP_URL${DB_MCP_URL:-}${USERS_MCP_URL:-}${INTERN_MCP_URL:-}" in
  *'<'*|*'>'*) fail "an MCP URL still contains a <...> placeholder" ;;
esac

# The persistent disk mounts here. If it is empty this is a first boot and
# Open WebUI will create a fresh database -- see DEPLOY-RENDER.md for the
# one-time step that restores the existing configuration.
mkdir -p /app/backend/data
if [ -f /app/backend/data/webui.db ]; then
  echo "==> found existing webui.db on the persistent disk"
else
  echo "==> no webui.db on disk: starting with a FRESH database."
  echo "    Existing models / MCP servers / accounts will NOT be present until"
  echo "    the database is restored (see DEPLOY-RENDER.md)."
fi

supervise() {
  local label="$1" url="$2" port="$3"
  while true; do
    echo "==> starting bridge $label on :$port"
    VAULT_MCP_URL="$url" VAULT_BRIDGE_PORT="$port" python /app/vault_bridge.py
    echo "!!! bridge $label exited (rc=$?); restarting in 5s" >&2
    sleep 5
  done
}

supervise "eoxs-vault" "$VAULT_MCP_URL"   9090 &
supervise "threads-ov" "$THREADS_MCP_URL" 9091 &

PORTS="9090 9091"
if [ -n "${DB_MCP_URL:-}" ]; then
  supervise "eoxs-db" "$DB_MCP_URL" 9092 &
  PORTS="$PORTS 9092"
fi
if [ -n "${USERS_MCP_URL:-}" ]; then
  supervise "eoxs-users" "$USERS_MCP_URL" 9093 &
  PORTS="$PORTS 9093"
fi
if [ -n "${INTERN_MCP_URL:-}" ]; then
  supervise "eoxs-intern" "$INTERN_MCP_URL" 9094 &
  PORTS="$PORTS 9094"
fi

# Wait for the bridges before accepting traffic, so the first request after a
# deploy does not arrive to a half-ready service.
for port in $PORTS; do
  for _ in $(seq 1 30); do
    nc -z 127.0.0.1 "$port" && break
    sleep 1
  done
  nc -z 127.0.0.1 "$port" \
    && echo "    bridge on :$port is listening" \
    || echo "!!! bridge on :$port did not come up in 30s; continuing anyway" >&2
done

echo "==> starting backend on :${PORT:-8080}"
cd /app/backend
exec python -m uvicorn open_webui.main:app --host 0.0.0.0 --port "${PORT:-8080}"
