interface Env {
  SIGNAL_CLI_URL: string;
  SIGNAL_ACCOUNT: string;
  SIGNAL_RECIPIENT: string;
  SIGNAL_WEBHOOK_TOKEN?: string;
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

    // Auth: require matching X-Webhook-Token if secret is set
    if (
      env.SIGNAL_WEBHOOK_TOKEN &&
      request.headers.get("X-Webhook-Token") !== env.SIGNAL_WEBHOOK_TOKEN
    ) {
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
