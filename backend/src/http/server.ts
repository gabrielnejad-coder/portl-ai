/**
 * HTTP surface. Plain node:http — the only routes are a health check and one
 * SSE streaming endpoint, which a framework would not simplify.
 */

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { env } from "../env.ts";
import { log } from "../util/log.ts";
import { KeyedLimiter } from "../data/rateLimiter.ts";
import { upstreamStats } from "../data/coingecko.ts";
import { verifyRequest, AuthError } from "./auth.ts";
import { parseChatRequest, runAnalyst, getProvider, ValidationError } from "../agent/run.ts";
import type { StreamEvent } from "../llm/types.ts";

const MAX_BODY_BYTES = 256 * 1024;
const userLimiter = new KeyedLimiter(env.userRateLimitPerMin, 60_000);

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(new ValidationError("Request body too large."));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "no-store",
  });
  res.end(payload);
}

/** SSE writer. Named events keep the iOS parser simple. */
function sseWriter(res: ServerResponse) {
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache, no-transform",
    connection: "keep-alive",
    "x-accel-buffering": "no",
  });

  let open = true;
  const send = (event: string, data: unknown): void => {
    if (!open) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  // Comment frames keep intermediaries from closing an idle connection while
  // the model is thinking or a tool is running.
  const heartbeat = setInterval(() => {
    if (open) res.write(": keepalive\n\n");
  }, 15_000);

  const close = (): void => {
    if (!open) return;
    open = false;
    clearInterval(heartbeat);
    res.end();
  };

  return { send, close, isOpen: () => open };
}

async function handleChat(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const user = await verifyRequest(req.headers.authorization);

  if (!userLimiter.tryAcquire(user.userId)) {
    sendJson(res, 429, {
      error: "rate_limited",
      message: `Too many requests. Limit is ${env.userRateLimitPerMin} per minute.`,
    });
    return;
  }

  const raw = await readBody(req);
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ValidationError("Body is not valid JSON.");
  }

  const chatRequest = parseChatRequest(parsed);

  // Abort the model call and every in-flight upstream fetch if the phone
  // disconnects — otherwise a backgrounded app keeps burning tokens.
  const controller = new AbortController();
  res.on("close", () => controller.abort());

  const sse = sseWriter(res);
  const started = Date.now();

  try {
    const result = await runAnalyst(chatRequest, controller.signal, (e: StreamEvent) => {
      sse.send(e.type, e);
    });

    sse.send("done", {
      stopReason: result.stopReason,
      truncated: result.truncated,
      usage: result.usage,
      ms: Date.now() - started,
    });

    log.info("chat complete", {
      userId: user.userId,
      ms: Date.now() - started,
      toolCalls: result.usage.toolCalls,
      iterations: result.usage.iterations,
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      cacheReadTokens: result.usage.cacheReadTokens,
    });
  } catch (err) {
    if (controller.signal.aborted) {
      log.info("chat aborted by client", { userId: user.userId, ms: Date.now() - started });
    } else {
      log.error("chat failed", { userId: user.userId, err: String(err) });
      // The stream is already committed with a 200, so errors are delivered
      // as an SSE event rather than a status code.
      sse.send("error", { message: "The assistant hit an error. Please try again." });
    }
  } finally {
    sse.close();
  }
}

export function createApp() {
  return createServer((req, res) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);

    void (async () => {
      try {
        if (req.method === "GET" && url.pathname === "/health") {
          sendJson(res, 200, {
            ok: true,
            provider: getProvider().providerName,
            model: getProvider().model,
            upstream: upstreamStats(),
            uptimeSeconds: Math.round(process.uptime()),
          });
          return;
        }

        if (req.method === "POST" && url.pathname === "/v1/chat") {
          await handleChat(req, res);
          return;
        }

        sendJson(res, 404, { error: "not_found" });
      } catch (err) {
        if (res.headersSent) {
          res.end();
          return;
        }
        if (err instanceof AuthError) {
          sendJson(res, err.status, { error: "unauthorized", message: err.message });
          return;
        }
        if (err instanceof ValidationError) {
          sendJson(res, 400, { error: "bad_request", message: err.message });
          return;
        }
        log.error("unhandled request error", { err: String(err) });
        sendJson(res, 500, { error: "internal_error" });
      }
    })();
  });
}
