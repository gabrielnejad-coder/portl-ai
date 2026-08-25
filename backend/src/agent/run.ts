/**
 * Orchestration: validate the request, trim history to a budget, pick a
 * provider, run the loop.
 */

import { env } from "../env.ts";
import { log } from "../util/log.ts";
import { AnthropicProvider } from "../llm/anthropic.ts";
import { OpenAIProvider } from "../llm/openai.ts";
import { SYSTEM_PROMPT } from "./systemPrompt.ts";
import { sanitizeCoinId, sanitizeSymbol } from "../data/sanitize.ts";
import type { Holding } from "../tools/index.ts";
import type { AnalystProvider, ChatTurn, RunResult, StreamEvent } from "../llm/types.ts";

/**
 * Rough characters-per-token for English prose. Used only to bound history —
 * an exact count would need a tokenizer round trip per request, and the
 * consequence of being 20% off here is a slightly shorter history, not an error.
 */
const CHARS_PER_TOKEN = 4;
const HISTORY_TOKEN_BUDGET = 12_000;
const MAX_MESSAGE_CHARS = 4_000;
const MAX_HISTORY_TURNS = 40;

let provider: AnalystProvider | null = null;

export function getProvider(): AnalystProvider {
  if (!provider) {
    provider = env.provider === "openai" ? new OpenAIProvider() : new AnthropicProvider();
    log.info("analyst provider ready", { provider: provider.providerName, model: provider.model });
  }
  return provider;
}

/**
 * Keep the most recent turns that fit the budget, walking backwards so the
 * newest context survives. Drops a leading assistant turn, since a history
 * cannot start with one.
 *
 * The iOS build re-sent the entire conversation plus a full market snapshot on
 * every message, so cost grew without bound and long chats eventually 400'd.
 */
export function trimHistory(turns: readonly ChatTurn[]): ChatTurn[] {
  const budgetChars = HISTORY_TOKEN_BUDGET * CHARS_PER_TOKEN;
  const kept: ChatTurn[] = [];
  let used = 0;

  for (let i = turns.length - 1; i >= 0 && kept.length < MAX_HISTORY_TURNS; i--) {
    const turn = turns[i]!;
    const content = turn.content.slice(0, MAX_MESSAGE_CHARS);
    if (content.trim().length === 0) continue;
    if (used + content.length > budgetChars) break;
    used += content.length;
    kept.push({ role: turn.role, content });
  }

  kept.reverse();
  while (kept.length > 0 && kept[0]!.role === "assistant") kept.shift();
  return kept;
}

export class ValidationError extends Error {}

export type ChatRequest = {
  message: string;
  history: ChatTurn[];
  holdings: Holding[];
};

/** Parse and validate the JSON body of a chat request. */
export function parseChatRequest(body: unknown): ChatRequest {
  if (!body || typeof body !== "object") throw new ValidationError("Body must be a JSON object.");
  const b = body as Record<string, unknown>;

  const message = typeof b["message"] === "string" ? b["message"].trim() : "";
  if (message.length === 0) throw new ValidationError("`message` is required.");
  if (message.length > MAX_MESSAGE_CHARS) {
    throw new ValidationError(`\`message\` must be at most ${MAX_MESSAGE_CHARS} characters.`);
  }

  const rawHistory = Array.isArray(b["history"]) ? b["history"] : [];
  if (rawHistory.length > 200) throw new ValidationError("`history` is too long.");

  const history: ChatTurn[] = [];
  for (const item of rawHistory) {
    if (!item || typeof item !== "object") continue;
    const t = item as Record<string, unknown>;
    const role = t["role"];
    const content = t["content"];
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") continue;
    history.push({ role, content });
  }

  const rawHoldings = Array.isArray(b["holdings"]) ? b["holdings"] : [];
  if (rawHoldings.length > 100) throw new ValidationError("`holdings` is too long.");

  const holdings: Holding[] = [];
  for (const item of rawHoldings) {
    if (!item || typeof item !== "object") continue;
    const h = item as Record<string, unknown>;
    const coinId = sanitizeCoinId(h["coinId"]);
    const symbol = sanitizeSymbol(h["symbol"]) ?? coinId?.toUpperCase() ?? null;
    const amount = Number(h["amount"]);
    if (!coinId || !symbol) continue;
    if (!Number.isFinite(amount) || amount <= 0) continue;
    holdings.push({ coinId, symbol, amount });
  }

  return { message, history, holdings };
}

export async function runAnalyst(
  req: ChatRequest,
  signal: AbortSignal,
  onEvent: (e: StreamEvent) => void,
): Promise<RunResult> {
  const history = trimHistory(req.history);

  return getProvider().run({
    system: SYSTEM_PROMPT,
    history,
    userMessage: req.message,
    ctx: { holdings: req.holdings, signal },
    onEvent,
  });
}
