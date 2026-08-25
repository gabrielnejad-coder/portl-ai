/** Entry point: boot the server and shut down cleanly. */

import { env } from "./env.ts";
import { log, setLevel } from "./util/log.ts";
import { createApp } from "./http/server.ts";
import { getProvider } from "./agent/run.ts";

setLevel(env.logLevel);

// The server cannot verify tokens without this; offline tooling does not need it.
if (!env.authDisabled && !env.privyAppId) {
  throw new Error("PRIVY_APP_ID is required unless AUTH_DISABLED=true");
}

const server = createApp();

server.listen(env.port, () => {
  const provider = getProvider();
  log.info("portl-backend listening", {
    port: env.port,
    provider: provider.providerName,
    model: provider.model,
    authDisabled: env.authDisabled,
  });
  if (env.authDisabled) {
    log.warn("AUTH IS DISABLED — every request is treated as authenticated. Development only.");
  }
});

// Railway sends SIGTERM on redeploy; finish in-flight streams before exiting.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    log.info("shutting down", { signal });
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}

process.on("unhandledRejection", (reason) => {
  log.error("unhandled rejection", { reason: String(reason) });
});
