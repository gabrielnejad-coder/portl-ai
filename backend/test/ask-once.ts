import { runAnalyst, parseChatRequest } from "../src/agent/run.ts";
import type { StreamEvent } from "../src/agent/types.ts";

const tools: string[] = [];
const req = parseChatRequest({ message: process.argv[2] ?? "is bitcoin over-leveraged rn", history: [], holdings: [] });
const result = await runAnalyst(req, AbortSignal.timeout(180_000), (e: StreamEvent) => {
  if (e.type === "tool_start") tools.push(e.name);
});
console.log("TOOLS:", tools.join(", "));
console.log("---");
console.log(result.text);
