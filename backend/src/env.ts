/** Validated process configuration. Fails fast at boot rather than at request time. */

function str(name: string, fallback?: string): string {
  const v = process.env[name]?.trim();
  if (v) return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing required environment variable: ${name}`);
}

function bool(name: string, fallback: boolean): boolean {
  const v = process.env[name]?.trim().toLowerCase();
  if (!v) return fallback;
  return v === "true" || v === "1" || v === "yes";
}

function int(name: string, fallback: number): number {
  const v = process.env[name]?.trim();
  if (!v) return fallback;
  const n = Number.parseInt(v, 10);
  if (!Number.isFinite(n)) throw new Error(`${name} must be an integer, got "${v}"`);
  return n;
}

export type Provider = "anthropic" | "openai";

const provider = str("LLM_PROVIDER", "anthropic") as Provider;
if (provider !== "anthropic" && provider !== "openai") {
  throw new Error(`LLM_PROVIDER must be "anthropic" or "openai", got "${provider}"`);
}

const authDisabled = bool("AUTH_DISABLED", false);
if (authDisabled && process.env.NODE_ENV === "production") {
  throw new Error("AUTH_DISABLED=true is not permitted when NODE_ENV=production");
}

export const env = {
  provider,
  // Only the selected provider's key is required, so the other can stay unset.
  anthropicApiKey: provider === "anthropic" ? str("ANTHROPIC_API_KEY") : process.env.ANTHROPIC_API_KEY,
  anthropicModel: str("ANTHROPIC_MODEL", "claude-opus-5"),
  openaiApiKey: provider === "openai" ? str("OPENAI_API_KEY") : process.env.OPENAI_API_KEY,
  openaiModel: str("OPENAI_MODEL", "gpt-4o"),
  // Any OpenAI-compatible endpoint works here: Groq, DeepSeek, Together,
  // Fireworks, OpenRouter, xAI, Mistral, or a local Ollama/LM Studio server.
  // Leave unset to use OpenAI itself.
  openaiBaseURL: process.env.OPENAI_BASE_URL?.trim() || undefined,

  // Validated in index.ts when the HTTP server boots, not here: offline
  // tooling imports the agent without ever touching auth.
  privyAppId: process.env.PRIVY_APP_ID?.trim() ?? "",
  authDisabled,

  coingeckoApiKey: process.env.COINGECKO_API_KEY?.trim() || null,
  coingeckoPlan: str("COINGECKO_PLAN", "free"),

  port: int("PORT", 8080),
  logLevel: str("LOG_LEVEL", "info"),
  userRateLimitPerMin: int("USER_RATE_LIMIT_PER_MIN", 12),
} as const;
