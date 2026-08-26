/**
 * Forward paper-trading harness for the analyst.
 *
 * An LLM cannot be backtested honestly — it has market history in its
 * training data, so any "what would you have done in March" test is
 * contaminated. This harness only runs forward:
 *
 *   1. SCORE  — predictions logged >=24h ago are graded against what the
 *               market actually did (chart data, not the model's opinion).
 *   2. PREDICT — the analyst is asked for a 24h directional call on
 *               BTC/ETH/SOL, logged with the live price at prediction time.
 *   3. REPORT — running scorecard: hit rate, avg forward return on "up"
 *               calls, and paper equity vs always-long-BTC on the same days.
 *
 * State lives in test/trader-log.jsonl. Run daily:
 *
 *   npm run trader
 *
 * One run costs a few cents (one analyst call). Scores need >=2 runs
 * spaced >=24h apart before they mean anything, and >=30 before they
 * mean much — directional calls on 3 coins produce noisy small samples.
 */

import { readFileSync, writeFileSync, existsSync, appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { runAnalyst } from "../src/agent/run.ts";
import { getMarkets, getMarketChart } from "../src/data/coingecko.ts";
import type { StreamEvent } from "../src/llm/types.ts";

const LOG = fileURLToPath(new URL("./trader-log.jsonl", import.meta.url));
const COINS = ["bitcoin", "ethereum", "solana"] as const;
const HORIZON_MS = 24 * 60 * 60_000;
const FLAT_BAND = 0.005; // |move| <= 0.5% counts as flat
const FEE_ROUND_TRIP = 0.002; // 0.1%/side paper fee on acted-upon calls

type Row = {
  predictedAt: number;
  coin: string;
  direction: "up" | "down" | "flat";
  confidence: number;
  reason: string;
  priceAtPrediction: number;
  // filled in by scoring:
  scoredAt?: number;
  priceAtMaturity?: number;
  forwardReturn?: number;
  correct?: boolean;
};

function loadRows(): Row[] {
  if (!existsSync(LOG)) return [];
  return readFileSync(LOG, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l) as Row);
}

