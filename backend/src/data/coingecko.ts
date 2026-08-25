/**
 * CoinGecko client.
 *
 * Differences from the iOS CryptoService this replaces:
 *  - HTTP status codes are inspected and surfaced (the app collapsed every
 *    failure into a generic "requestFailed", losing the 429 vs 500 distinction).
 *  - Retries honour the `Retry-After` header instead of a fixed 1.5s sleep.
 *  - Stale cache genuinely works as a fallback (see cache.ts).
 *  - Rate limits default to the real free-tier ceiling, not the historical 30/min.
 */

import { env } from "../env.ts";
import { log } from "../util/log.ts";
import { TtlCache, TTL } from "./cache.ts";
import { SlidingWindowLimiter } from "./rateLimiter.ts";
import { sanitizeText } from "./sanitize.ts";
import type { Candle } from "./indicators.ts";

const PRO_BASE = "https://pro-api.coingecko.com/api/v3";
const FREE_BASE = "https://api.coingecko.com/api/v3";

const usingPro = Boolean(env.coingeckoApiKey) && env.coingeckoPlan !== "demo";
const BASE = usingPro ? PRO_BASE : FREE_BASE;

// The public free tier throttles well below the historical 30/min. Being
// conservative here costs a little latency and avoids sustained 429s.
const limiter = new SlidingWindowLimiter({
  max: env.coingeckoApiKey ? 250 : 10,
  windowMs: 60_000,
});

const cache = new TtlCache({ maxEntries: 400 });

export class UpstreamError extends Error {
  readonly status: number | null;
  readonly retryable: boolean;

  constructor(message: string, status: number | null, retryable: boolean) {
    super(message);
    this.name = "UpstreamError";
    this.status = status;
    this.retryable = retryable;
  }
}

function authHeaders(): Record<string, string> {
  if (!env.coingeckoApiKey) return {};
  return usingPro
    ? { "x-cg-pro-api-key": env.coingeckoApiKey }
    : { "x-cg-demo-api-key": env.coingeckoApiKey };
}

/** GET with rate limiting, bounded retries, and Retry-After awareness. */
async function get<T>(path: string, params: Record<string, string>, signal?: AbortSignal): Promise<T> {
  const url = new URL(BASE + path);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);

  const maxAttempts = 3;
  let lastError: Error = new UpstreamError("no attempt made", null, false);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    signal?.throwIfAborted();
    await limiter.acquire(signal);

    const timeout = AbortSignal.timeout(12_000);
    const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;

    try {
      const res = await fetch(url, {
        headers: { accept: "application/json", ...authHeaders() },
        signal: combined,
      });

      if (res.ok) return (await res.json()) as T;

      // 429 and 5xx are worth another attempt; 4xx is not.
      const retryable = res.status === 429 || res.status >= 500;
      lastError = new UpstreamError(`CoinGecko ${res.status} for ${path}`, res.status, retryable);
      if (!retryable || attempt === maxAttempts) throw lastError;

      const retryAfter = Number.parseFloat(res.headers.get("retry-after") ?? "");
      const backoffMs = Number.isFinite(retryAfter)
        ? Math.min(retryAfter * 1000, 10_000)
        : Math.min(500 * 2 ** (attempt - 1), 5_000);

      log.warn("coingecko retry", { path, status: res.status, attempt, backoffMs });
      await new Promise((r) => setTimeout(r, backoffMs));
    } catch (err) {
      if (signal?.aborted) throw err;
      if (err instanceof UpstreamError && !err.retryable) throw err;
      lastError = err instanceof Error ? err : new Error(String(err));
      if (attempt === maxAttempts) break;
      await new Promise((r) => setTimeout(r, Math.min(500 * 2 ** (attempt - 1), 5_000)));
    }
  }

  throw lastError;
}

// ---------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------

export type Market = {
  id: string;
  symbol: string;
  name: string;
  price: number;
  change1hPct: number | null;
  change24hPct: number | null;
  change7dPct: number | null;
  marketCap: number | null;
  volume24h: number | null;
  rank: number | null;
  high24h: number | null;
  low24h: number | null;
  athChangePct: number | null;
};

type RawMarket = Record<string, unknown>;

const num = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) ? v : null;

