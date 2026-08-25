/**
 * TTL cache with explicit stale retention and single-flight de-duplication.
 *
 * Two deliberate differences from a naive TTL map:
 *  1. Expired entries are RETAINED, not deleted, so `getStale()` can serve them
 *     when upstream fails. (The iOS CacheManager deletes on expiry, which makes
 *     its own stale-fallback path unreachable — that bug is not repeated here.)
 *  2. `fetch()` de-duplicates concurrent misses for the same key, so a burst of
 *     requests produces one upstream call rather than N.
 */

export type Entry<T> = { value: T; storedAt: number };

export class TtlCache {
  readonly #entries = new Map<string, Entry<unknown>>();
  readonly #inflight = new Map<string, Promise<unknown>>();
  readonly #maxEntries: number;
  readonly #now: () => number;

  constructor(opts: { maxEntries?: number; now?: () => number } = {}) {
    this.#maxEntries = opts.maxEntries ?? 500;
    this.#now = opts.now ?? Date.now;
  }

  /** Fresh value only, or undefined if absent/expired. */
  get<T>(key: string, ttlMs: number): T | undefined {
    const e = this.#entries.get(key);
    if (!e) return undefined;
    if (this.#now() - e.storedAt >= ttlMs) return undefined;
    return e.value as T;
  }

  /** Any retained value regardless of age, plus how old it is. */
  getStale<T>(key: string): { value: T; ageMs: number } | undefined {
    const e = this.#entries.get(key);
    if (!e) return undefined;
    return { value: e.value as T, ageMs: this.#now() - e.storedAt };
  }

  set<T>(key: string, value: T): void {
    // Re-insert so Map iteration order tracks recency for the LRU trim below.
    this.#entries.delete(key);
    this.#entries.set(key, { value, storedAt: this.#now() });
    while (this.#entries.size > this.#maxEntries) {
      const oldest = this.#entries.keys().next();
      if (oldest.done) break;
      this.#entries.delete(oldest.value);
    }
  }

  /**
   * Read-through with single-flight. On upstream failure, falls back to a stale
   * entry when one exists within `maxStaleMs`; otherwise the error propagates.
   */
  async fetch<T>(
    key: string,
    ttlMs: number,
    loader: () => Promise<T>,
    opts: { maxStaleMs?: number } = {},
  ): Promise<{ value: T; stale: boolean; ageMs: number }> {
    const fresh = this.get<T>(key, ttlMs);
    if (fresh !== undefined) return { value: fresh, stale: false, ageMs: 0 };

    const existing = this.#inflight.get(key);
    if (existing) return { value: (await existing) as T, stale: false, ageMs: 0 };

    const p = loader()
      .then((v) => {
        this.set(key, v);
        return v;
      })
      .finally(() => this.#inflight.delete(key));

    this.#inflight.set(key, p);

    try {
      return { value: (await p) as T, stale: false, ageMs: 0 };
    } catch (err) {
      const stale = this.getStale<T>(key);
      const maxStale = opts.maxStaleMs ?? 30 * 60_000;
      if (stale && stale.ageMs <= maxStale) {
        return { value: stale.value, stale: true, ageMs: stale.ageMs };
      }
      throw err;
    }
  }

  clear(): void {
    this.#entries.clear();
    this.#inflight.clear();
  }

  get size(): number {
    return this.#entries.size;
  }
}

export const TTL = {
  prices: 45_000,
  market: 120_000,
  chart: 180_000,
  search: 300_000,
  news: 120_000,
} as const;
