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
curl -LsSf https://my-url/install.sh | bash
```

The installer:
- installs to `~/.signals`
- creates a `signals` launcher in `~/.local/bin`
- runs `signals init` so you can paste your domain + phone numbers
- optionally runs `signals setup`

Manual fallback:

```bash
git clone https://github.com/yourusername/signals.git && cd signals
./signals init
./signals setup
```

## Prerequisites

- macOS
- Docker Desktop (running)
- `cloudflared` — `brew install cloudflared`
- Node.js / npm — `brew install node`
- A Cloudflare account with a domain (free tier is fine)
- Signal installed on your phone

## CLI

```bash
signals init                # generate local .env + wrangler.toml
signals setup               # first-time: docker, tunnel, worker, e2e test
signals up                  # start tunnel + docker
signals up <token>          # start + redeploy worker with new token
signals down                # stop tunnel
signals uninstall           # remove tunnel, worker, docker container

# or, from inside the repo:
./signals setup             # first-time: docker, tunnel, worker, e2e test
./signals up                # start tunnel + docker
./signals up <token>        # start + redeploy worker with new token
./signals down              # stop tunnel
./signals uninstall         # remove tunnel, worker, docker container
```

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

## Security note

`signal-bridge.yourdomain.com` is publicly resolvable — anyone who finds it can POST to signal-cli directly, bypassing Worker auth. A non-guessable subdomain is sufficient for personal use. For stronger protection, add a Cloudflare Access service-token policy on that hostname (free tier, Zero Trust dashboard).

## Local dev

```bash
cp .dev.vars.example .dev.vars   # fill in values
npx wrangler dev                 # → http://localhost:8787/notify
```