function saveRows(rows: Row[]): void {
  writeFileSync(LOG, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
}

// ── 1. Score matured predictions ────────────────────────────────────────────

async function scoreMatured(rows: Row[]): Promise<number> {
  const now = Date.now();
  const due = rows.filter((r) => r.correct === undefined && now - r.predictedAt >= HORIZON_MS);
  if (due.length === 0) return 0;

  let scored = 0;
  for (const coin of new Set(due.map((r) => r.coin))) {
    // 7 days of hourly candles comfortably covers any recent maturity.
    const { candles } = await getMarketChart(coin, "7");
    for (const row of due.filter((r) => r.coin === coin)) {
      const target = row.predictedAt + HORIZON_MS;
      let best: { t: number; close: number } | null = null;
      for (const c of candles) {
        if (!best || Math.abs(c.t - target) < Math.abs(best.t - target)) best = c;
      }
      // Accept a candle within 2h of the target, else leave for a later run.
      if (!best || Math.abs(best.t - target) > 2 * 60 * 60_000) continue;

      const ret = best.close / row.priceAtPrediction - 1;
      row.priceAtMaturity = best.close;
      row.forwardReturn = ret;
      row.scoredAt = now;
      row.correct =
        row.direction === "flat"
          ? Math.abs(ret) <= FLAT_BAND
          : row.direction === "up"
            ? ret > FLAT_BAND
            : ret < -FLAT_BAND;
      scored++;
    }
  }
  return scored;
}

// ── 2. Collect a fresh prediction ───────────────────────────────────────────

const PROMPT = `For each of bitcoin, ethereum, and solana, predict the price direction over the NEXT 24 hours. Use your tools: check current data, recent chart history, and derivatives positioning (funding rate and open interest) before deciding.

Definitions: "up" means more than +0.5%, "down" means more than -0.5% down, "flat" means within that band.

Respond with ONLY this JSON, no markdown fences, no other text:
{"calls":[{"coin":"bitcoin","direction":"up","confidence":0.6,"reason":"one short line"},{"coin":"ethereum",...},{"coin":"solana",...}]}`;

async function predict(): Promise<Row[]> {
  const tools: string[] = [];
  const result = await runAnalyst(
    { message: PROMPT, history: [], holdings: [] },
    AbortSignal.timeout(180_000),
    (e: StreamEvent) => {
      if (e.type === "tool_start") tools.push(e.name);
    },
  );

  const match = result.text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error(`no JSON in analyst answer: ${result.text.slice(0, 200)}`);
  const parsed = JSON.parse(match[0]) as { calls: Array<Record<string, unknown>> };

  const markets = await getMarkets({ ids: [...COINS] });
  const priceOf = new Map<string, number>(markets.markets.map((m) => [m.id, m.price]));

  const now = Date.now();
  const rows: Row[] = [];
  for (const call of parsed.calls ?? []) {
    const coin = String(call.coin);
    const direction = String(call.direction) as Row["direction"];
    if (!COINS.includes(coin as (typeof COINS)[number])) continue;
    if (!["up", "down", "flat"].includes(direction)) continue;
    const price = priceOf.get(coin);
    if (!price) continue;
    rows.push({
      predictedAt: now,
      coin,
      direction,
      confidence: Math.max(0, Math.min(1, Number(call.confidence) || 0.5)),
      reason: String(call.reason ?? "").slice(0, 160),
      priceAtPrediction: price,
    });
  }
  if (rows.length === 0) throw new Error("analyst returned no usable calls");
  console.log(`  tools used: ${tools.join(", ") || "none"}`);
  return rows;
}

// ── 3. Scorecard ────────────────────────────────────────────────────────────

function report(rows: Row[]): void {
  const scored = rows.filter((r) => r.correct !== undefined);
  const pending = rows.length - scored.length;

  console.log(`\n=== TRADER SCORECARD ===`);
  console.log(`predictions logged: ${rows.length}  scored: ${scored.length}  pending: ${pending}`);
  if (scored.length === 0) {
    console.log(`no matured predictions yet — run again in 24h to get the first scores.`);
    return;
  }

  const hits = scored.filter((r) => r.correct).length;
  const directional = scored.filter((r) => r.direction !== "flat");
  const dirHits = directional.filter((r) => r.correct).length;
  console.log(`hit rate (all): ${hits}/${scored.length} = ${((100 * hits) / scored.length).toFixed(1)}%`);
  if (directional.length > 0) {
    console.log(
      `hit rate (up/down only): ${dirHits}/${directional.length} = ${((100 * dirHits) / directional.length).toFixed(1)}%`,
    );
  }

  // Paper book: $10k start, act on BOTH up (long) and down (short) calls.
  // Each acted call gets 1/3 of equity (3 coins max); flat = deliberately
  // out of that coin. Fees on every acted call. Rules are fixed here so
  // results can't be curve-fit after the fact.
  const START_EQUITY = 10_000;
  let bookEq = START_EQUITY;
  let btcEq = START_EQUITY;
  let peak = START_EQUITY;
  let maxDD = 0;
  const btcRets = new Map(
    scored.filter((r) => r.coin === "bitcoin").map((r) => [r.predictedAt, r.forwardReturn ?? 0]),
  );
  const byTime = new Map<number, Row[]>();
  for (const r of scored) {
    const bucket = byTime.get(r.predictedAt) ?? [];
    bucket.push(r);
    byTime.set(r.predictedAt, bucket);
  }
  for (const [ts, bucket] of [...byTime.entries()].sort((a, b) => a[0] - b[0])) {
    let windowRet = 0;
    for (const r of bucket) {
      if (r.direction === "flat") continue;
      const dir = r.direction === "up" ? 1 : -1;
      windowRet += (dir * (r.forwardReturn ?? 0) - FEE_ROUND_TRIP) / 3;
    }
    bookEq *= 1 + windowRet;
    peak = Math.max(peak, bookEq);
    maxDD = Math.max(maxDD, 1 - bookEq / peak);
    btcEq *= 1 + (btcRets.get(ts) ?? 0);
  }
  console.log(`\n=== PAPER BOOK ($${START_EQUITY.toLocaleString()} start, long+short, 1/3 sizing, 0.2% fees) ===`);
  console.log(`book equity:      $${bookEq.toFixed(2)}  (${((bookEq / START_EQUITY - 1) * 100).toFixed(2)}%)`);
  console.log(`always-long BTC:  $${btcEq.toFixed(2)}  (${((btcEq / START_EQUITY - 1) * 100).toFixed(2)}%)`);
  console.log(`max drawdown:     ${(maxDD * 100).toFixed(2)}%`);

  if (scored.length < 30) {
    console.log(`\nCAVEAT: n=${scored.length}. Under ~30 scored calls this is noise, not signal.`);
  }

  const byCoin = new Map<string, { n: number; hit: number }>();
  for (const r of scored) {
    const s = byCoin.get(r.coin) ?? { n: 0, hit: 0 };
    s.n++;
    if (r.correct) s.hit++;
    byCoin.set(r.coin, s);
  }
  for (const [coin, s] of byCoin) console.log(`  ${coin}: ${s.hit}/${s.n}`);
}

// ── Main ────────────────────────────────────────────────────────────────────

/** Loud when quiet: consecutive all-flat batches are a decision, not silence. */
function idleAlarm(rows: Row[]): void {
  const batches = [...new Set(rows.map((r) => r.predictedAt))].sort((a, b) => b - a);
  let idle = 0;
  for (const ts of batches) {
    if (rows.filter((r) => r.predictedAt === ts).every((r) => r.direction === "flat")) idle++;
    else break;
  }
  if (idle >= 3) {
    console.log(
      `\n*** IDLE ALARM: ${idle} consecutive all-flat batches. The book has taken no positions. ***\n` +
        `*** Read the logged reasons — either the market is genuinely dead or the bot is stuck. ***`,
    );
  }
}

async function main(): Promise<void> {
  const rows = loadRows();

  console.log(`Scoring matured predictions...`);
  const n = await scoreMatured(rows);
  console.log(`  scored ${n} prediction(s)`);
  if (n > 0) saveRows(rows);

  if (process.argv.includes("--report")) {
    report(rows);
    idleAlarm(rows);
    return;
  }

  console.log(`Asking the analyst for 24h calls...`);
  const fresh = await predict();
  for (const r of fresh) {
    console.log(
      `  ${r.coin}: ${r.direction.toUpperCase()} (conf ${r.confidence.toFixed(2)}) @ $${r.priceAtPrediction} — ${r.reason}`,
    );
    appendFileSync(LOG, JSON.stringify(r) + "\n");
  }

  // What the paper book does with today's calls, stated plainly.
  console.log(`\nBOOK ACTIONS (24h hold):`);
  for (const r of fresh) {
    if (r.direction === "flat") console.log(`  ${r.coin}: no position (flat call)`);
    else console.log(`  ${r.coin}: ${r.direction === "up" ? "LONG" : "SHORT"} 1/3 of equity @ $${r.priceAtPrediction}`);
  }

  report([...rows, ...fresh]);
  idleAlarm([...rows, ...fresh]);
}

await main();
