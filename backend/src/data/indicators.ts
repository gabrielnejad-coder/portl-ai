/**
 * Technical indicators computed from a close-price series.
 *
 * This is the substance behind questions like "which coins have momentum" —
 * the iOS app could only ever answer those from a single 24h percentage.
 * Every function is pure and returns `null` when the series is too short,
 * so a partial history degrades a field rather than the whole response.
 */

export type Candle = { t: number; close: number };

const isNum = (n: number | null | undefined): n is number => typeof n === "number" && Number.isFinite(n);

/** Simple moving average of the last `period` closes. */
export function sma(closes: readonly number[], period: number): number | null {
  if (period <= 0 || closes.length < period) return null;
  let sum = 0;
  for (let i = closes.length - period; i < closes.length; i++) sum += closes[i]!;
  return sum / period;
}

/** Exponential moving average series, seeded with the SMA of the first window. */
export function emaSeries(closes: readonly number[], period: number): number[] | null {
  if (period <= 0 || closes.length < period) return null;
  const k = 2 / (period + 1);
  let seed = 0;
  for (let i = 0; i < period; i++) seed += closes[i]!;
  let prev = seed / period;
  const out: number[] = [prev];
  for (let i = period; i < closes.length; i++) {
    prev = closes[i]! * k + prev * (1 - k);
    out.push(prev);
  }
  return out;
}

export function ema(closes: readonly number[], period: number): number | null {
  const s = emaSeries(closes, period);
  return s ? s[s.length - 1]! : null;
}

/**
 * Wilder-smoothed RSI. Returns 0-100, or null if the series is too short.
 * An all-gain series yields 100 (avgLoss is zero, so RS is unbounded).
 */
