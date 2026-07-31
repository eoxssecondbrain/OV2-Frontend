#!/usr/bin/env bash
# Stop the Cruz stack (backend, both MCP bridges, tunnel).
set -uo pipefail

for port in 8080 9090 9091; do
  pid=$(netstat -ano 2>/dev/null | grep "LISTENING" | grep ":$port " | awk '{print $NF}' | head -1)
  if [ -n "${pid:-}" ]; then taskkill //PID "$pid" //F >/dev/null 2>&1 && echo "stopped :$port (pid $pid)"; fi
done

taskkill //IM cloudflared.exe //F >/dev/null 2>&1 && echo "stopped tunnel" || true
echo "done"
