/** Preserve the router's 32 MiB contract: four base64-encoded comparison PDFs can exceed the SDK's 4 MiB default.
 * The router parses first, so both its parser and transport receive this explicit byte ceiling. */
export const MCP_REQUEST_BYTES = 32 * 1024 * 1024;
/** GHSA-46jr-4wx8-v453 recommends an explicit bound; low-level Server has no McpServer option. */
export const MCP_ARGUMENT_ELEMENTS = 10_000;
const MCP_ARGUMENT_DEPTH = 128;

export class McpInputLimit extends Error {
  constructor(message: string, readonly status: number, readonly code: number) { super(message); }
}

/** Runs before SDK/Zod parsing and before any upstream opens. Count object members and array elements,
 * without recursive descent or collecting unbounded validation errors. Scalars consume no element budget. */
export function checkMcpArgumentLimits(body: unknown): void {
  for (const message of Array.isArray(body) ? body : [body]) {
    if (!message || typeof message !== 'object' || message.method !== 'tools/call') continue;
    const args = message.params?.arguments;
    const stack: Array<{ value: unknown; depth: number }> = [{ value: args, depth: 0 }];
    let count = 0;
    while (stack.length) {
      const { value, depth } = stack.pop()!;
      if (!value || typeof value !== 'object') continue;
      if (depth > MCP_ARGUMENT_DEPTH) throw new McpInputLimit('Tool arguments exceed the nesting limit of 128.', 400, -32602);
      const values = Array.isArray(value) ? value : Object.values(value);
      count += values.length;
      if (count > MCP_ARGUMENT_ELEMENTS) throw new McpInputLimit(`Tool arguments exceed the limit of ${MCP_ARGUMENT_ELEMENTS} array elements and object members.`, 400, -32602);
      for (const child of values) if (child && typeof child === 'object') stack.push({ value: child, depth: depth + 1 });
    }
  }
}
