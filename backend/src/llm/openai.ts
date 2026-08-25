/**
 * OpenAI provider — same tool-use loop shape as the Anthropic one.
 *
 * Kept so you can switch back or A/B against the model the app originally used,
 * by setting LLM_PROVIDER=openai. Behaviour, tools, and the system prompt are
 * identical; only the wire format differs.
 */

import OpenAI from "openai";
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

const client = new OpenAI({
  apiKey: env.openaiApiKey,
  maxRetries: 2,
  timeout: 120_000,
});

const toolDefs: OpenAI.Chat.Completions.ChatCompletionTool[] = TOOLS.map((t) => ({
  type: "function",
  function: {
    name: t.name,
    description: t.description,
    parameters: t.schema as unknown as Record<string, unknown>,
  },
}));

/** Accumulates streamed tool-call fragments, which arrive split by index. */
type PartialCall = { id: string; name: string; args: string };

export class OpenAIProvider implements AnalystProvider {
  readonly providerName = "openai";
  readonly model = env.openaiModel;

  async run(opts: RunOptions): Promise<RunResult> {
    const { system, history, userMessage, ctx, onEvent } = opts;

    const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
      { role: "system", content: system },
      ...history.map((t) => ({ role: t.role, content: t.content }) as OpenAI.Chat.Completions.ChatCompletionMessageParam),
      { role: "user", content: userMessage },
    ];

    const usage = emptyUsage();
    let finalText = "";
    let stopReason = "stop";
    let truncated = true;

    for (let iteration = 0; iteration < MAX_ITERATIONS; iteration++) {
      usage.iterations = iteration + 1;
      ctx.signal.throwIfAborted();

      const stream = await client.chat.completions.create(
        {
          model: this.model,
          max_tokens: MAX_OUTPUT_TOKENS,
          messages,
          tools: toolDefs,
          stream: true,
          stream_options: { include_usage: true },
        },
        { signal: ctx.signal },
      );

      const calls = new Map<number, PartialCall>();
      let assistantText = "";

      for await (const chunk of stream) {
        if (chunk.usage) {
          usage.inputTokens += chunk.usage.prompt_tokens ?? 0;
          usage.outputTokens += chunk.usage.completion_tokens ?? 0;
          usage.cacheReadTokens += chunk.usage.prompt_tokens_details?.cached_tokens ?? 0;
        }

        const choice = chunk.choices[0];
        if (!choice) continue;
        if (choice.finish_reason) stopReason = choice.finish_reason;

        const delta = choice.delta;
        if (delta?.content) {
          assistantText += delta.content;
          finalText += delta.content;
          onEvent({ type: "text", delta: delta.content });
        }

        for (const tc of delta?.tool_calls ?? []) {
          const idx = tc.index;
          const existing = calls.get(idx) ?? { id: "", name: "", args: "" };
          calls.set(idx, {
            id: tc.id ?? existing.id,
            name: tc.function?.name ?? existing.name,
            args: existing.args + (tc.function?.arguments ?? ""),
          });
        }
      }

      if (stopReason === "length") {
        onEvent({ type: "warning", message: "Response was cut off at the length limit." });
        truncated = false;
        break;
      }

      if (calls.size === 0) {
        truncated = false;
        break;
      }

      const ordered = [...calls.entries()].sort((a, b) => a[0] - b[0]).map(([, v]) => v);

      messages.push({
        role: "assistant",
        content: assistantText || null,
        tool_calls: ordered.map((c) => ({
          id: c.id,
          type: "function",
          function: { name: c.name, arguments: c.args || "{}" },
        })),
      });

      const results = await Promise.all(
        ordered.map(async (c) => {
          const started = Date.now();
          onEvent({ type: "tool_start", name: c.name });
          usage.toolCalls += 1;

          let input: Record<string, unknown> = {};
          try {
            const parsed: unknown = JSON.parse(c.args || "{}");
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              input = parsed as Record<string, unknown>;
            }
          } catch {
            log.warn("unparseable tool arguments", { name: c.name });
            onEvent({ type: "tool_end", name: c.name, ok: false, ms: Date.now() - started });
            return {
              role: "tool" as const,
              tool_call_id: c.id,
              content: JSON.stringify({ ok: false, error: "Arguments were not valid JSON." }),
            };
          }

          const { content, isError } = await runTool(c.name, input, ctx);
          onEvent({ type: "tool_end", name: c.name, ok: !isError, ms: Date.now() - started });

          return { role: "tool" as const, tool_call_id: c.id, content };
        }),
      );

      messages.push(...results);
    }

    if (truncated) {
      log.warn("analyst hit iteration ceiling", { iterations: usage.iterations });
      onEvent({ type: "warning", message: "Stopped after the maximum number of data lookups." });
    }

    return { text: finalText, usage, stopReason, truncated };
  }
}
