/** Structured JSON logging. One line per event so Railway/Datadog can parse it. */

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 } as const;
export type Level = keyof typeof LEVELS;

let threshold: number = LEVELS.info;

export function setLevel(level: string): void {
  const l = level.toLowerCase() as Level;
  if (l in LEVELS) threshold = LEVELS[l];
}

/** Keys whose values are redacted before they ever reach a log sink. */
const SECRET_KEYS = /^(authorization|api[_-]?key|token|access_token|secret|password)$/i;

function scrub(value: unknown, depth = 0): unknown {
  if (depth > 4) return "[deep]";
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => scrub(v, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    out[k] = SECRET_KEYS.test(k) ? "[redacted]" : scrub(v, depth + 1);
  }
  return out;
}

function emit(level: Level, msg: string, fields?: Record<string, unknown>): void {
  if (LEVELS[level] < threshold) return;
  const line = { ts: new Date().toISOString(), level, msg, ...(scrub(fields ?? {}) as object) };
  const sink = level === "error" || level === "warn" ? process.stderr : process.stdout;
  sink.write(`${JSON.stringify(line)}\n`);
}

export const log = {
  debug: (m: string, f?: Record<string, unknown>) => emit("debug", m, f),
  info: (m: string, f?: Record<string, unknown>) => emit("info", m, f),
  warn: (m: string, f?: Record<string, unknown>) => emit("warn", m, f),
  error: (m: string, f?: Record<string, unknown>) => emit("error", m, f),
};
