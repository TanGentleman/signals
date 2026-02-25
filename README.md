# signals

Send Signal messages from the cloud via a simple HTTP endpoint.

```
POST /notify
     ↓
Cloudflare Worker (auth)
     ↓  named tunnel
signal-cli-rest-api (Docker, your Mac)
     ↓
Signal message delivered
```

Any service that can make an HTTP POST — AI agents, cron jobs, webhooks — can send you a Signal message.

## Quick start

```bash
curl -LsSf https://raw.githubusercontent.com/TanGentleman/signals/main/install.sh | bash
```

The installer:
- installs to `~/.signals`
- creates a `signals` launcher in `~/.local/bin`
- runs `signals init` so you can paste your domain + phone numbers
- optionally runs `signals setup`

Manual fallback:

```bash
git clone https://github.com/TanGentleman/signals.git && cd signals
./signals init
./signals setup
```

## Prerequisites

- macOS
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) — install and open it before running setup
- `cloudflared` — `brew install cloudflared`
- Node.js / npm — `brew install node`
- Signal installed on your phone
- A Cloudflare account with a domain — see below

### Getting a Cloudflare domain

You need a domain whose DNS is managed by Cloudflare (free account is fine).

**Option A — buy a domain through Cloudflare** (easiest): go to [dash.cloudflare.com](https://dash.cloudflare.com) → Registrar → Register a domain. It lands in your account ready to use.

**Option B — use a domain you already own**: in the Cloudflare dashboard, add the domain as a new site, then update its nameservers at your registrar to the ones Cloudflare gives you. Takes ~5 minutes to propagate.

Either way, once your domain is active in Cloudflare, you're ready to run `signals init`.

## CLI

```bash
signals init                # generate local .env + wrangler.toml
signals setup               # first-time: docker, tunnel, worker, e2e test
signals setup --no-deploy   # first-time: docker + tunnel only (no worker deploy)
signals up                  # start tunnel + docker (redeploys token if SIGNAL_WEBHOOK_TOKEN is set in .env)
signals up <token>          # start + redeploy worker with provided token
signals down                # stop tunnel
signals uninstall           # remove tunnel, worker, docker container

# or, from inside the repo:
./signals setup             # first-time: docker, tunnel, worker, e2e test
./signals setup --no-deploy # first-time: docker + tunnel only (no worker deploy)
./signals up                # start tunnel + docker (redeploys token if SIGNAL_WEBHOOK_TOKEN is set in .env)
./signals up <token>        # start + redeploy worker with provided token
./signals down              # stop tunnel
./signals uninstall         # remove tunnel, worker, docker container
```

Token behavior:
- `setup` deploys worker auth unless you pass `--no-deploy`.
- `setup` uses a secure random token unless you set `SIGNAL_WEBHOOK_TOKEN` in `.env`.
- `up <token>` redeploys worker auth with the provided token and verifies registration.
- `up` also redeploys token auth when `SIGNAL_WEBHOOK_TOKEN` exists in `.env`.
- Custom tokens only need to be non-empty.

## Usage

Send a message:

```bash
curl -X POST https://signal-agent.yourdomain.com/notify \
  -H 'Content-Type: application/json' \
  -H 'X-Webhook-Token: YOUR_TOKEN' \
  -d '{"message": "Hello from the cloud"}'
```

From Python:

```python
import httpx

httpx.post(
    "https://signal-agent.yourdomain.com/notify",
    headers={"X-Webhook-Token": "YOUR_TOKEN"},
    json={"message": "Job finished"},
)
```

From JavaScript/TypeScript:

```ts
await fetch("https://signal-agent.yourdomain.com/notify", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-Webhook-Token": "YOUR_TOKEN",
  },
  body: JSON.stringify({ message: "Job finished" }),
});
```

## Files

| File | Purpose |
|---|---|
| `install.sh` | Installer for `curl ... | bash` flow |
| `signals` | CLI — setup, up, down, uninstall |
| `src/index.ts` | Cloudflare Worker — auth + relay to signal-cli-rest-api |
| `wrangler.toml.example` | Worker config template (copy to local `wrangler.toml`) |
| `.env.example` | Config template — domain, phone numbers |

## Troubleshooting

| Symptom | Check |
|---|---|
| Worker returns 502 | Is tunnel running? `./signals up` |
| 401 Unauthorized | Token mismatch — check `X-Webhook-Token` header |
| Message not received | Wrong phone number format — must be E.164 (`+1...`) |
| Docker container stopped | `docker start signal-bridge` |
| Device unlinked | Re-link at `http://localhost:8080/v1/qrcodelink?device_name=mac` |

## Uninstall scope

`signals uninstall` removes infrastructure managed by this project:
- Cloudflare tunnel `signal-bridge` and its DNS route
- Cloudflare Worker `signal-agent`
- Docker container `signal-bridge`
- `~/.cloudflared/config.yml`

It intentionally keeps local state:
- Signal linked-device data in `~/.local/share/signal-cli`
- Other Cloudflare files in `~/.cloudflared` (for example `cert.pem` and tunnel credentials)
- Your repo checkout and launcher script

Optional full cleanup (destructive):

```bash
./signals uninstall
rm -f ~/.local/bin/signals
rm -rf ~/.signals
# Optional: remove all Signal + Cloudflare local state too
rm -rf ~/.local/share/signal-cli
rm -rf ~/.cloudflared
```

## Security note

`signal-bridge.yourdomain.com` is publicly resolvable — anyone who finds it can POST to signal-cli directly, bypassing Worker auth. A non-guessable subdomain is sufficient for personal use. For stronger protection, add a Cloudflare Access service-token policy on that hostname (free tier, Zero Trust dashboard).

## Local dev

```bash
cp .dev.vars.example .dev.vars   # fill in values
npx wrangler dev                 # → http://localhost:8787/notify
```
