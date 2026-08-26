/**
 * Derivatives positioning data from OKX public endpoints (no key required).
 *
 * Everything else the analyst sees — price, charts, RSI/SMA/MACD — is a
 * transformation of the same price series. Funding and open interest are a
 * genuinely independent channel: funding shows which side of the perp market
 * is crowded and paying to hold, open interest shows whether money is
 * entering or leaving. This is the data layer for the get_derivatives_data
 * tool; interpretation is left to the model, but sign conventions are
 * spelled out in the payload because they are easy to misremember.
 */

import { TtlCache } from "./cache.ts";
import { UpstreamError } from "./errors.ts";

const BASE = "https://www.okx.com/api/v5/public";

/** CoinGecko id → OKX perpetual swap instrument. Major liquid coins only. */
const INSTRUMENTS: Record<string, string> = {
  bitcoin: "BTC-USDT-SWAP",
  ethereum: "ETH-USDT-SWAP",
  solana: "SOL-USDT-SWAP",
  ripple: "XRP-USDT-SWAP",
  dogecoin: "DOGE-USDT-SWAP",
  cardano: "ADA-USDT-SWAP",
  "avalanche-2": "AVAX-USDT-SWAP",
  chainlink: "LINK-USDT-SWAP",
  litecoin: "LTC-USDT-SWAP",
  "the-open-network": "TON-USDT-SWAP",
};

export function instrumentFor(coinId: string): string | null {
  return INSTRUMENTS[coinId] ?? null;
}

const cache = new TtlCache();
const FUNDING_TTL = 5 * 60_000; // funding updates every 8h; 5min is plenty fresh
const OI_TTL = 5 * 60_000;

async function okx<T>(path: string, signal?: AbortSignal): Promise<T[]> {
  const res = await fetch(`${BASE}${path}`, { signal });
  if (!res.ok) throw new UpstreamError(`OKX ${res.status} for ${path}`, res.status, res.status >= 500);
  const body = (await res.json()) as { code?: string; data?: T[]; msg?: string };
  if (body.code !== "0" || !Array.isArray(body.data)) {
    throw new UpstreamError(`OKX error for ${path}: ${body.msg ?? body.code}`, 502, true);
  }
  return body.data;
}

export type FundingSummary = {
  /** Current 8h funding rate in percent (e.g. 0.01 = 0.01% per 8h). */
  currentPct8h: number;
  /** Simple annualization: rate * 3 * 365. */
  annualizedPct: number;
  /** Mean of the last ~7 days of settled rates, percent per 8h. */
  avg7dPct8h: number;
  /** Whether current is above or below the 7d average. */
  vsAverage: "above" | "below" | "near";
};

/** Pure summary over funding history — exported for unit tests. */
export function summarizeFunding(currentRate: number, history: number[]): FundingSummary {
  const currentPct8h = currentRate * 100;
  const avg = history.length > 0 ? history.reduce((s, r) => s + r, 0) / history.length : currentRate;
  const avg7dPct8h = avg * 100;
  const diff = currentPct8h - avg7dPct8h;
  return {
    currentPct8h: round6(currentPct8h),
    annualizedPct: round6(currentPct8h * 3 * 365),
    avg7dPct8h: round6(avg7dPct8h),
    vsAverage: Math.abs(diff) < 0.002 ? "near" : diff > 0 ? "above" : "below",
  };
}

function round6(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}

export type DerivativesData = {
  instrument: string;
  funding: FundingSummary;
  openInterestUsd: number;
  asOf: string;
};

export async function getDerivatives(coinId: string, signal?: AbortSignal): Promise<DerivativesData> {
  const instId = instrumentFor(coinId);
  if (!instId) {
    throw new UpstreamError(`no derivatives instrument for ${coinId}`, 404, false);
  }

  const r = await cache.fetch(
    `deriv:${instId}`,
    FUNDING_TTL,
    async () => {
      const [current, history, oi] = await Promise.all([
        okx<{ fundingRate: string }>(`/funding-rate?instId=${instId}`, signal),
        okx<{ realizedRate?: string; fundingRate: string }>(
          `/funding-rate-history?instId=${instId}&limit=21`,
          signal,
        ),
        okx<{ oiUsd: string }>(`/open-interest?instId=${instId}`, signal),
      ]);

      const currentRate = Number(current[0]?.fundingRate ?? 0);
      const rates = history
        .map((h) => Number(h.realizedRate ?? h.fundingRate))
        .filter((n) => Number.isFinite(n));
      const openInterestUsd = Number(oi[0]?.oiUsd ?? 0);

      return {
        instrument: instId,
        funding: summarizeFunding(currentRate, rates),
        openInterestUsd: Math.round(openInterestUsd),
        asOf: new Date().toISOString(),
      };
    },
    { maxStaleMs: OI_TTL * 6 },
  );

  return r.value;
}
