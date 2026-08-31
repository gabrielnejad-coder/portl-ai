# PortL AI

**An AI crypto analyst in your pocket** — a native iOS app backed by a tool-calling LLM service.

Ask questions about the market in plain English; the backend's analyst agent answers by calling live tools (price lookups, market data) rather than guessing from stale training data. Alongside the chat, the app tracks prices and runs a paper-trading book so you can test ideas without risking money.

## Features

- **AI analyst chat** — LLM backend with tool calling for live market data; API keys live server-side, never on the device
- **Price tracking** — watch coins with a dedicated `PriceTracker` module
- **Paper trading book** — dollar-based equity, long *and* short positions, drawdown tracking, and an idle alarm so a forgotten book doesn't silently drift
- **Email-code sign-in** — passwordless onboarding with visible error and progress states

## Architecture

```
Portl AI/          SwiftUI iOS app (chat, tracking, paper book, onboarding)
PriceTracker/      price-watch module
backend/           TypeScript analyst service — LLM + market tools, deployed on production
Portl AITests/     unit tests
Portl AIUITests/   UI tests
```

The app talks only to the backend; the backend owns all model calls and market-data credentials.

## Stack

Swift / SwiftUI · TypeScript · LLM tool calling · Xcode

## Status

Personal project, built and maintained solo. Backend runs in production; the app is in active development.

> Not financial advice — PortL AI is an analysis and paper-trading tool. It never touches real funds.
