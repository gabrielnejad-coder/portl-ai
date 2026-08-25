/** Provider-agnostic types for the analyst loop. */

import type { ToolContext } from "../tools/index.ts";

/** One turn of the conversation as it arrives from the iOS client. */
export type ChatTurn = { role: "user" | "assistant"; content: string };

/** Events pushed to the client over SSE as the answer is produced. */
export type StreamEvent =
  | { type: "text"; delta: string }
  | { type: "tool_start"; name: string }
  | { type: "tool_end"; name: string; ok: boolean; ms: number }
  | { type: "warning"; message: string };

export type Usage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  toolCalls: number;
  iterations: number;
};

export type RunResult = {
  text: string;
  usage: Usage;
  stopReason: string;
  /** True when the loop hit its iteration ceiling before the model finished. */
  truncated: boolean;
};

export type RunOptions = {
  system: string;
  history: ChatTurn[];
  userMessage: string;
  ctx: ToolContext;
  onEvent: (event: StreamEvent) => void;
};

export interface AnalystProvider {
  readonly providerName: string;
  readonly model: string;
  run(opts: RunOptions): Promise<RunResult>;
}

/** Hard ceiling on tool-use round trips, so a confused model cannot loop forever. */
export const MAX_ITERATIONS = 8;

/** Generous for an analyst answer; far below any runaway-cost threshold. */
export const MAX_OUTPUT_TOKENS = 8192;

export const emptyUsage = (): Usage => ({
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  toolCalls: 0,
  iterations: 0,
});
