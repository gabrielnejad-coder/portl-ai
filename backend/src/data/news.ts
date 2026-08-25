/**
 * Google News RSS client.
 *
 * Everything returned here is untrusted third-party text. It is sanitized on
 * the way out and delivered to the model only inside tool results wrapped by
 * `wrapUntrusted` — never in the system prompt.
 */

import { log } from "../util/log.ts";
import { TtlCache, TTL } from "./cache.ts";
import { SlidingWindowLimiter } from "./rateLimiter.ts";
import { sanitizeText } from "./sanitize.ts";

const cache = new TtlCache({ maxEntries: 100 });
const limiter = new SlidingWindowLimiter({ max: 30, windowMs: 60_000 });

export type Article = {
  title: string;
  source: string;
  publishedAt: string | null;
  ageMinutes: number | null;
  /**
   * Crude keyword heuristic, carried over from the iOS app. It is a lexical
   * signal only — the model is told in the tool result not to treat it as a
   * judgement about market impact.
   */
  keywordImpactHint: "high" | "medium" | "low";
};

const HIGH_KEYWORDS = [
  "crash", "plunge", "plummet", "collapse", "surge", "soar", "skyrocket", "spike",
  "breaking", "urgent", "emergency", "war", "invasion", "sanctions", "ban",
  "default", "recession", "shutdown", "rate hike", "rate cut", "hack", "exploit",
  "all-time high", "all-time low", "record high", "record low", "etf approval",
  "liquidation", "bankruptcy", "indictment", "lawsuit",
];

const MEDIUM_KEYWORDS = [
  "rise", "fall", "drop", "gain", "rally", "dip", "volatil", "inflation", "gdp",
  "employment", "report", "announce", "launch", "approval", "ruling", "federal reserve",
  "sec", "regulation", "partnership", "acquisition", "merger", "upgrade", "downgrade",
  "outflow", "inflow", "unlock",
];

function impactHint(title: string): Article["keywordImpactHint"] {
  const t = title.toLowerCase();
  if (HIGH_KEYWORDS.some((k) => t.includes(k))) return "high";
  if (MEDIUM_KEYWORDS.some((k) => t.includes(k))) return "medium";
  return "low";
}

/** Decode the small set of XML entities that appear in RSS titles. */
function decodeEntities(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, "&");
}

function tagContent(block: string, tag: string): string | null {
  const m = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i").exec(block);
  if (!m || m[1] === undefined) return null;
  const inner = m[1].replace(/^<!\[CDATA\[([\s\S]*?)\]\]>$/, "$1");
  return decodeEntities(inner);
}

/**
 * Parse an RSS document into articles. Deliberately regex-based: the input is
 * a narrow, well-known feed shape, and this avoids pulling an XML parser (and
 * its XXE surface) into the dependency tree.
 */
export function parseRss(xml: string, now = Date.now()): Article[] {
  const items = xml.match(/<item[\s\S]*?<\/item>/gi) ?? [];
  const out: Article[] = [];

  for (const item of items) {
    const rawTitle = tagContent(item, "title");
    if (!rawTitle) continue;

    // Google News appends " - Publisher" to titles; prefer the <source> tag.
    const sourceTag = tagContent(item, "source");
    const dashSplit = rawTitle.lastIndexOf(" - ");
    const title = sanitizeText(
      sourceTag === null && dashSplit > 20 ? rawTitle.slice(0, dashSplit) : rawTitle,
      220,
    );
    if (!title) continue;

    const pubDate = tagContent(item, "pubDate");
    const parsed = pubDate ? Date.parse(pubDate) : Number.NaN;
    const hasDate = Number.isFinite(parsed);

    out.push({
      title,
      source: sanitizeText(sourceTag ?? (dashSplit > 20 ? rawTitle.slice(dashSplit + 3) : "Unknown"), 48),
      publishedAt: hasDate ? new Date(parsed).toISOString() : null,
      ageMinutes: hasDate ? Math.max(0, Math.round((now - parsed) / 60_000)) : null,
      keywordImpactHint: impactHint(title),
    });
  }

  return out;
}

export async function fetchNews(
  query: string,
  limit = 12,
  signal?: AbortSignal,
): Promise<Article[]> {
  const key = `news:${query.toLowerCase()}`;

  const r = await cache.fetch(
    key,
    TTL.news,
    async () => {
      await limiter.acquire(signal);

      const url = new URL("https://news.google.com/rss/search");
      url.searchParams.set("q", query);
      url.searchParams.set("hl", "en-US");
      url.searchParams.set("gl", "US");
      url.searchParams.set("ceid", "US:en");

      const timeout = AbortSignal.timeout(10_000);
      const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;

      const res = await fetch(url, {
        headers: { accept: "application/rss+xml, application/xml, text/xml" },
        signal: combined,
      });
      if (!res.ok) throw new Error(`Google News RSS ${res.status}`);

      const xml = await res.text();
      const articles = parseRss(xml);
      log.debug("news fetched", { query, count: articles.length });
      return articles;
    },
    { maxStaleMs: 60 * 60_000 },
  );

  return r.value
    .slice()
    .sort((a, b) => (a.ageMinutes ?? 1e9) - (b.ageMinutes ?? 1e9))
    .slice(0, Math.min(Math.max(limit, 1), 25));
}
