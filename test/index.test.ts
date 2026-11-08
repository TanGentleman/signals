import { afterEach, beforeEach, describe, it, vi } from "vitest";
import worker from "../src/index";

const env = {
  SIGNAL_CLI_URL: "https://signal-bridge.example.com",
  SIGNAL_ACCOUNT: "+15550000001",
  SIGNAL_RECIPIENT: "+15550000002",
  SIGNAL_WEBHOOK_TOKEN: "test-token",
};

type Env = typeof env | Omit<typeof env, "SIGNAL_WEBHOOK_TOKEN">;

// Stands in for signal-cli-rest-api: records each request the worker sends
// and answers with `respond`.
let upstream: { url: string; init: RequestInit }[];
let respond: () => Response | Promise<Response>;

beforeEach(() => {
  upstream = [];
  respond = () => Response.json({ timestamp: "1" }, { status: 201 });
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    upstream.push({ url: String(input), init: init ?? {} });
    return respond();
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

async function call(
  init: RequestInit & { path?: string } = {},
  workerEnv: Env = env,
): Promise<Response> {
  const { path = "/notify", ...rest } = init;
  const request = new Request(`https://signal-agent.example.com${path}`, {
    method: "POST",
    ...rest,
  });
  return worker.fetch(request, workerEnv as typeof env);
}

function notify(body: string, token: string | null = env.SIGNAL_WEBHOOK_TOKEN) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token !== null) headers["X-Webhook-Token"] = token;
  return call({ headers, body });
}

it("runs in workerd", ({ expect }) => {
  expect(navigator.userAgent).toBe("Cloudflare-Workers");
});

describe("routing", () => {
  it("returns 404 for other paths and methods", async ({ expect }) => {
    for (const response of [
      await call({ path: "/", headers: { "X-Webhook-Token": "test-token" } }),
      await call({ path: "/send", headers: { "X-Webhook-Token": "test-token" } }),
      await call({ method: "GET", headers: { "X-Webhook-Token": "test-token" } }),
    ]) {
      expect(response.status).toBe(404);
      expect(await response.json()).toEqual({ error: "Not Found" });
    }
    expect(upstream).toHaveLength(0);
  });
});

describe("auth", () => {
  it("rejects a missing token", async ({ expect }) => {
    const response = await notify('{"message":"hi"}', null);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "Unauthorized" });
    expect(upstream).toHaveLength(0);
  });

  it("rejects a wrong token", async ({ expect }) => {
    const response = await notify('{"message":"hi"}', "test-tokenX");
    expect(response.status).toBe(401);
    expect(upstream).toHaveLength(0);
  });

  it("fails closed when SIGNAL_WEBHOOK_TOKEN is unset", async ({ expect }) => {
    const { SIGNAL_WEBHOOK_TOKEN: _, ...noToken } = env;
    const response = await call(
      { headers: { "Content-Type": "application/json" }, body: "{}" },
      noToken,
    );
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      error: "SIGNAL_WEBHOOK_TOKEN is not set",
    });
    expect(upstream).toHaveLength(0);
  });

  it("rejects a token that is a prefix of the real one", async ({ expect }) => {
    const response = await notify('{"message":"hi"}', "test-toke");
    expect(response.status).toBe(401);
    expect(upstream).toHaveLength(0);
  });

  it("does not echo the token in the response", async ({ expect }) => {
    const response = await notify('{"message":"hi"}', "wrong");
    expect(await response.text()).not.toContain("test-token");
  });
});

describe("relay", () => {
  it("forwards the message to /v2/send", async ({ expect }) => {
    const response = await notify('{"message":"Job finished"}');
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });

    expect(upstream).toHaveLength(1);
    const [sent] = upstream;
    expect(sent.url).toBe("https://signal-bridge.example.com/v2/send");
    expect(sent.init.method).toBe("POST");
    expect(new Headers(sent.init.headers).get("Content-Type")).toBe(
      "application/json",
    );
    expect(JSON.parse(String(sent.init.body))).toEqual({
      message: "Job finished",
      number: "+15550000001",
      recipients: ["+15550000002"],
    });
  });

  it("uses a default message when none is given", async ({ expect }) => {
    const response = await notify("{}");
    expect(response.status).toBe(200);
    expect(JSON.parse(String(upstream[0].init.body)).message).toBe(
      "Agent notification",
    );
  });

  it("accepts the README curl example, which has no JSON content type", async ({ expect }) => {
    const response = await call({
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-Webhook-Token": env.SIGNAL_WEBHOOK_TOKEN,
      },
      body: '{"message": "Backup finished"}',
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(JSON.parse(String(upstream[0].init.body)).message).toBe("Backup finished");
  });

  it("rejects invalid JSON", async ({ expect }) => {
    const response = await notify("not json");
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "Invalid JSON" });
    expect(upstream).toHaveLength(0);
  });

  it("accepts a body at the 64 KiB limit", async ({ expect }) => {
    const padding = "a".repeat(64 * 1024 - '{"message":""}'.length);
    const response = await notify(JSON.stringify({ message: padding }));
    expect(response.status).toBe(200);
    expect(upstream).toHaveLength(1);
  });

  it("rejects a body over 64 KiB", async ({ expect }) => {
    const padding = "a".repeat(64 * 1024);
    const response = await notify(JSON.stringify({ message: padding }));
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({ error: "Payload Too Large" });
    expect(upstream).toHaveLength(0);
  });

  it("rejects a streamed body over 64 KiB with no Content-Length", async ({ expect }) => {
    const chunk = new TextEncoder().encode("a".repeat(16 * 1024));
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        for (let i = 0; i < 5; i++) controller.enqueue(chunk);
        controller.close();
      },
    });
    const request = new Request("https://signal-agent.example.com/notify", {
      method: "POST",
      headers: { "X-Webhook-Token": "test-token" },
      body,
    });
    expect(request.headers.get("Content-Length")).toBeNull();
    const response = await worker.fetch(request, env);
    expect(response.status).toBe(413);
    expect(upstream).toHaveLength(0);
  });

  it("surfaces an upstream error as 502", async ({ expect }) => {
    respond = () =>
      Response.json({ error: "Couldn't process request" }, { status: 400 });
    const response = await notify('{"message":"hi"}');
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      error: "signal-cli-rest-api returned an error",
      status: 400,
      detail: '{"error":"Couldn\'t process request"}',
    });
  });

  it("returns 502 when the tunnel is unreachable", async ({ expect }) => {
    respond = () => {
      throw new Error("connection refused");
    };
    const response = await notify('{"message":"hi"}');
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      error: "Failed to reach signal-cli-rest-api",
      detail: "connection refused",
    });
  });
});
