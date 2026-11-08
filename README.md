# signals

Get a Signal message on your phone from anything that can make an HTTP POST:
cron jobs, CI, AI agents, webhooks.

```bash
curl -X POST https://signal-agent.yourdomain.com/notify \
  -H 'X-Webhook-Token: YOUR_TOKEN' \
  -d '{"message": "Backup finished"}'
# {"ok":true}
```

```
POST /notify -> Cloudflare Worker (checks token) -> named tunnel
             -> signal-cli-rest-api in Docker on your Mac -> Signal
```

The Mac runs Signal as a linked device of your phone; nothing is hosted
except a small Worker on your own Cloudflare account.

## Install

Needs macOS with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
running, `brew install cloudflared node` (Node 22+), Signal on your phone, and a
domain on Cloudflare (a free account works; buy one under Registrar or point an
existing domain's nameservers at Cloudflare).

```bash
DOMAIN=yourdomain.com \
SIGNAL_ACCOUNT=+1XXXXXXXXXX \
SIGNAL_RECIPIENT=+1XXXXXXXXXX \
  curl -LsSf https://raw.githubusercontent.com/TanGentleman/signals/main/install.sh | bash
```

It clones to `~/.signals`, adds a `signals` launcher to `~/.local/bin`, writes
`.env` and `wrangler.toml`, then runs `signals setup`: starts the Docker
container, opens a QR code to link Signal, creates the tunnel
`signal-bridge.yourdomain.com`, deploys the Worker at
`signal-agent.yourdomain.com` and sends a test message. It prints the token at
the end. Leave out the variables to be prompted instead.

`SIGNAL_ACCOUNT` is the number Signal runs under on your phone;
`SIGNAL_RECIPIENT` is who gets the messages (can be the same number). Both in
E.164 format.

Without the installer:

```bash
git clone https://github.com/TanGentleman/signals.git && cd signals
./signals init && ./signals setup
```

## API

`POST /notify` with header `X-Webhook-Token` and a JSON body
`{"message": "..."}` (a missing message sends "Agent notification").

| Status | Meaning |
|---|---|
| 200 `{"ok":true}` | sent |
| 400 | body is not JSON |
| 401 | missing or wrong token |
| 404 | any other method or path |
| 413 | body over 64 KiB |
| 500 | the Worker has no `SIGNAL_WEBHOOK_TOKEN`: run `signals up <token>` |
| 502 | tunnel or Docker is down (`signals up`), or signal-cli-rest-api returned an error (shown in the body) |

## CLI

```bash
signals init                # write .env and wrangler.toml
signals setup               # docker, QR link, tunnel, worker, test message
signals setup --no-deploy   # docker and tunnel only
signals up [token]          # start tunnel and docker; redeploy the token if given or set in .env
signals down                # stop tunnel and docker
signals uninstall           # remove the tunnel, worker, container and ~/.cloudflared/config.yml
```

From a checkout, use `./signals`. Set `SIGNAL_WEBHOOK_TOKEN` in `.env` to keep
the same token across `setup` runs; otherwise `setup` makes a random one.
`uninstall` keeps the linked-device data in `~/.local/share/signal-cli`, the
rest of `~/.cloudflared`, the checkout and the launcher. It does not delete
the `signal-bridge` DNS record (cloudflared has no command for that); remove it
in the Cloudflare dashboard.

If messages stop arriving: `docker start signal-bridge`, or re-link at
`http://localhost:8080/v1/qrcodelink?device_name=mac`.

## Security

The Worker compares tokens in constant time and never logs them. The tunnel
hostname `signal-bridge.yourdomain.com` is public, and anyone who finds it can
POST to signal-cli-rest-api directly, skipping the token. Keep the subdomain
hard to guess, or put a Cloudflare Access service-token policy on it (free,
Zero Trust dashboard).

## Development

```bash
npm ci
npm run type-check
npm test                                 # worker tests in workerd, no account needed
npm run test:cli                         # install.sh and CLI against fake docker/cloudflared
cp .dev.vars.example .dev.vars           # fill in values
cp wrangler.toml.example wrangler.toml   # or ./signals init
npx wrangler dev                         # http://localhost:8787/notify
```

`src/index.ts` is the Worker, `signals` the CLI, `install.sh` the installer.