export function rsi(closes: readonly number[], period = 14): number | null {
  if (closes.length < period + 1) return null;

  let gain = 0;
  let loss = 0;
  for (let i = 1; i <= period; i++) {
    const d = closes[i]! - closes[i - 1]!;
    if (d >= 0) gain += d;
    else loss -= d;
  }
  let avgGain = gain / period;
  let avgLoss = loss / period;

  for (let i = period + 1; i < closes.length; i++) {
    const d = closes[i]! - closes[i - 1]!;
    const g = d > 0 ? d : 0;
    const l = d < 0 ? -d : 0;
    avgGain = (avgGain * (period - 1) + g) / period;
    avgLoss = (avgLoss * (period - 1) + l) / period;
  }

  if (avgLoss === 0) return avgGain === 0 ? 50 : 100;
  const rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

export type Macd = { macd: number; signal: number; histogram: number };

/** MACD(12,26,9) on the supplied series. */
export function macd(closes: readonly number[], fast = 12, slow = 26, signalPeriod = 9): Macd | null {
  const fastS = emaSeries(closes, fast);
  const slowS = emaSeries(closes, slow);
  if (!fastS || !slowS) return null;

  // emaSeries drops the first (period-1) points, so align the tails.
  const n = Math.min(fastS.length, slowS.length);
  const line: number[] = [];
  for (let i = 0; i < n; i++) {
    line.push(fastS[fastS.length - n + i]! - slowS[slowS.length - n + i]!);
  }

  const sig = emaSeries(line, signalPeriod);
  if (!sig) return null;

  const macdVal = line[line.length - 1]!;
  const signalVal = sig[sig.length - 1]!;
  return { macd: macdVal, signal: signalVal, histogram: macdVal - signalVal };
}

/** Percentage change between the first and last close. */
export function pctChange(closes: readonly number[]): number | null {
  if (closes.length < 2) return null;
  const first = closes[0]!;
  if (first === 0) return null;
  return ((closes[closes.length - 1]! - first) / first) * 100;
}

/**
 * Annualized realized volatility (%) from log returns.
 * `intervalMs` is the spacing between samples; annualization scales by the
 * number of such intervals in a 365-day year.
 */
export function realizedVolatility(closes: readonly number[], intervalMs: number): number | null {
  if (closes.length < 3 || intervalMs <= 0) return null;

  const rets: number[] = [];
  for (let i = 1; i < closes.length; i++) {
    const a = closes[i - 1]!;
    const b = closes[i]!;
    if (a > 0 && b > 0) rets.push(Math.log(b / a));
  }
  if (rets.length < 2) return null;

  const mean = rets.reduce((s, r) => s + r, 0) / rets.length;
  const variance = rets.reduce((s, r) => s + (r - mean) ** 2, 0) / (rets.length - 1);
  const perInterval = Math.sqrt(variance);
  const intervalsPerYear = (365 * 24 * 60 * 60 * 1000) / intervalMs;
  return perInterval * Math.sqrt(intervalsPerYear) * 100;
}

/** Median spacing between samples — robust to gaps in the upstream series. */
export function inferIntervalMs(candles: readonly Candle[]): number | null {
  if (candles.length < 3) return null;
  const gaps: number[] = [];
  for (let i = 1; i < candles.length; i++) {
    const g = candles[i]!.t - candles[i - 1]!.t;
    if (g > 0) gaps.push(g);
  }
  if (gaps.length === 0) return null;
  gaps.sort((a, b) => a - b);
  return gaps[Math.floor(gaps.length / 2)]!;
}

export type IndicatorSet = {
  samples: number;
  intervalMinutes: number | null;
  last: number;
  changePct: number | null;
  high: number;
  low: number;
  pctFromHigh: number | null;
  pctFromLow: number | null;
  sma20: number | null;
  sma50: number | null;
  priceVsSma20Pct: number | null;
  priceVsSma50Pct: number | null;
  rsi14: number | null;
  macd: Macd | null;
  annualizedVolatilityPct: number | null;
  trend: "uptrend" | "downtrend" | "sideways" | "unknown";
};

/**
 * Full indicator bundle for one coin's history.
 * `trend` is a coarse, explicitly-defined label so the model does not have to
 * invent one: price above both SMAs and a rising MACD histogram is an uptrend.
 */
export function computeIndicators(candles: readonly Candle[]): IndicatorSet | null {
  if (candles.length === 0) return null;

  const closes = candles.map((c) => c.close).filter((c) => Number.isFinite(c) && c > 0);
  if (closes.length === 0) return null;

  const last = closes[closes.length - 1]!;
  const high = Math.max(...closes);
  const low = Math.min(...closes);
  const intervalMs = inferIntervalMs(candles);

  const s20 = sma(closes, 20);
  const s50 = sma(closes, 50);
  const m = macd(closes);
  const r = rsi(closes, 14);

  // Trend is defined by moving-average structure, not by the MACD histogram.
  // The histogram measures acceleration: on a steady, textbook uptrend it sits
  // at zero, so using it as the confirmation would label a clean uptrend
  // "sideways". The MACD *line* (fast EMA above slow EMA) is directional, so
  // that is what corroborates the SMA ordering.
  let trend: IndicatorSet["trend"] = "unknown";
  if (isNum(s20) && isNum(s50)) {
    const macdAgrees = (want: "up" | "down"): boolean => {
      if (!m) return true; // insufficient history — do not veto on a missing signal
      return want === "up" ? m.macd >= 0 : m.macd <= 0;
    };
    if (last > s20 && s20 > s50 && macdAgrees("up")) trend = "uptrend";
    else if (last < s20 && s20 < s50 && macdAgrees("down")) trend = "downtrend";
    else trend = "sideways";
  }

  return {
    samples: closes.length,
    intervalMinutes: intervalMs ? Math.round(intervalMs / 60_000) : null,
    last,
    changePct: pctChange(closes),
    high,
    low,
    pctFromHigh: high > 0 ? ((last - high) / high) * 100 : null,
    pctFromLow: low > 0 ? ((last - low) / low) * 100 : null,
    sma20: s20,
    sma50: s50,
    priceVsSma20Pct: isNum(s20) && s20 > 0 ? ((last - s20) / s20) * 100 : null,
    priceVsSma50Pct: isNum(s50) && s50 > 0 ? ((last - s50) / s50) * 100 : null,
    rsi14: r,
    macd: m,
    annualizedVolatilityPct: intervalMs ? realizedVolatility(closes, intervalMs) : null,
    trend,
  };
}
