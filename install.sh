#!/bin/sh
set -eu

INSTALL_DIR="${SIGNALS_INSTALL_DIR:-$HOME/.signals}"
BIN_DIR="${HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/signals"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
LOCAL_SIGNALS="${SCRIPT_DIR}/signals"
REPO_URL="${SIGNALS_REPO_URL:-https://github.com/TanGentleman/signals.git}"

log() {
  printf '%s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  cmd=""
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
  done
}

confirm() {
  answer=""
  printf '%s' "$1 [Y/n] "
  read -r answer
  case "$answer" in
    ""|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd git bash

if [ -x "$LOCAL_SIGNALS" ] && [ -f "${SCRIPT_DIR}/README.md" ]; then
  log "Using local checkout at $SCRIPT_DIR"
  TARGET_SIGNALS="$LOCAL_SIGNALS"
else
  [ -n "$REPO_URL" ] || die "No local checkout detected. Set SIGNALS_REPO_URL to your repo URL."

  if [ -d "$INSTALL_DIR/.git" ]; then
    log "Updating existing install at $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
  else
    log "Cloning signals into $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  TARGET_SIGNALS="$INSTALL_DIR/signals"
fi

[ -f "$TARGET_SIGNALS" ] || die "Install failed: $TARGET_SIGNALS missing"
chmod +x "$TARGET_SIGNALS"

mkdir -p "$BIN_DIR"
cat >"$BIN_PATH" <<EOF
#!/usr/bin/env bash
exec "$TARGET_SIGNALS" "\$@"
EOF
chmod +x "$BIN_PATH"

log ""
log "Installed command: $BIN_PATH"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
  log "Add this to your shell profile if needed:"
  log "  export PATH=\"$BIN_DIR:\$PATH\""
  ;;
esac

log ""
log "Let's configure your local files (.env and wrangler.toml)."
"$TARGET_SIGNALS" init

if [ -n "${DOMAIN:-}" ] || confirm "Run full setup now?"; then
  "$TARGET_SIGNALS" setup
else
  log ""
  log "Next steps:"
  log "  $BIN_PATH setup"
fi
