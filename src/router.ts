import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type CallToolResult,
} from '@modelcontextprotocol/sdk/types.js';
import type { RouterConfig, UpstreamConfig } from './config.js';
import { UpstreamPool } from './pool.js';
import { splitToolName, unionTools, visibleTo, placardFor, type ManifestStore } from './manifest.js';
import { ClientResolver, UsageStore, projectOf } from './usage.js';
import { handleControl, controlToken, isControlPath } from './control.js';
import { handleAuthServer, isAuthServerPath, instructionsFor } from './oauth.js';
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
 * The authority check, for every route rather than for /mcp alone.
 *
 * It used to live only inside the MCP transport — `enableDnsRebindingProtection` on
 * `StreamableHTTPServerTransport` — which the dispatcher below reaches after /health,
 * /status and the whole control block have already answered. Measured on 2026-08-21:
 * /health, /status, /servers and /usage all returned 200 to `Host: evil.example` while
 * /mcp returned 403. A page on a domain whose DNS re-resolves to 127.0.0.1 is
 * same-origin with the router by the browser's reckoning, so it could read the usage
 * history, the project list and the full command line of every configured server. Not
 * a credential leak — `envKeys` is variable names only — but a reconnaissance surface
 * nobody chose to publish.
 *
 * So the check moved to the front of the ladder, where a route added later inherits it
 * rather than having to opt in.
 *
 * `/mcp`'s answer is the transport's own, byte for byte, because a parity row pins it:
 * `403 Forbidden`, `content-type: application/json`, and the JSON-RPC envelope in the
 * member order `jsonrpc, error, id`. Every other route gets the ordinary error envelope
 * this file's 404 already uses.
 *
 * One ordering consequence, deliberate: a POST to /mcp that is both wrongly addressed
 * and unparseable now answers 403 rather than the 500 it answered when `readBody` ran
 * first. Refusing a foreign authority before reading its body is the better order, and
 * the Swift port moves with it.
 *
 * A request with no Host header at all is left alone here — Node's own parser answers
 * 400 to an HTTP/1.1 request without one, so this branch is unreachable through it, and
 * inventing a refusal the reference cannot produce would be a divergence rather than a fix.
 */
function hostRefusal(
  req: IncomingMessage,
  res: ServerResponse,
  pathname: string,
  allowedHosts: string[]
): boolean {
  const host = req.headers.host;
  if (host === undefined || allowedHosts.includes(host)) return false;
  if (pathname === MCP_PATH) {
    json(res, 403, {
      jsonrpc: '2.0',
      error: { code: -32000, message: `Invalid Host header: ${host}` },
      id: null,
    });
  } else {
    json(res, 403, { error: `Invalid Host header: ${host}` });
  }
  return true;
}

/**
 * Builds a fresh MCP Server for one HTTP request.
 *
 * The server object is cheap and per-request; the expensive state (live upstreams)
 * lives in the shared pool, which is what lets ten Claude sessions share one copy
 * of each server instead of forking their own. Being per-request is also what makes
 * attribution possible: this closure knows which socket it is answering, so it can
 * name the process and directory behind every call it records.
 */
function buildMcpServer(
  cfg: RouterConfig,
  manifest: ManifestStore,
  pool: UpstreamPool,
  usage: UsageStore,
  identify: () => Promise<{ pid?: number; cwd?: string; client?: string }>
): Server {
  const server = new Server({ name: 'mcp-router', version: '0.1.0' }, { capabilities: { tools: {} } });

  // Read through the store, not a snapshot: a `mcp-router index` run while this
  // process is up must reach the next client that lists tools. The caller's own
  // directory is part of the answer, because a scoped server is served to some
  // projects and not others.
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    const who = await identify().catch(() => ({}) as { cwd?: string });
    return { tools: unionTools(manifest.current(), cfg.upstreams, { cwd: who.cwd }) };
  });

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
    const upstream = cfg.upstreams.find((u) => u.name === serverName);

    // A scoped server is not merely hidden from the list — it does not run for a
    // caller outside its projects. Hiding alone would leave it callable by any agent
    // that learned the name from somewhere else.
    if (upstream) {
      const who = await identify().catch(() => ({}) as { cwd?: string });
      if (!visibleTo(upstream, who.cwd)) {
        return {
          isError: true,
          content: [
            {
              type: 'text',
              text: `Upstream "${serverName}" is not available in this project${who.cwd ? ` (${who.cwd})` : ''}.`,
            },
          ],
        };
      }
    }

    /*
     * A placarded server answers instead of running. The error is written for the
     * model rather than for a log: it names the fault and the substitute, so the
     * assistant reroutes on this attempt rather than retrying a tool that cannot
     * work and spending the turn discovering that.
     */
    const placard = upstream ? placardFor(upstream, manifest.current().servers[serverName]) : undefined;
    if (placard) {
      return {
        isError: true,
        content: [
          {
            type: 'text',
            text:
              `Tool "${tool}" is INOPERATIVE: ${placard.reason}.` +
              (placard.substitute ? ` Use ${placard.substitute} instead.` : '') +
              ` Do not retry this tool; it will keep returning this.`,
          },
        ],
      };
    }

    const t0 = Date.now();
    // Read before the call: after it the upstream is live either way, so this is
    // the only moment at which "did this call pay the start-up cost" is knowable.
    const cold = !pool.isLive(serverName);
    let ok = true;
    let err: string | undefined;

    try {
      // First call for this upstream in this idle window is what starts it.
      // pool.call, not acquire + callTool: the pool has to know a request is
      // outstanding or its idle reaper will close the upstream mid-call.
      const result = (await pool.call(serverName, {
        name: tool,
        arguments: request.params.arguments ?? {},
      })) as CallToolResult;
      // A tool that reports its own failure is a failure in the record. Counting
      // it as a success would make the error rate a measure of transport health
      // rather than of whether the tool worked.
      if (result.isError) {
        ok = false;
        err = 'tool reported an error';
      }
      return result;
    } catch (e) {
      ok = false;
      err = (e as Error).message;
      log.error(`call ${serverName}__${tool} failed: ${err}`);
      // A dead upstream is reported as a tool error, never as a router crash:
      // one broken server must not take the other nine down with it.
      return {
        isError: true,
        content: [
          { type: 'text', text: `Upstream "${serverName}" failed to handle "${tool}": ${err}` },
        ],
      };
    } finally {
      // Attribution must never delay or break a call, so it runs after the result
      // is on its way and swallows everything.
      void identify()
        .then((who) => {
          usage.record({
            ts: new Date(t0).toISOString(),
            server: serverName,
            tool,
            ok,
            ms: Date.now() - t0,
            cold,
            pid: who.pid,
            cwd: who.cwd,
            project: projectOf(who.cwd),
            client: who.client,
            err,
          });
        })
        .catch(() => undefined);
    }
  });

  return server;
}

