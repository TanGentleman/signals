interface Env {
  SIGNAL_CLI_URL: string;
  SIGNAL_ACCOUNT: string;
  SIGNAL_RECIPIENT: string;
  SIGNAL_WEBHOOK_TOKEN?: string;
}

// Compare SHA-256 digests so the comparison takes the same time whatever the
// token length or the position of the first differing byte.
async function tokensMatch(given: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(given)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST" || url.pathname !== "/notify") {
      return new Response(JSON.stringify({ error: "Not Found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!env.SIGNAL_WEBHOOK_TOKEN) {
      return new Response(
        JSON.stringify({ error: "SIGNAL_WEBHOOK_TOKEN is not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = request.headers.get("X-Webhook-Token");
    if (token === null || !(await tokensMatch(token, env.SIGNAL_WEBHOOK_TOKEN))) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    let body: Record<string, unknown>;
    try {
      body = await request.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const message =
      typeof body.message === "string" ? body.message : "Agent notification";

    // Forward to signal-cli-rest-api via named tunnel
    let signalResponse: Response;
    try {
      signalResponse = await fetch(`${env.SIGNAL_CLI_URL}/v2/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message,
          number: env.SIGNAL_ACCOUNT,
          recipients: [env.SIGNAL_RECIPIENT],
        }),
      });
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err);
      return new Response(
        JSON.stringify({ error: "Failed to reach signal-cli-rest-api", detail }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!signalResponse.ok) {
      const detail = await signalResponse.text().catch(() => "");
      return new Response(
        JSON.stringify({
          error: "signal-cli-rest-api returned an error",
          status: signalResponse.status,
          detail,
        }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  },
} satisfies ExportedHandler<Env>;
