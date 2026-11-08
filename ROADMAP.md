# signals roadmap

signals lets anything that can make an HTTP POST (cron jobs, CI, AI agents)
send a Signal message to one fixed recipient. A Cloudflare Worker checks a
token and forwards to signal-cli-rest-api running in Docker on your Mac,
reached through a named Cloudflare tunnel. It is for one person who wants
phone notifications from their own scripts.

## Status on upstream main (500b826), checked 2026-11-08

| Check | Result | Evidence |
|---|---|---|
| `npm ci` | installs | Node 24 |
| `npm run type-check` | **fails**, 103 errors | DOM lib conflicts with `@cloudflare/workers-types` |
| `wrangler deploy --dry-run` | builds, 2.09 KiB | with `wrangler.toml.example` copied to `wrangler.toml` |
| `npm audit` | 6 issues (5 high) | wrangler 4.68.1 -> miniflare, undici, ws, sharp |
| `shellcheck signals install.sh` | 7 warnings | one is a real bug (empty e2e error body) |
| tests | none (added in -2) | |
| README quick start (`DOMAIN=... curl ... \| bash`) | **exits 1** at "Press Enter once linked" | with fake docker/cloudflared/curl: `read` gets EOF from the piped script, `set -e` exits silently |
| signal-cli-rest-api contract | matches | `POST /v2/send {number, recipients, message}`, `/v1/about`, `/v1/qrcodelink`, `MODE=native`, volume path all match upstream `src/api/api.go` and README |
| Links in README | live | docker.com, raw install.sh, clone URL (dash.cloudflare.com blocks curl, 403) |

Not verified (needs real accounts): Cloudflare login, tunnel creation,
`wrangler secret put` before first deploy, worker deploy, a real Signal send.

Worker security on main: token compare is `!==` (not constant time); auth is
skipped entirely when `SIGNAL_WEBHOOK_TOKEN` is unset; no request size limit;
the token is never logged by the worker (the CLI prints it on purpose).

## Signal vs noise

Keep: the 80-line worker, `/notify` contract, the CLI's `init`/`setup`/`up`/
`down`, the non-interactive install. That is the whole product.

Cut or shrink: duplicated CLI docs (done in -1), `signals up <token>`
redeploy-and-verify path and the PID-file plus pgrep double tunnel tracking
in the CLI (candidates for a later cut once the CLI has tests).

## Stack

- `signals-1` (done): import, type-check fix, current pinned deps (audit 0),
  shellcheck clean plus the e2e error-body fix, README CLI and local dev
  fixes, CI, this file.
- `signals-2` (done): 11 worker tests in workerd (vitest 5 +
  `@cloudflare/vitest-plugin`) with a fake signal-cli-rest-api; `npm test`
  in CI.
- `signals-3` (planned): worker hardening: constant-time token compare,
  fail closed without a token, request size limit.
- `signals-4` (planned): offline CLI and installer tests with fake
  docker/cloudflared/npx.
- `signals-5` (planned): installer reads prompts from `/dev/tty` so the
  README quick start works with `curl | bash`.
- `signals-6` (planned): README a stranger understands in 30 seconds.

## Applying a branch upstream

```bash
# in kranti-sandbox: everything after the import commit
base=$(git log -1 --format=%H --grep='^Import signals upstream' origin/signals-1)
git format-patch --relative=signals "$base"..origin/signals-1 -o /tmp/signals-1
# in a clean upstream clone at 500b826
git clone https://github.com/TanGentleman/signals && cd signals
git am /tmp/signals-1/*.patch
npm ci && npm run type-check && npm test && shellcheck signals install.sh
```

For a stacked branch, use the previous branch as the base:
`origin/signals-1..origin/signals-2`. No CRLF files, so `--keep-cr` is not
needed.

## Needs Tan

- `@cloudflare/workers-types` went 4 -> 5 (4.x stopped in July 2026).
  Type-check passes; nothing else in the repo uses it.
- Node 22 is now required (`engines`), because wrangler 4.158 needs it.
- Nothing here was run against Cloudflare or a real Signal account.
