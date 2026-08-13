import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type CallToolResult,
} from '@modelcontextprotocol/sdk/types.js';
import type { RouterConfig } from './config.js';
import { ChildPool } from './pool.js';
import { splitToolName, unionTools, type ManifestStore } from './manifest.js';
import { log } from './log.js';

const MCP_PATH = '/mcp';

function readBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (c: Buffer) => {
      size += c.length;
      if (size > 32 * 1024 * 1024) {
        reject(new Error('request body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve(undefined);
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(new Error(`invalid JSON body: ${(err as Error).message}`));
      }
    });
    req.on('error', reject);
  });
}

function json(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

/**
 * Builds a fresh MCP Server for one HTTP request.
 *
 * The server object is cheap and per-request; the expensive state (spawned upstream
 * children) lives in the shared pool, which is what lets ten Claude sessions share
 * one copy of each server instead of forking their own.
 */
function buildMcpServer(cfg: RouterConfig, manifest: ManifestStore, pool: ChildPool): Server {
  const server = new Server(
    { name: 'mcp-router', version: '0.1.0' },
    { capabilities: { tools: {} } }
  );

  // Read through the store, not a snapshot: a `mcp-router index` run while this
  // process is up must reach the next client that lists tools.
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: unionTools(manifest.current(), cfg.upstreams),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request): Promise<CallToolResult> => {
    const fullName = request.params.name;
    const split = splitToolName(fullName);
    if (!split) {
      return {
        isError: true,
        content: [{ type: 'text', text: `Tool "${fullName}" is not namespaced <server>__<tool>.` }],
      };
    }

    const { server: serverName, tool } = split;
    try {
      // First call for this upstream in this idle window is what spawns it.
      // pool.call, not acquire + callTool: the pool has to know a request is
      // outstanding or its idle reaper will close the child mid-call.
      const result = await pool.call(serverName, {
        name: tool,
        arguments: request.params.arguments ?? {},
      });
      return result as CallToolResult;
    } catch (err) {
      const message = (err as Error).message;
      log.error(`call ${serverName}${'__'}${tool} failed: ${message}`);
      // A dead upstream is reported as a tool error, never as a router crash:
      // one broken server must not take the other nine down with it.
      return {
        isError: true,
        content: [
          { type: 'text', text: `Upstream "${serverName}" failed to handle "${tool}": ${message}` },
        ],
      };
    }
  });

  return server;
}

export async function startRouter(
  cfg: RouterConfig,
  manifest: ManifestStore,
  pool: ChildPool
): Promise<{ close: () => Promise<void> }> {
  /*
   * Binding to loopback is not on its own enough to keep a browser out. A page the
   * user visits can point a hostname it controls at 127.0.0.1; the request is then
   * same-origin by the browser's reckoning, so no CORS preflight stands in the way
   * and a plain POST reaches this endpoint — which runs every MCP server the user
   * owns, with the user's full environment. The Host header is what distinguishes
   * that request from a real local client, so it is checked.
   */
  const allowedHosts = [
    ...new Set([
      `${cfg.host}:${cfg.port}`,
      `127.0.0.1:${cfg.port}`,
      `localhost:${cfg.port}`,
      `[::1]:${cfg.port}`,
    ]),
  ];

  const http = createServer((req, res) => {
    void (async () => {
      const url = new URL(req.url ?? '/', `http://${cfg.host}:${cfg.port}`);

      if (url.pathname === '/health') {
        return json(res, 200, { ok: true, upstreams: cfg.upstreams.length });
      }
      if (url.pathname === '/status') {
        return json(res, 200, {
          ok: true,
          port: cfg.port,
          idleMs: cfg.idleMs,
          children: pool.status(),
          tools: unionTools(manifest.current(), cfg.upstreams).length,
        });
      }
      if (url.pathname !== MCP_PATH) {
        return json(res, 404, { error: `not found; MCP endpoint is ${MCP_PATH}` });
      }

      // Stateless: a transport and server per request, so concurrent Claude sessions
      // never share MCP session state. Only the child pool is shared.
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableDnsRebindingProtection: true,
        allowedHosts,
      });
      const server = buildMcpServer(cfg, manifest, pool);

      res.on('close', () => {
        void transport.close().catch(() => undefined);
        void server.close().catch(() => undefined);
      });

      try {
        await server.connect(transport);
        const body = req.method === 'POST' ? await readBody(req) : undefined;
        await transport.handleRequest(req, res, body);
      } catch (err) {
        log.error(`request handling failed: ${(err as Error).message}`);
        if (!res.headersSent) {
          json(res, 500, {
            jsonrpc: '2.0',
            error: { code: -32603, message: (err as Error).message },
            id: null,
          });
        }
      }
    })();
  });

  await new Promise<void>((resolve, reject) => {
    http.once('error', reject);
    // Loopback by default: this endpoint runs every MCP server you own with your
    // environment, so it must not be reachable from the network.
    http.listen(cfg.port, cfg.host, () => {
      http.removeListener('error', reject);
      resolve();
    });
  });

  log.info(`mcp-router listening on http://${cfg.host}:${cfg.port}${MCP_PATH}`);

  return {
    close: async () => {
      await new Promise<void>((resolve) => http.close(() => resolve()));
      await pool.shutdown();
    },
  };
}
