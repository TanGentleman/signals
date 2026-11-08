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
in the CLI (candidates for a later cut, now that the CLI has tests in -4).

## Stack

- `signals-1` (done): import, type-check fix, current pinned deps (audit 0),
  shellcheck clean plus the e2e error-body fix, README CLI and local dev
  fixes, CI, this file.
- `signals-2` (done): 11 worker tests in workerd (vitest 5 +
  `@cloudflare/vitest-plugin`) with a fake signal-cli-rest-api; `npm test`
  in CI.
- `signals-3` (done): worker hardening: constant-time token compare,
  fail closed (500) without a token, 64 KiB request limit (413). 15 tests.
- `signals-4` (done): 9 offline tests of `install.sh` and `./signals`
  (`npm run test:cli`) with fake docker/cloudflared/curl/npx/npm; covers
  init validation, the full setup flow, e2e failure, `--no-deploy`, `down`.
- `signals-5` (done): installer prompts read `/dev/tty` when stdin is not
  a terminal, so the README `curl | bash` quick start no longer stops at the
  first prompt (it hung in `init`, or exited 1 at the QR prompt with
  `DOMAIN` set). Tested through a pty (`script`), 10 CLI tests.
- `signals-6` (done): README rewrite (178 -> 107 lines): example first,
  one install block, a status-code table, cuts the Python/TS examples and
  the long uninstall/cleanup section. Adds a test for the README curl
  example (no JSON content type), 16 worker tests.
  Review fixes on `-6`: a JSON body that is not an object (`null`) threw
  in the worker; it now gets the default message (17 worker tests). The
  README no longer says `uninstall` removes the DNS record (it never did).
- `signals-7` (done): TypeScript 7.0.2 (all other deps were already latest);
  CI pinned to `ubuntu-24.04` with Node 22.23.4 and 26.13.0. CLI tests for
  `up`, `up <token>` and `uninstall` (14 CLI tests). README in the
  tan-toolchains style: CLI and `.env` tables, a Boundaries section with what
  needs credentials and what was never run live, and the CI command set
  (shellcheck, wrangler dry run) under Development.

## Applying a branch upstream

```bash
git clone https://github.com/TanGentleman/kranti-sandbox && cd kranti-sandbox   # private: needs access
base=$(git log -1 --format=%H --grep='^Import signals upstream' origin/signals-1)
git format-patch --relative=signals "$base"..origin/signals-7 -o /tmp/signals-7
cd .. && git clone https://github.com/TanGentleman/signals && cd signals
git am /tmp/signals-7/*.patch
# then the README Development commands
```

For a stacked branch, use the previous branch as the base:
`origin/signals-6..origin/signals-7`, or take everything with
`"$base"..origin/signals-7`. No CRLF files, so `--keep-cr` is not needed.
Checked 2026-11-08: applying `-1` through `-7` to a fresh clone of 500b826
gives a tree identical to `origin/signals-7:signals`, and the README
Development commands pass there on Node 22.23.4 and 26.13.0.

## Needs Tan

- Contract changes to accept or revert: no token secret now returns 500
  instead of relaying (`-3`); bodies over 64 KiB get 413 (`-3`); under
  `curl | bash` the installer prompts read `/dev/tty` (`-5`).
- Node 22 is the floor (`engines`), because wrangler 4.158 needs it.
- `-6` dropped the Python/TypeScript examples and the uninstall cleanup
  commands from the README; restore any you want back.
- CI has not run on GitHub (it only runs once applied upstream), and nothing
  was run on macOS, against Cloudflare, or with a real Signal account.
