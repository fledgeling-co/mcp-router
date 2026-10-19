import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { handleControl, type ControlDeps } from '../src/control.js';
import { diskHarnessInventory } from '../src/harness.js';
import { parseMiniToml, TOMLProblem } from '../src/minitoml.js';
import type { UpstreamConfig } from '../src/config.js';

const PORT = 8879;
const TOKEN = 'harness-test-token-0123456789abcdef';

/** The fields `DetectedHarness` in app/Sources/MCPRouterKit/Boards/HarnessModels.swift requires. */
const ROW_KEYS = [
  'bridge',
  'capability',
  'displayName',
  'duplicateCount',
  'duplicates',
  'entries',
  'exists',
  'harness',
  'httpCapability',
  'path',
  'route',
  'state',
  'unparsed',
  'unreadable',
].sort();

const ENVELOPE_KEYS = ['harnesses', 'port', 'readAt', 'scope'].sort();

const STATES = ['not-wired', 'wired-http', 'wired-shim', 'wired-with-duplicates'];
const ROUTES = ['none', 'http', 'stdio-shim'];
const CAPABILITIES = ['measured', 'documented', 'unknown'];

/** A home directory with one config per harness shape the reader has to tell apart. */
function fixtureHome(): string {
  const home = mkdtempSync(join(tmpdir(), 'harness-home-'));
  const write = (relative: string, text: string) => {
    const path = join(home, relative);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, text);
  };
  // Direct HTTP to the router, a name duplicate of `alpha`, and an identity duplicate of it.
  write('.claude.json', JSON.stringify({
    mcpServers: {
      router: { type: 'http', url: `http://127.0.0.1:${PORT}/mcp` },
      alpha: { command: 'node', args: ['alpha.js'] },
      'alpha-copy': { command: 'node', args: ['alpha.js'] },
    },
  }));
  // A stdio bridge to the router: one child process per session.
  write(
    'Library/Application Support/Claude/claude_desktop_config.json',
    JSON.stringify({
      mcpServers: {
        bridge: { command: 'npx', args: ['-y', 'mcp-remote', `http://127.0.0.1:${PORT}/mcp`] },
      },
    }),
  );
  write('.codex/config.toml', `[mcp_servers.router]\nurl = "http://127.0.0.1:${PORT}/mcp"\n`);
  // Gemini spells its endpoint `serverUrl`, which only its own dialect reads.
  write(
    '.gemini/config/mcp_config.json',
    JSON.stringify({ mcpServers: { router: { serverUrl: `http://127.0.0.1:${PORT}/mcp` } } }),
  );
  // A table the reader passes over, then a server whose args span several lines.
  write(
    '.grok/config.toml',
    '[[marketplace.sources]]\nname = "x"\n\n[mcp_servers.proctor]\ncommand = "npx"\nargs = [\n  "-y",\n  "proctor"\n]\n',
  );
  // A file that is present and broken: unreadable, not an empty harness.
  write('.cursor/mcp.json', '{ "mcpServers": ');
  return home;
}

/** Every file the route reads, with its bytes and mtime, for the read-only check. */
function snapshot(home: string): Map<string, string> {
  const files = [
    '.claude.json',
    'Library/Application Support/Claude/claude_desktop_config.json',
    '.codex/config.toml',
    '.gemini/config/mcp_config.json',
    '.grok/config.toml',
    '.cursor/mcp.json',
  ];
  return new Map(files.map((f) => {
    const path = join(home, f);
    return [f, `${readFileSync(path, 'utf8')}\n${statSync(path).mtimeMs}`];
  }));
}

function upstreams(): UpstreamConfig[] {
  return [{
    transport: 'stdio',
    name: 'alpha',
    command: 'node',
    args: ['alpha.js'],
    env: {},
    envFiles: [],
  }];
}

interface Reply {
  status: number;
  body: string;
}

/** Drive the control handler the way the dispatcher does, without a socket. */
async function getHarnesses(deps: Partial<ControlDeps>, headers: Record<string, string>): Promise<Reply> {
  const reply: Reply = { status: 0, body: '' };
  const req = { method: 'GET', headers } as unknown as IncomingMessage;
  const res = {
    writeHead(status: number) {
      reply.status = status;
      return res;
    },
    end(payload?: string) {
      reply.body = payload ?? '';
    },
  } as unknown as ServerResponse;
  const full = {
    cfg: { port: PORT },
    upstreams: new Map(upstreams().map((u) => [u.name, u])),
    ...deps,
  } as unknown as ControlDeps;
  await handleControl(req, res, new URL('http://127.0.0.1/harnesses'), undefined, full, TOKEN);
  return reply;
}

function assertMacDetectedHarness(row: Record<string, unknown>): void {
  assert.deepEqual(Object.keys(row).sort(), ROW_KEYS);
  assert.equal(typeof row.harness, 'string');
  assert.equal(typeof row.displayName, 'string');
  assert.equal(typeof row.path, 'string');
  assert.equal(typeof row.exists, 'boolean');
  assert.ok(row.unreadable === null || typeof row.unreadable === 'string');
  assert.ok(STATES.includes(row.state as string), `state ${String(row.state)}`);
  assert.ok(ROUTES.includes(row.route as string), `route ${String(row.route)}`);
  assert.ok(row.bridge === null || typeof row.bridge === 'string');
  assert.equal(typeof row.entries, 'number');
  assert.equal(typeof row.duplicateCount, 'number');
  assert.ok(Array.isArray(row.duplicates));
  for (const d of row.duplicates as Record<string, unknown>[]) {
    assert.deepEqual(Object.keys(d).sort(), ['basis', 'harnessName', 'routerName']);
    assert.ok(['name', 'identity'].includes(d.basis as string));
  }
  assert.ok(Array.isArray(row.unparsed));
  assert.equal(typeof row.httpCapability, 'string');
  assert.ok(CAPABILITIES.includes(row.capability as string), `capability ${String(row.capability)}`);
}

