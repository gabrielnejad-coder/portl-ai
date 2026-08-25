/** Sliding-window limiter. `acquire` queues; `tryAcquire` rejects immediately. */
export class SlidingWindowLimiter {
  readonly #max: number;
  readonly #windowMs: number;
  readonly #hits: number[] = [];
  readonly #now: () => number;
  readonly #sleep: (ms: number) => Promise<void>;

  constructor(opts: {
    max: number;
    windowMs: number;
    now?: () => number;
    sleep?: (ms: number) => Promise<void>;
  }) {
    this.#max = opts.max;
    this.#windowMs = opts.windowMs;
    this.#now = opts.now ?? Date.now;
    this.#sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  }

  #prune(): void {
    const cutoff = this.#now() - this.#windowMs;
    while (this.#hits.length > 0 && this.#hits[0]! <= cutoff) this.#hits.shift();
  }

  /** Non-blocking. Returns false when the window is full. */
  tryAcquire(): boolean {
    this.#prune();
    if (this.#hits.length >= this.#max) return false;
    this.#hits.push(this.#now());
    return true;
  }

  /** Blocks until a slot frees. Throws if `signal` aborts while waiting. */
  async acquire(signal?: AbortSignal): Promise<void> {
    for (;;) {
      signal?.throwIfAborted();
      this.#prune();
      if (this.#hits.length < this.#max) {
        this.#hits.push(this.#now());
        return;
      }
      const oldest = this.#hits[0]!;
      const waitMs = Math.max(10, oldest + this.#windowMs - this.#now() + 25);
      await this.#sleep(waitMs);
    }
  }

  get inWindow(): number {
    this.#prune();
    return this.#hits.length;
  }
}

/** Per-key limiter used to cap chat requests per authenticated user. */
export class KeyedLimiter {
  readonly #buckets = new Map<string, SlidingWindowLimiter>();
  readonly #max: number;
  readonly #windowMs: number;

  constructor(max: number, windowMs: number) {
    this.#max = max;
    this.#windowMs = windowMs;
  }

  tryAcquire(key: string): boolean {
    let b = this.#buckets.get(key);
    if (!b) {
      b = new SlidingWindowLimiter({ max: this.#max, windowMs: this.#windowMs });
      this.#buckets.set(key, b);
    }
    // Opportunistic GC so idle users don't accumulate forever.
    if (this.#buckets.size > 10_000) {
      for (const [k, v] of this.#buckets) {
        if (v.inWindow === 0) this.#buckets.delete(k);
        if (this.#buckets.size <= 5_000) break;
      }
    }
    return b.tryAcquire();
  }
}
