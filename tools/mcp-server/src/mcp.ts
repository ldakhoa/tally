import { externalInstructions, READ_TOOLS, runReadTool } from "./adviser.ts";
import { todayKeyForOffsetMinutes } from "./money.ts";
import type { AdviserContext, MCPToolDefinition, MCPToolResult, VaultConfig } from "./types.ts";
import { runWriteTool, WRITE_TOOLS, type VaultWriteStore } from "./writes.ts";

export const SUPPORTED_VERSIONS = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
];

const ERROR_CODE = {
  parseError: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  invalidParams: -32602,
} as const;

export interface MCPHost {
  getConfig(): VaultConfig;
  getAdviserContext(todayKey: string): AdviserContext;
  getWriteStore(): VaultWriteStore;
  recordToolCall?(name: string): void;
}

export function listTools(allowsChanges: boolean): MCPToolDefinition[] {
  return allowsChanges ? [...READ_TOOLS, ...WRITE_TOOLS] : [...READ_TOOLS];
}

export async function handleMCPBody(
  rawBody: string,
  host: MCPHost,
  now: Date = new Date()
): Promise<string | null> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return JSON.stringify(rpcError(null, ERROR_CODE.parseError, "Parse error"));
  }

  if (Array.isArray(parsed)) {
    if (parsed.length === 0) {
      return JSON.stringify(rpcError(null, ERROR_CODE.invalidRequest, "Empty batch"));
    }
    const replies: unknown[] = [];
    for (const item of parsed) {
      const reply = await handleSingleMessage(item, host, now);
      if (reply !== null) replies.push(reply);
    }
    return replies.length > 0 ? JSON.stringify(replies) : null;
  }

  const single = await handleSingleMessage(parsed, host, now);
  return single !== null ? JSON.stringify(single) : null;
}

async function handleSingleMessage(
  msg: unknown,
  host: MCPHost,
  now: Date
): Promise<Record<string, unknown> | null> {
  if (!msg || typeof msg !== "object" || Array.isArray(msg)) {
    return rpcError(null, ERROR_CODE.invalidRequest, "Invalid request");
  }
  const obj = msg as Record<string, unknown>;
  if (obj.jsonrpc !== "2.0") {
    return rpcError(null, ERROR_CODE.invalidRequest, "Invalid request");
  }

  if (typeof obj.method !== "string") {
    if ("result" in obj || "error" in obj) return null;
    return rpcError(obj.id ?? null, ERROR_CODE.invalidRequest, "Invalid request");
  }

  if (!("id" in obj) || obj.id === null || obj.id === undefined) {
    // Notification: never answered.
    return null;
  }

  const id = obj.id;
  const method = obj.method;
  const params =
    obj.params && typeof obj.params === "object" && !Array.isArray(obj.params)
      ? (obj.params as Record<string, unknown>)
      : {};

  const config = host.getConfig();

  switch (method) {
    case "initialize": {
      const requested = typeof params.protocolVersion === "string" ? params.protocolVersion : "";
      const version = SUPPORTED_VERSIONS.includes(requested) ? requested : SUPPORTED_VERSIONS[0];
      return rpcResult(id, {
        protocolVersion: version,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "tally", title: "Tally", version: "1.0" },
        instructions: externalInstructions(config.currency, config.allowsChanges),
      });
    }

    case "ping":
      return rpcResult(id, {});

    case "tools/list": {
      const tools = listTools(config.allowsChanges).map((tool) => ({
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
        annotations: {
          readOnlyHint: tool.readOnly,
          destructiveHint: Boolean(tool.destructive),
          openWorldHint: false,
        },
      }));
      return rpcResult(id, { tools });
    }

    case "tools/call": {
      if (typeof params.name !== "string" || !params.name) {
        return rpcError(id, ERROR_CODE.invalidParams, "Missing tool name");
      }
      const toolName = params.name;
      const args =
        params.arguments && typeof params.arguments === "object" && !Array.isArray(params.arguments)
          ? (params.arguments as Record<string, unknown>)
          : {};
      const todayKey = todayKeyForOffsetMinutes(config.timeZoneOffsetMinutes, now);

      let outcome: MCPToolResult | null = runReadTool(
        toolName,
        args,
        host.getAdviserContext(todayKey)
      );
      if (outcome === null) {
        outcome = runWriteTool(toolName, args, host.getWriteStore(), todayKey, now.toISOString());
      }
      if (outcome === null) {
        return rpcError(id, ERROR_CODE.invalidParams, `Unknown tool: ${toolName}`);
      }
      host.recordToolCall?.(toolName);
      return rpcResult(id, {
        content: [{ type: "text", text: outcome.text }],
        isError: outcome.isError,
      });
    }

    default:
      return rpcError(id, ERROR_CODE.methodNotFound, `Method not found: ${method}`);
  }
}

function rpcResult(id: unknown, result: Record<string, unknown>): Record<string, unknown> {
  return { jsonrpc: "2.0", id, result };
}

function rpcError(id: unknown, code: number, message: string): Record<string, unknown> {
  return { jsonrpc: "2.0", id, error: { code, message } };
}
