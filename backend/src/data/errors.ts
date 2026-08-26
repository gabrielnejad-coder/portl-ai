/**
 * Upstream error type, in its own module so that leaf modules (and tests)
 * can import it without dragging in env validation via coingecko.ts.
 */
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
