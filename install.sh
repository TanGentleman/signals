#!/bin/sh
set -eu

REPO_URL="${SIGNALS_REPO_URL:-https://github.com/yourusername/signals.git}"
INSTALL_DIR="${SIGNALS_INSTALL_DIR:-$HOME/.signals}"
BIN_DIR="${HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/signals"

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

if [ -d "$INSTALL_DIR/.git" ]; then
  log "Updating existing install at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  log "Cloning signals into $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

[ -f "$INSTALL_DIR/signals" ] || die "Install failed: $INSTALL_DIR/signals missing"
chmod +x "$INSTALL_DIR/signals"

mkdir -p "$BIN_DIR"
cat >"$BIN_PATH" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/signals" "\$@"
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
"$INSTALL_DIR/signals" init

if confirm "Run full setup now?"; then
  "$INSTALL_DIR/signals" setup
else
  log ""
  log "Next steps:"
  log "  $BIN_PATH setup"
fi
