/**
 * Privy access-token verification.
 *
 * The iOS app already authenticates with Privy, so the backend accepts the
 * Privy access token as its bearer credential and verifies it against Privy's
 * published JWKS. This is what makes it safe to hold the provider key server
 * side: only a signed-in user of this app can spend it.
 */

import { createRemoteJWKSet, jwtVerify, errors as joseErrors } from "jose";
import { env } from "../env.ts";
import { log } from "../util/log.ts";

const JWKS_URL = new URL(`https://auth.privy.io/api/v1/apps/${env.privyAppId}/jwks.json`);

// jose caches keys and refreshes on unknown `kid`, with its own cooldown.
const jwks = env.privyAppId
  ? createRemoteJWKSet(JWKS_URL, { cacheMaxAge: 10 * 60_000, timeoutDuration: 5_000 })
  : null;

export class AuthError extends Error {
  readonly status: number;

  constructor(message: string, status = 401) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

export type AuthedUser = { userId: string };

export function bearerFrom(header: string | undefined): string | null {
  if (!header) return null;
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  return m?.[1]?.trim() ?? null;
}

export async function verifyRequest(authorization: string | undefined): Promise<AuthedUser> {
  if (env.authDisabled) {
    // Local development only; env.ts refuses this combination in production.
    return { userId: "dev-user" };
  }

  const token = bearerFrom(authorization);
  if (!token) throw new AuthError("Missing bearer token.");
  if (!jwks) throw new AuthError("Server auth is not configured.", 500);

  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: "privy.io",
      audience: env.privyAppId,
      algorithms: ["ES256"],
      clockTolerance: 30,
    });

    const userId = typeof payload.sub === "string" ? payload.sub : null;
    if (!userId) throw new AuthError("Token has no subject.");
    return { userId };
  } catch (err) {
    if (err instanceof AuthError) throw err;
    if (err instanceof joseErrors.JWTExpired) throw new AuthError("Token expired.");
    if (err instanceof joseErrors.JWTClaimValidationFailed) throw new AuthError("Token claims invalid.");
    if (err instanceof joseErrors.JWSSignatureVerificationFailed) throw new AuthError("Token signature invalid.");
    log.warn("token verification failed", { err: String(err) });
    throw new AuthError("Token verification failed.");
  }
}
