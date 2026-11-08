#!/usr/bin/env bash
# Offline tests for install.sh and ./signals. docker, cloudflared, curl, npx,
# npm and open are replaced by test/fakes/fake, so nothing leaves the machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNNEL_ID="123e4567-e89b-12d3-a456-426614174000"
failures=0
work_dirs=()
trap '[[ -n "${KEEP_TMP:-}" ]] || rm -rf "${work_dirs[@]}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*"
  failures=$((failures + 1))
}

expect_contains() {
  local file="$1" needle="$2"
  grep -qF -- "$needle" "$file" || fail "$file does not contain: $needle"
}

expect_not_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then fail "$file contains: $needle"; fi
}

# A fresh checkout copy, home dir and fake bin dir; sets WORK, CHECKOUT and HOME_DIR.
sandbox() {
  WORK="$(mktemp -d)"
  work_dirs+=("$WORK")
  CHECKOUT="$WORK/checkout"
  HOME_DIR="$WORK/home"
  mkdir -p "$CHECKOUT" "$HOME_DIR/.cloudflared" "$WORK/bin"
  cp "$ROOT"/{signals,install.sh,README.md,.env.example,wrangler.toml.example} "$CHECKOUT"/
  touch "$HOME_DIR/.cloudflared/cert.pem"
  local cmd
  for cmd in docker cloudflared curl npx npm open; do
    ln -s "$ROOT/test/fakes/fake" "$WORK/bin/$cmd"
  done
  : >"$WORK/calls.log"
}

# Runs a command with the fakes first on PATH; output goes to $WORK/out.
run() {
  env HOME="$HOME_DIR" PATH="$WORK/bin:$PATH" FAKE_LOG="$WORK/calls.log" \
    FAKE_TUNNEL_ID="$TUNNEL_ID" "$@" >"$WORK/out" 2>&1
}

config_env=(DOMAIN=example.com SIGNAL_ACCOUNT=+15550000001 SIGNAL_RECIPIENT=+15550000002)

test_help() {
  sandbox
  run "$CHECKOUT/signals" help || fail "help exited non-zero"
  expect_contains "$WORK/out" "./signals setup"
  if run "$CHECKOUT/signals" bogus; then fail "unknown command exited 0"; fi
}

test_init_from_env() {
  sandbox
  run env "${config_env[@]}" "$CHECKOUT/signals" init || fail "init exited non-zero"
  expect_contains "$CHECKOUT/.env" "DOMAIN=example.com"
  expect_contains "$CHECKOUT/.env" "SIGNAL_ACCOUNT=+15550000001"
  expect_contains "$CHECKOUT/.env" "SIGNAL_RECIPIENT=+15550000002"
  expect_contains "$CHECKOUT/wrangler.toml" \
    'routes = [{ pattern = "signal-agent.example.com/*", zone_name = "example.com" }]'
}

test_init_rejects_bad_values() {
  sandbox
  if run env DOMAIN=localhost SIGNAL_ACCOUNT=+15550000001 SIGNAL_RECIPIENT=+15550000002 \
    "$CHECKOUT/signals" init; then fail "init accepted DOMAIN=localhost"; fi
  expect_contains "$WORK/out" "DOMAIN is not a valid domain"
  if run env DOMAIN=example.com SIGNAL_ACCOUNT=5550000001 SIGNAL_RECIPIENT=+15550000002 \
    "$CHECKOUT/signals" init; then fail "init accepted a number without +"; fi
  expect_contains "$WORK/out" "SIGNAL_ACCOUNT is not a valid E.164 number"
  [[ ! -e "$CHECKOUT/.env" ]] || fail "init wrote .env for bad values"
}

test_setup_needs_env() {
  sandbox
  if run "$CHECKOUT/signals" setup; then fail "setup without .env exited 0"; fi
  expect_contains "$WORK/out" "No .env found"
}