function toMarket(raw: RawMarket): Market | null {
  const id = typeof raw["id"] === "string" ? raw["id"] : null;
  const price = num(raw["current_price"]);
  if (!id || price === null) return null;
  return {
    id,
    symbol: sanitizeText(raw["symbol"], 16).toUpperCase(),
    name: sanitizeText(raw["name"], 48),
    price,
    change1hPct: num(raw["price_change_percentage_1h_in_currency"]),
    change24hPct: num(raw["price_change_percentage_24h_in_currency"]) ?? num(raw["price_change_percentage_24h"]),
    change7dPct: num(raw["price_change_percentage_7d_in_currency"]),
    marketCap: num(raw["market_cap"]),
    volume24h: num(raw["total_volume"]),
    rank: num(raw["market_cap_rank"]),
    high24h: num(raw["high_24h"]),
    low24h: num(raw["low_24h"]),
    athChangePct: num(raw["ath_change_percentage"]),
  };
}

export type Freshness = { stale: boolean; ageMs: number };

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

export async function getMarkets(
  opts: { limit?: number; currency?: string; ids?: string[] } = {},
  signal?: AbortSignal,
): Promise<{ markets: Market[] } & Freshness> {
  const limit = Math.min(Math.max(opts.limit ?? 30, 1), 250);
  const currency = opts.currency ?? "usd";
  const ids = opts.ids?.length ? [...opts.ids].sort() : null;
  const key = `markets:${currency}:${ids ? ids.join(",") : `top${limit}`}`;

  const params: Record<string, string> = {
    vs_currency: currency,
    order: "market_cap_desc",
    per_page: String(limit),
    page: "1",
    sparkline: "false",
    price_change_percentage: "1h,24h,7d",
  };
  if (ids) params["ids"] = ids.join(",");

  const r = await cache.fetch(
    key,
    TTL.market,
    async () => {
      const raw = await get<RawMarket[]>("/coins/markets", params, signal);
      return raw.map(toMarket).filter((m): m is Market => m !== null);
    },
    { maxStaleMs: 60 * 60_000 },
  );

  return { markets: r.value, stale: r.stale, ageMs: r.ageMs };
}

export async function getMarketChart(
  coinId: string,
  days: string,
  currency = "usd",
  signal?: AbortSignal,
): Promise<{ candles: Candle[] } & Freshness> {
  const key = `chart:${coinId}:${days}:${currency}`;

  const r = await cache.fetch(
    key,
    TTL.chart,
    async () => {
      const raw = await get<{ prices?: Array<[number, number]> }>(
        `/coins/${encodeURIComponent(coinId)}/market_chart`,
        { vs_currency: currency, days },
        signal,
      );
      const prices = Array.isArray(raw.prices) ? raw.prices : [];
      return prices
        .filter((p) => Array.isArray(p) && p.length >= 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]))
        .map(([t, close]) => ({ t, close }));
    },
    { maxStaleMs: 60 * 60_000 },
  );

  return { candles: r.value, stale: r.stale, ageMs: r.ageMs };
}

export type SearchHit = { id: string; symbol: string; name: string; rank: number | null };

export async function searchCoins(query: string, signal?: AbortSignal): Promise<SearchHit[]> {
  const key = `search:${query.toLowerCase()}`;
  const r = await cache.fetch(
    key,
    TTL.search,
    async () => {
      const raw = await get<{ coins?: RawMarket[] }>("/search", { query }, signal);
      const coins = Array.isArray(raw.coins) ? raw.coins : [];
      return coins.slice(0, 15).map((c) => ({
        id: typeof c["id"] === "string" ? c["id"] : "",
        symbol: sanitizeText(c["symbol"], 16).toUpperCase(),
        name: sanitizeText(c["name"], 48),
        rank: num(c["market_cap_rank"]),
      }));
    },
    { maxStaleMs: 24 * 60 * 60_000 },
  );
  return r.value.filter((c) => c.id.length > 0);
}

/** Diagnostics for the /health endpoint. */
export function upstreamStats(): { cacheEntries: number; requestsInWindow: number; plan: string } {
  return {
    cacheEntries: cache.size,
    requestsInWindow: limiter.inWindow,
    plan: env.coingeckoApiKey ? (usingPro ? "pro" : "demo") : "free",
  };
}
