#!/bin/bash
# obsidian-headless-mcp entrypoint
#
# 1. Installs the pinned versions of Obsidian Headless and obsidian-remote-mcp into
#    /config/app (first start, or when OB_VERSION / MCP_REF change).
# 2. With arguments (e.g. `ob login`), runs that command and exits. Used for setup.
# 3. Without arguments, runs Obsidian Headless sync and the MCP server side by side.
#    If either stops, the container exits so Docker restarts both.
set -uo pipefail

APP_DIR=/config/app
OB_DIR="$APP_DIR/obsidian-headless"
MCP_DIR="$APP_DIR/obsidian-remote-mcp"

log() { echo "[obsidian-headless-mcp] $*"; }

install_headless() {
  if [ "$(cat "$OB_DIR/.installed" 2>/dev/null)" = "$OB_VERSION" ]; then
    return 0
  fi
  log "installing obsidian-headless@$OB_VERSION from npm (first start or version change)..."
  local tmp="$OB_DIR.tmp"
  rm -rf "$tmp" && mkdir -p "$tmp" || return 1
  npm install --prefix "$tmp" --no-audit --no-fund --cache /tmp/npm-cache \
    "obsidian-headless@$OB_VERSION" || return 1
  echo "$OB_VERSION" > "$tmp/.installed"
  rm -rf "$OB_DIR" && mv "$tmp" "$OB_DIR"
  log "obsidian-headless@$OB_VERSION installed"
}

install_mcp() {
  if [ "$(cat "$MCP_DIR/.installed" 2>/dev/null)" = "$MCP_REPO@$MCP_REF" ]; then
    return 0
  fi
  log "installing obsidian-remote-mcp ($MCP_REF) from $MCP_REPO (first start or version change)..."
  local tmp="$MCP_DIR.tmp"
  rm -rf "$tmp" && mkdir -p "$tmp" || return 1
  git -C "$tmp" init -q \
    && git -C "$tmp" remote add origin "$MCP_REPO" \
    && git -C "$tmp" fetch -q --depth 1 origin "$MCP_REF" \
    && git -C "$tmp" checkout -q --detach FETCH_HEAD \
    || return 1
  rm -rf "$tmp/.git"
  (cd "$tmp" && BUN_INSTALL_CACHE_DIR=/tmp/bun-cache \
    bun install --frozen-lockfile --production --omit=optional) || return 1
  echo "$MCP_REPO@$MCP_REF" > "$tmp/.installed"
  rm -rf "$MCP_DIR" && mv "$tmp" "$MCP_DIR"
  log "obsidian-remote-mcp installed"
}

mkdir -p "$HOME" "$APP_DIR" "$(dirname "$TOKEN_STORE_PATH")" "$LOG_DIR"

if ! install_headless; then
  log "ERROR: could not install obsidian-headless@$OB_VERSION. Check the version and internet access."
  exit 1
fi
if ! install_mcp; then
  log "ERROR: could not install obsidian-remote-mcp at $MCP_REF. Check MCP_REF and internet access."
  exit 1
fi

# Setup mode: run the given command (e.g. `ob login`) and exit
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

pids=()

if ob sync-status --path "$VAULT_PATH" >/dev/null 2>&1; then
  log "starting Obsidian Headless sync for $VAULT_PATH"
  ob sync --continuous --path "$VAULT_PATH" &
  pids+=($!)
else
  log "WARNING: Obsidian Sync is not set up for $VAULT_PATH yet."
  log "Run the one-time setup from the README (ob login, ob sync-setup), then restart."
  log "Starting the MCP server only."
fi

log "starting obsidian-remote-mcp on port $PORT"
(cd "$MCP_DIR" && exec bun run src/server.ts) &
pids+=($!)

stop() {
  log "stopping..."
  kill -TERM "${pids[@]}" 2>/dev/null
  wait "${pids[@]}" 2>/dev/null
  exit 0
}
trap stop TERM INT

wait -n "${pids[@]}"
status=$?
log "a process exited with status $status; stopping so Docker restarts the container"
kill -TERM "${pids[@]}" 2>/dev/null
wait "${pids[@]}" 2>/dev/null
exit 1
