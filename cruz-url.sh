#!/usr/bin/env bash
# Print the current public Cruz URL, and whether the stack is actually serving.
#
#   bash cruz-url.sh
#
# Safe to run any time. Reads the running tunnel's log -- it does not restart
# anything, so it will never change the URL out from under you.

cd "$(dirname "$0")"
LOGS="$(pwd)/.run"

URL=$(grep -ohE "https://[a-z0-9-]+\.trycloudflare\.com" \
        "$LOGS/tunnel.log" "$LOGS/tunnel.out" 2>/dev/null | tail -1)

up() { curl -s -m 5 -o /dev/null "$1" 2>/dev/null && echo "up" || echo "DOWN"; }

echo
if [ -z "${URL:-}" ]; then
  echo "  No tunnel URL found. The stack is probably not running."
  echo "  Start it with:  bash start-cruz.sh"
  echo
  exit 1
fi

echo "  $URL"
echo
printf "  backend :8080        %s\n" "$(up http://127.0.0.1:8080/health)"
printf "  bridge  :9090 vault  %s\n" "$(up http://127.0.0.1:9090/mcp)"
printf "  bridge  :9091 threads %s\n" "$(up http://127.0.0.1:9091/mcp)"
printf "  public tunnel        %s\n" "$(up "$URL/health")"
echo

# A stale URL in .env means share links and redirects point at a dead tunnel.
ENV_URL=$(grep -E '^WEBUI_URL=' .env 2>/dev/null | cut -d= -f2-)
if [ -n "$ENV_URL" ] && [ "$ENV_URL" != "$URL" ]; then
  echo "  WARNING: WEBUI_URL in .env does not match the live tunnel."
  echo "           .env says: $ENV_URL"
  echo "           Update it and restart the backend."
  echo
fi
