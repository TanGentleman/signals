# signals

Send a Signal message to your phone with an HTTP POST. A Cloudflare Worker relays it through a tunnel to [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api) in Docker on your Mac.

```bash
git clone https://github.com/TanGentleman/signals.git && cd signals
./signals init && ./signals setup   # prompts for the domain and numbers, links Signal, deploys the Worker, prints the token
curl -X POST https://signal-agent.yourdomain.com/notify -H 'X-Webhook-Token: YOUR_TOKEN' -d '{"message": "Backup finished"}'
```

Needs macOS with Docker Desktop, `brew install cloudflared node` (Node 22+), Signal on your phone and a domain on a Cloudflare account (free plan works). Details: [IMPLEMENTATION.md](IMPLEMENTATION.md), [ROADMAP.md](ROADMAP.md).

[MIT](LICENSE)