describe('GET /harnesses', () => {
  test('answers 200 with an envelope every Mac DetectedHarness field decodes from', async () => {
    const home = fixtureHome();
    try {
      const reply = await getHarnesses(
        { harnesses: diskHarnessInventory(home) },
        { 'x-mcpr-token': TOKEN },
      );
      assert.equal(reply.status, 200);
      const envelope = JSON.parse(reply.body) as Record<string, unknown>;
      assert.deepEqual(Object.keys(envelope).sort(), ENVELOPE_KEYS);
      assert.equal(envelope.port, PORT);
      assert.equal(envelope.scope, 'global');
      assert.ok(!Number.isNaN(Date.parse(envelope.readAt as string)), 'readAt is a date');
      const rows = envelope.harnesses as Record<string, unknown>[];
      assert.ok(rows.length > 0);
      for (const row of rows) assertMacDetectedHarness(row);
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });

  test('reads each harness the way the Swift reconciliation does', async () => {
    const home = fixtureHome();
    try {
      const reply = await getHarnesses(
        { harnesses: diskHarnessInventory(home) },
        { 'x-mcpr-token': TOKEN },
      );
      const rows = (JSON.parse(reply.body) as { harnesses: Record<string, unknown>[] }).harnesses;
      const by = (harness: string) => rows.find((r) => r.harness === harness)!;

      const claude = by('claudeCode');
      assert.equal(claude.state, 'wired-with-duplicates');
      assert.equal(claude.route, 'http');
      assert.equal(claude.entries, 2);
      assert.equal(claude.duplicateCount, 2);
      assert.deepEqual(claude.duplicates, [
        { harnessName: 'alpha', routerName: 'alpha', basis: 'name' },
        { harnessName: 'alpha-copy', routerName: 'alpha', basis: 'identity' },
      ]);
      assert.equal(claude.capability, 'measured');

      const desktop = by('claudeDesktop');
      assert.equal(desktop.state, 'wired-shim');
      assert.equal(desktop.route, 'stdio-shim');
      assert.equal(desktop.bridge, 'mcp-remote');
      assert.equal(desktop.capability, 'documented');

      assert.equal(by('codexCLI').state, 'wired-http');
      assert.equal(by('geminiCLI').state, 'wired-http', 'Gemini reads serverUrl');

      const grok = by('grokCLI');
      assert.equal(grok.state, 'not-wired');
      assert.equal(grok.entries, 1, 'the multi-line args array is one server');
      assert.deepEqual(grok.unparsed, []);

      const cursor = by('cursor');
      assert.equal(cursor.exists, true);
      assert.equal(typeof cursor.unreadable, 'string', 'a broken file is named, not read as empty');
      assert.equal(cursor.state, 'not-wired');

      const opencode = by('opencode');
      assert.equal(opencode.exists, false);
      assert.equal(opencode.unreadable, null);
      assert.equal(opencode.capability, 'unknown');

      assert.equal(rows.some((r) => r.harness === 'chatGPTCLI'), false, 'project-scoped, so absent globally');
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });

  test('refuses a request without the control token, and one with the wrong token', async () => {
    const home = fixtureHome();
    try {
      const deps = { harnesses: diskHarnessInventory(home) };
      const none = await getHarnesses(deps, {});
      assert.equal(none.status, 401);
      assert.equal(none.body.includes('"harnesses"'), false, 'no harness data without the token');
      const wrong = await getHarnesses(deps, { 'x-mcpr-token': 'nope' });
      assert.equal(wrong.status, 401);
      const bearer = await getHarnesses(deps, { authorization: `Bearer ${TOKEN}` });
      assert.equal(bearer.status, 200);
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });

  test('answers 503 when the router has no inventory source, rather than an empty list', async () => {
    const reply = await getHarnesses({}, { 'x-mcpr-token': TOKEN });
    assert.equal(reply.status, 503);
    assert.match(reply.body, /no inventory source/);
  });

  test('never writes a harness config', async () => {
    const home = fixtureHome();
    try {
      const before = snapshot(home);
      const deps = { harnesses: diskHarnessInventory(home) };
      await getHarnesses(deps, { 'x-mcpr-token': TOKEN });
      await getHarnesses(deps, { 'x-mcpr-token': TOKEN });
      assert.deepEqual(snapshot(home), before);
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });
});

describe('minitoml', () => {
  test('refuses a multi-line string and names its line', () => {
    assert.throws(
      () => parseMiniToml('[mcp_servers.x]\ncommand = """\nnode\n"""\n'),
      (err: unknown) => err instanceof TOMLProblem && err.line === 2,
    );
  });

  test('refuses an array of tables where it would change a server', () => {
    assert.throws(
      () => parseMiniToml('[[mcp_servers.x]]\ncommand = "node"\n'),
      (err: unknown) => err instanceof TOMLProblem && /arrays of tables/.test(err.detail),
    );
  });
});