# The README's non-interactive install, from a local checkout. The newline on
# stdin answers "Press Enter once linked".
test_install_and_setup() {
  sandbox
  printf '\n' | run env "${config_env[@]}" bash "$CHECKOUT/install.sh" \
    || { cat "$WORK/out"; fail "install.sh exited non-zero"; return; }
  local log="$WORK/calls.log" out="$WORK/out"

  expect_contains "$out" "Using local checkout at $CHECKOUT"
  expect_contains "$HOME_DIR/.local/bin/signals" "exec \"$CHECKOUT/signals\""
  [[ -x "$HOME_DIR/.local/bin/signals" ]] || fail "launcher is not executable"

  expect_contains "$log" "docker run -d --name signal-bridge --restart unless-stopped -p 8080:8080 -v $HOME_DIR/.local/share/signal-cli:/home/.local/share/signal-cli -e MODE=native bbernhard/signal-cli-rest-api"
  expect_contains "$log" "open http://localhost:8080/v1/qrcodelink?device_name=mac"
  expect_contains "$log" "cloudflared tunnel create signal-bridge"
  expect_contains "$log" "cloudflared tunnel route dns -f signal-bridge signal-bridge.example.com"

  local cf="$HOME_DIR/.cloudflared/config.yml"
  expect_contains "$cf" "tunnel: $TUNNEL_ID"
  expect_contains "$cf" "credentials-file: $HOME_DIR/.cloudflared/$TUNNEL_ID.json"
  expect_contains "$cf" "hostname: signal-bridge.example.com"
  expect_contains "$cf" "service: http://localhost:8080"

  local key
  for key in SIGNAL_CLI_URL SIGNAL_ACCOUNT SIGNAL_RECIPIENT SIGNAL_WEBHOOK_TOKEN; do
    expect_contains "$log" "npx wrangler secret put $key"
  done
  expect_contains "$log" "npm run deploy --silent"

  local token
  token="$(sed -n 's/^Token: *//p' "$out" | tail -1)"
  [[ "$token" =~ ^[0-9a-f]{64}$ ]] || fail "setup did not print a 64-hex token: '$token'"
  expect_contains "$log" "-X POST https://signal-agent.example.com/notify"
  expect_contains "$log" "X-Webhook-Token: $token"
  expect_contains "$out" "Setup complete."
}

test_setup_uses_token_from_env() {
  sandbox
  run env "${config_env[@]}" "$CHECKOUT/signals" init
  echo "SIGNAL_WEBHOOK_TOKEN=my-stable-token" >>"$CHECKOUT/.env"
  printf '\n' | run "$CHECKOUT/signals" setup || fail "setup exited non-zero"
  expect_contains "$WORK/calls.log" "X-Webhook-Token: my-stable-token"
  expect_contains "$WORK/out" "Token:  my-stable-token"
}

test_setup_reports_e2e_failure() {
  sandbox
  run env "${config_env[@]}" "$CHECKOUT/signals" init
  if printf '\n' | FAKE_HTTP_CODE=401 run "$CHECKOUT/signals" setup; then
    fail "setup exited 0 when the e2e test got 401"
  fi
  expect_contains "$WORK/out" 'E2E failed after 3 attempts (HTTP 401): {"ok":true}'
}

test_setup_no_deploy() {
  sandbox
  run env "${config_env[@]}" "$CHECKOUT/signals" init
  printf '\n' | run "$CHECKOUT/signals" setup --no-deploy || fail "setup --no-deploy exited non-zero"
  expect_contains "$WORK/out" "Setup complete (no deploy)."
  expect_not_contains "$WORK/calls.log" "wrangler"
  expect_not_contains "$WORK/calls.log" "npm run deploy"
}

test_down() {
  sandbox
  run env "${config_env[@]}" "$CHECKOUT/signals" init
  run "$CHECKOUT/signals" down || fail "down exited non-zero"
  expect_contains "$WORK/calls.log" "docker stop signal-bridge"
  expect_contains "$WORK/out" "Docker container stopped"
}

# The README quick start: curl ... | bash, cloning the repo, with answers typed
# at the terminal. bash reads the script from the pipe, so the prompts have to
# read /dev/tty. script(1) from util-linux provides the terminal.
test_curl_pipe_install() {
  if ! script --version 2>/dev/null | grep -q util-linux; then
    echo "skip test_curl_pipe_install (needs util-linux script)"
    return
  fi
  sandbox
  git -C "$CHECKOUT" init -q
  git -C "$CHECKOUT" add -A
  git -C "$CHECKOUT" -c user.name=test -c user.email=test@example.com commit -qm test
  # domain, account, recipient, "Run full setup now?", "Press Enter once linked"
  printf 'example.com\n+15550000001\n+15550000002\n\n\n' |
    run env SIGNALS_REPO_URL="$CHECKOUT" SIGNALS_INSTALL_DIR="$WORK/install" \
      timeout 60 script -qec "cd '$WORK' && cat '$CHECKOUT/install.sh' | bash" /dev/null \
    || fail "curl | bash install exited non-zero"
  expect_contains "$WORK/out" "Cloning signals into $WORK/install"
  expect_contains "$WORK/install/.env" "DOMAIN=example.com"
  expect_contains "$WORK/install/.env" "SIGNAL_RECIPIENT=+15550000002"
  expect_contains "$WORK/calls.log" "-X POST https://signal-agent.example.com/notify"
  expect_contains "$WORK/out" "Setup complete."
}

tests=(
  test_help
  test_init_from_env
  test_init_rejects_bad_values
  test_setup_needs_env
  test_install_and_setup
  test_setup_uses_token_from_env
  test_setup_reports_e2e_failure
  test_setup_no_deploy
  test_down
  test_curl_pipe_install
)
for t in "${@:-${tests[@]}}"; do
  before=$failures
  "$t"
  if [[ $failures -eq $before ]]; then echo "ok   $t"; else echo "FAIL $t"; fi
done

[[ $failures -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "all ${#tests[@]} CLI tests passed"
