/**
 * Anthropic provider — manual streaming tool-use loop.
 *
 * A manual loop rather than the SDK tool runner because we need to emit
 * per-tool lifecycle events to the SSE channel as they happen, cap the number
 * of round trips, and keep tool execution inside our own context object.
 *
 * Prompt caching: the system prompt and tool definitions are byte-stable across
 * requests and render before `messages`, so a single `cache_control` breakpoint
 * on the system block covers the whole static prefix.
 */

import Anthropic from "@anthropic-ai/sdk";
import { env } from "../env.ts";
import { log } from "../util/log.ts";
import { TOOLS, runTool } from "../tools/index.ts";
import {
  MAX_ITERATIONS,
  MAX_OUTPUT_TOKENS,
  emptyUsage,
  type AnalystProvider,
  type RunOptions,
  type RunResult,
} from "./types.ts";

// Lazy for the same reason as the OpenAI provider: importing a provider must
// never require the other provider's credentials.
let client: Anthropic | null = null;

function getClient(): Anthropic {
  if (!client) {
    if (!env.anthropicApiKey) {
      throw new Error("ANTHROPIC_API_KEY is required when LLM_PROVIDER=anthropic");
    }
    client = new Anthropic({ apiKey: env.anthropicApiKey, maxRetries: 2, timeout: 120_000 });
  }
  return client;
}

const toolDefs: Anthropic.Tool[] = TOOLS.map((t) => ({
  name: t.name,
  description: t.description,
  input_schema: t.schema as unknown as Anthropic.Tool.InputSchema,
}));

export class AnthropicProvider implements AnalystProvider {
  readonly providerName = "anthropic";
  readonly model = env.anthropicModel;

  async run(opts: RunOptions): Promise<RunResult> {
    const { system, history, userMessage, ctx, onEvent } = opts;

    const messages: Anthropic.MessageParam[] = [
      ...history.map((t) => ({ role: t.role, content: t.content }) as Anthropic.MessageParam),
      { role: "user", content: userMessage },
    ];

    const usage = emptyUsage();
    let finalText = "";
    let stopReason = "end_turn";
    let truncated = true;

    for (let iteration = 0; iteration < MAX_ITERATIONS; iteration++) {
      usage.iterations = iteration + 1;
      ctx.signal.throwIfAborted();

      const stream = getClient().messages.stream(
        {
          model: this.model,
          max_tokens: MAX_OUTPUT_TOKENS,
          // Adaptive thinking with medium effort: enough reasoning to plan tool
          // use, without the latency of a high-effort run in a chat UI.
          thinking: { type: "adaptive" },
          output_config: { effort: "medium" },
          system: [
            {
              type: "text",
              text: system,
              cache_control: { type: "ephemeral" },
            },
          ],
          tools: toolDefs,
          messages,
        },
        { signal: ctx.signal },
      );

      // Only text deltas reach the user. Thinking is not streamed (display
      // defaults to omitted on Opus 5), and tool input JSON is internal.
      stream.on("text", (delta) => {
        finalText += delta;
        onEvent({ type: "text", delta });
      });

      const message = await stream.finalMessage();

      usage.inputTokens += message.usage.input_tokens ?? 0;
      usage.outputTokens += message.usage.output_tokens ?? 0;
      usage.cacheReadTokens += message.usage.cache_read_input_tokens ?? 0;
      usage.cacheWriteTokens += message.usage.cache_creation_input_tokens ?? 0;
      stopReason = message.stop_reason ?? "end_turn";

      if (stopReason === "refusal") {
        log.warn("model refused", { category: message.stop_details?.category ?? null });
        onEvent({
          type: "warning",
          message: "The assistant declined to answer that request.",
        });
        truncated = false;
        break;
      }

      if (stopReason === "max_tokens") {
        onEvent({ type: "warning", message: "Response was cut off at the length limit." });
        truncated = false;
        break;
      }

      // A server-side tool paused the turn; replay the assistant turn to resume.
      if (stopReason === "pause_turn") {
        messages.push({ role: "assistant", content: message.content });
        continue;
      }

      const toolUses = message.content.filter(
        (b): b is Anthropic.ToolUseBlock => b.type === "tool_use",
      );

      if (toolUses.length === 0) {
        truncated = false;
        break;
      }

      messages.push({ role: "assistant", content: message.content });

      // Parallel tool_use blocks must all be answered in ONE user message —
      // splitting them trains the model out of parallel calls.
      const results = await Promise.all(
        toolUses.map(async (tu) => {
          const started = Date.now();
          onEvent({ type: "tool_start", name: tu.name });
          usage.toolCalls += 1;

          // Tool inputs are parsed JSON from the SDK; never string-match them.
          const input = (tu.input ?? {}) as Record<string, unknown>;
          const { content, isError } = await runTool(tu.name, input, ctx);

          onEvent({ type: "tool_end", name: tu.name, ok: !isError, ms: Date.now() - started });

          return {
            type: "tool_result" as const,
            tool_use_id: tu.id,
            content,
            ...(isError ? { is_error: true } : {}),
          };
        }),
      );

      messages.push({ role: "user", content: results });
    }

    if (truncated) {
      log.warn("analyst hit iteration ceiling", { iterations: usage.iterations });
      onEvent({
        type: "warning",
        message: "Stopped after the maximum number of data lookups.",
      });
    }

    return { text: finalText, usage, stopReason, truncated };
  }
}