export async function startRouter(
  cfg: RouterConfig,
  manifest: ManifestStore,
  pool: UpstreamPool,
  upstreams: Map<string, UpstreamConfig>,
  usage: UsageStore
): Promise<{ close: () => Promise<void> }> {
  /*
   * Binding to loopback is not on its own enough to keep a browser out. A page the
   * user visits can point a hostname it controls at 127.0.0.1; the request is then
   * same-origin by the browser's reckoning, so no CORS preflight stands in the way
   * and a plain POST reaches this endpoint — which runs every MCP server the user
   * owns, with the user's full environment. The Host header is what distinguishes
   * that request from a real local client, so it is checked.
   *
   * The check itself runs in `hostRefusal` at the top of the dispatcher, so it guards every
   * route. The transport keeps its own copy below as defence in depth — the same list, so
   * the two can never disagree about what the bound authority is.
   */
  const allowedHosts = [
    ...new Set([
      `${cfg.host}:${cfg.port}`,
      `127.0.0.1:${cfg.port}`,
      `localhost:${cfg.port}`,
      `[::1]:${cfg.port}`,
    ]),
  ];

  const resolver = new ClientResolver();
  const token = controlToken();
  const deps = { cfg, upstreams, pool, manifest, usage };

  const http = createServer((req, res) => {
    void (async () => {
      const url = new URL(req.url ?? '/', `http://${cfg.host}:${cfg.port}`);

      /*
       * Start identifying the caller now, while it is certainly still alive.
       *
       * The lookup asks the OS who holds the other end of this socket, so it can
       * only answer while that process exists. Deferring it to the end of a tool
       * call — the natural place, since that is where the record is written — loses
       * every short-lived client: the answer arrives after the process has gone and
       * the call is logged with no project against it. The result is cached on the
       * socket, so awaiting it later costs nothing.
       */
      const identity = resolver.identify(req.socket);
      identity.catch(() => undefined);

      // Ahead of every route, so a route added below inherits it. See hostRefusal.
      if (hostRefusal(req, res, url.pathname, allowedHosts)) return;

      if (url.pathname === '/health') {
        return json(res, 200, { ok: true, upstreams: cfg.upstreams.length });
      }
      if (url.pathname === '/status') {
        return json(res, 200, {
          ok: true,
          port: cfg.port,
          idleMs: cfg.idleMs,
          children: pool.status(),
          pendingAuth: pool.pending(),
          tools: unionTools(manifest.current(), cfg.upstreams).length,
        });
      }

      // The control API mutates config and streams the call log, so it is handled
      // before the MCP endpoint and carries its own token check. Its body is only
      // read on its own paths: the request stream can be consumed exactly once, and
      // draining it here for a /mcp POST leaves the MCP transport waiting forever
      // on an "end" event that has already fired.
      if (isControlPath(url.pathname)) {
        const controlBody =
          req.method === 'POST' || req.method === 'PATCH'
            ? await readBody(req).catch(() => undefined)
            : undefined;
        if (await handleControl(req, res, url, controlBody, deps, token)) return;
      }

      if (url.pathname !== MCP_PATH) {
        return json(res, 404, { error: `not found; MCP endpoint is ${MCP_PATH}` });
      }

      // Stateless: a transport and server per request, so concurrent Claude sessions
      // never share MCP session state. Only the upstream pool is shared.
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableDnsRebindingProtection: true,
        allowedHosts,
      });
      const server = buildMcpServer(cfg, manifest, pool, usage, () => identity);

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

  /*
   * Identify a caller the instant its connection is accepted, not when its first
   * request is parsed. The lookup asks the OS who holds the other end of the socket,
   * so it can only answer while that process is alive, and it takes about 80ms — long
   * enough to lose a race against a client that fires one fast call and exits. Doing
   * it at accept time buys the whole request-parse and tool-call duration. A real MCP
   * client holds its connection for the session and would never have raced; a short
   * one-shot client is exactly the case this protects.
   */
  http.on('connection', (socket) => {
    void resolver.identify(socket).catch(() => undefined);
  });

  log.info(`mcp-router listening on http://${cfg.host}:${cfg.port}${MCP_PATH}`);

  return {
    close: async () => {
      usage.flush();
      await new Promise<void>((resolve) => http.close(() => resolve()));
      await pool.shutdown();
    },
  };
}
