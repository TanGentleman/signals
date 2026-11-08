# signals: implementation

## Requirements

- macOS with Docker Desktop running
- `brew install cloudflared node` (Node 22 or later)
- Signal on your phone
- a domain on a Cloudflare account (free plan works)

Credentials: a Cloudflare login (`cloudflared tunnel login`, `wrangler`) and a Signal account linked by
QR code. The Mac is a linked Signal device of your phone.

## Usage

### Install

```bash
DOMAIN=yourdomain.com \
SIGNAL_ACCOUNT=+1XXXXXXXXXX \
SIGNAL_RECIPIENT=+1XXXXXXXXXX \
  curl -LsSf https://raw.githubusercontent.com/TanGentleman/signals/main/install.sh | bash
```

`SIGNAL_ACCOUNT` is the number Signal runs under on your phone and
`SIGNAL_RECIPIENT` the number that gets the messages (it can be the same).
Both use E.164 format. Leave the variables out to be prompted.

The installer clones to `~/.signals`, puts a `signals` launcher in
`~/.local/bin`, writes `.env` and `wrangler.toml`, then runs `signals setup`:

1. starts the `signal-bridge` container and opens a QR code to link Signal;
2. logs in to Cloudflare in the browser (once), creates the tunnel
   `signal-bridge.yourdomain.com` and its DNS record;
3. sets the Worker secrets, deploys `signal-agent.yourdomain.com` and sends a
   test message;
4. prints the token.

The README's `./signals init && ./signals setup` does the same steps from a checkout.

### API

`POST /notify` with header `X-Webhook-Token` and a JSON body
`{"message": "..."}`. Any other body without a string `message` sends
"Agent notification".

| Status | Meaning |
| --- | --- |
| 200 `{"ok":true}` | sent |
| 400 | body is not JSON |
| 401 | missing or wrong token |
| 404 | any other method or path |
| 413 | body over 64 KiB |
| 500 | the Worker has no `SIGNAL_WEBHOOK_TOKEN`; run `signals up <token>` |
| 502 | tunnel or Docker is down (`signals up`), or signal-cli-rest-api returned an error (shown in the body) |

### CLI

From a checkout, use `./signals`.

| Command | Effect |
| --- | --- |
| `signals init` | write `.env` and `wrangler.toml` |
| `signals setup` | Docker, QR link, tunnel, Worker deploy, test message |
| `signals setup --no-deploy` | Docker and tunnel only |
| `signals up [token]` | start Docker and the tunnel in the foreground; with a token (argument or `.env`), redeploy the Worker and send a test message first |
| `signals down` | stop the tunnel and the container |
| `signals uninstall` | delete the tunnel, Worker, container and `~/.cloudflared/config.yml` |

Each command exits 0 on success and non-zero on an error. `uninstall` keeps the
linked-device data in `~/.local/share/signal-cli`, the rest of
`~/.cloudflared`, the checkout, the launcher, and the `signal-bridge` DNS
record (cloudflared cannot delete it; remove it in the Cloudflare dashboard).

`.env` (written by `init`):

| Variable | Meaning |
| --- | --- |
| `DOMAIN` | Cloudflare zone for the tunnel and Worker routes |
| `SIGNAL_ACCOUNT` | Signal number of the linked device, E.164 |
| `SIGNAL_RECIPIENT` | who gets the messages, E.164 |
| `SIGNAL_WEBHOOK_TOKEN` | optional; keeps the same token across `setup` runs (otherwise a random 64-hex token) |

If messages stop arriving: `docker start signal-bridge`, or re-link at
`http://localhost:8080/v1/qrcodelink?device_name=mac`.

### Local Worker

Against a signal-cli-rest-api on `localhost:8080`:

```bash
cp .dev.vars.example .dev.vars    # fill in the numbers and a token
cp wrangler.toml.example wrangler.toml
npx wrangler dev                  # http://localhost:8787/notify
```

## How it works

- `src/index.ts`: the Cloudflare Worker. It checks `X-Webhook-Token` against the `SIGNAL_WEBHOOK_TOKEN`
  secret in constant time (never logging it) and forwards the message through the named Cloudflare tunnel
  `signal-bridge.yourdomain.com` to signal-cli-rest-api.
- `signals`: the CLI above. It runs the `signal-bridge` container, the tunnel and `wrangler`. It prints
  the token once, at the end of `setup`.
- `install.sh`: the installer described above.

## Tests

CI (`.github/workflows/ci.yml`) runs these on Node 22.23.4 and 26.13.0 on `ubuntu-24.04`:

```bash
npm ci
npm run type-check
npm test                    # Worker tests in workerd with a fake signal-cli-rest-api
shellcheck signals install.sh test/cli.sh test/fakes/fake
npm run test:cli            # install.sh and ./signals with fake docker/cloudflared/curl
cp wrangler.toml.example wrangler.toml
npx wrangler deploy --dry-run --outdir /tmp/signals-dist
```

CI writes the dry-run output to `$RUNNER_TEMP/dist`. All of these run offline except `npm ci`. The pty
test in `test:cli` needs util-linux `script` and skips without it.

## Limits

- Network: the tunnel hostname `signal-bridge.yourdomain.com` is public. Anyone who finds it can POST to
  signal-cli-rest-api directly and skip the token, so keep the subdomain hard to guess or put a Cloudflare
  Access service-token policy on it.
- Not verified live: Cloudflare login, tunnel creation, Worker deploy and a real Signal send. The tests
  replace Cloudflare, Docker and Signal with fakes. macOS was not run; the CLI tests ran on Linux.
