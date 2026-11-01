import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';

/*
 * GET /marketplaces, through handleControl. The Mac and Windows Skills boards draw their Marketplaces tab from this
 * route. The shape is checked against the fields both models decode (app/Sources/MCPRouterKit/Control/SkillModels.swift
 * and app/windows/MCPRouter.Shell.Model/Skills/SkillModels.cs), in camelCase as every TypeScript route answers.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'marketplaces-route-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token';

const UPSTREAMS = new Map<string, UpstreamConfig>();

interface WireMarketplace {
  name: string;
  source: Record<string, unknown>;
  autoUpdate: boolean;
  installedPluginCount: number;
  suppliedSkillCount: number;
}

interface MarketplacesBody {
  marketplaces: WireMarketplace[];
}

function scratch(): string {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'marketplaces-route-')));
  made.push(parent);
  return parent;
}

function write(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text, 'utf8');
}

function skillFile(name: string, description: string): string {
  return `---\nname: ${name}\ndescription: ${description}\n---\n`;
}

/**
 * Claude's tree with three followed marketplaces. `fledgeling-plugins` is a GitHub source with auto-update on, two
 * installed plugins, and three of their skills in the skills directory. `local-dir` is a directory source with no
 * auto-update record, one plugin and one skill. `git-mirror` has a git source, which the clients' closed set does not
 * name, so it is left out. `solo` is a standalone skill, so it belongs to no marketplace.
 */
function claudeTree(): { claude: string; localDirectory: string } {
  const claude = join(scratch(), '.claude');
  const localDirectory = join(scratch(), 'local-dir');
  const trawl = join(claude, 'plugins', 'cache', 'fledgeling-plugins', 'trawl', '2.2.0');
  const lint = join(claude, 'plugins', 'cache', 'fledgeling-plugins', 'lint', '1.0.0');
  const demo = join(claude, 'plugins', 'cache', 'local-dir', 'demo', '0.1.0');
  write(join(trawl, 'skills', 'trawl', 'SKILL.md'), skillFile('trawl', 'mines sessions'));
  write(join(trawl, 'skills', 'trawl-report', 'SKILL.md'), skillFile('trawl-report', 'reports on sessions'));
  write(join(lint, 'skills', 'lint', 'SKILL.md'), skillFile('lint', 'lints a tree'));
  write(join(demo, 'skills', 'demo', 'SKILL.md'), skillFile('demo', 'a demo skill'));
  write(join(claude, 'skills', 'solo', 'SKILL.md'), skillFile('solo', 'a standalone skill'));
  mkdirSync(join(claude, 'skills'), { recursive: true });
  symlinkSync(join(trawl, 'skills', 'trawl'), join(claude, 'skills', 'trawl'));
  symlinkSync(join(trawl, 'skills', 'trawl-report'), join(claude, 'skills', 'trawl-report'));
  symlinkSync(join(lint, 'skills', 'lint'), join(claude, 'skills', 'lint'));
  symlinkSync(join(demo, 'skills', 'demo'), join(claude, 'skills', 'demo'));

  write(
    join(claude, 'plugins', 'installed_plugins.json'),
    JSON.stringify({
      version: 2,
      plugins: {
        'trawl@fledgeling-plugins': [{ scope: 'user', installPath: trawl, version: '2.2.0' }],
        'lint@fledgeling-plugins': [{ scope: 'user', installPath: lint, version: '1.0.0' }],
        'demo@local-dir': [{ scope: 'user', installPath: demo, version: '0.1.0' }],
      },
    })
  );
  write(
    join(claude, 'plugins', 'known_marketplaces.json'),
    JSON.stringify({
      'fledgeling-plugins': {
        source: { source: 'github', repo: 'fledgeling-co/fledgeling-plugins' },
        installLocation: join(claude, 'plugins', 'marketplaces', 'fledgeling-plugins'),
        lastUpdated: '2026-10-01T00:00:00.000Z',
        autoUpdate: true,
      },
      'local-dir': {
        source: { source: 'directory', path: localDirectory },
        installLocation: localDirectory,
        lastUpdated: '2026-10-02T00:00:00.000Z',
      },
      'git-mirror': {
        source: { source: 'git', url: 'https://example.com/mirror.git' },
        installLocation: join(claude, 'plugins', 'marketplaces', 'git-mirror'),
        lastUpdated: '2026-10-03T00:00:00.000Z',
        autoUpdate: false,
      },
    })
  );
  return { claude, localDirectory };
}

interface Call {
  method: string;
  path: string;
  token?: boolean;
}

/** Drive one request through handleControl and capture what it answered. */
async function answer(call: Call, deps: Partial<ControlDeps>): Promise<{ status: number; json: unknown }> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (call.token !== false) headers['x-mcpr-token'] = TOKEN;
  const req = { method: call.method, headers } as unknown as IncomingMessage;

  let status = 0;
  let text = '';
  const res = {
    writeHead(code: number) {
      status = code;
    },
    end(payload: string) {
      text = payload;
    },
  } as unknown as ServerResponse;

  const url = new URL(call.path, 'http://127.0.0.1:8879');
  const handled = await handleControl(req, res, url, undefined, { upstreams: UPSTREAMS, ...deps } as unknown as ControlDeps, TOKEN);
  assert.equal(handled, true, `${call.method} ${call.path} was not claimed by the control API`);
  return { status, json: text ? JSON.parse(text) : undefined };
}

async function getMarketplaces(claude: string): Promise<MarketplacesBody> {
  const res = await answer({ method: 'GET', path: '/marketplaces' }, { claudeHome: claude });
  assert.equal(res.status, 200);
  return res.json as MarketplacesBody;
}

/** Every file and directory under a tree, with its kind and bytes, so a read that wrote anything shows as a diff. */
function snapshot(root: string): string[] {
  const out: string[] = [];
  const visit = (dir: string): void => {
    for (const name of readdirSync(dir).sort()) {
      const path = join(dir, name);
      const stat = lstatSync(path);
      if (stat.isSymbolicLink()) out.push(`${path} -> symlink`);
      else if (stat.isDirectory()) {
        out.push(`${path}/`);
        visit(path);
      } else out.push(`${path} ${readFileSync(path, 'utf8')}`);
    }
  };
  visit(root);
  return out;
}

test('M1 — GET /marketplaces answers the followed marketplaces the clients decode, in camelCase', async () => {
  const { claude, localDirectory } = claudeTree();
  const body = await getMarketplaces(claude);

  // The clients decode the envelope key `marketplaces`, and nothing else is read from the body.
  assert.deepEqual(Object.keys(body), ['marketplaces']);
  // Each entry carries the five fields Marketplace in SkillModels.swift and SkillModels.cs requires. The git-source
  // entry is absent: a source kind the closed set does not name cannot be decoded, so it is left out rather than sent.
  assert.deepEqual(body.marketplaces, [
    {
      name: 'fledgeling-plugins',
      source: { kind: 'github', repo: 'fledgeling-co/fledgeling-plugins' },
      autoUpdate: true,
      installedPluginCount: 2,
      suppliedSkillCount: 3,
    },
    {
      name: 'local-dir',
      source: { kind: 'directory', path: localDirectory },
      // No record of auto-update is read as off, which is the value the clients' models hold.
      autoUpdate: false,
      installedPluginCount: 1,
      suppliedSkillCount: 1,
    },
  ]);
});

test('M2 — GET /marketplaces is token-gated, and is GET only', async () => {
  const { claude } = claudeTree();

  const unauthorised = await answer({ method: 'GET', path: '/marketplaces', token: false }, { claudeHome: claude });
  assert.equal(unauthorised.status, 401);

  const write = await answer({ method: 'POST', path: '/marketplaces' }, { claudeHome: claude });
  assert.equal(write.status, 405);
});

test('M3 — an absent registry is no marketplaces, and an absent Claude home is unavailable', async () => {
  const claude = join(scratch(), '.claude');
  mkdirSync(claude, { recursive: true });
  const empty = await getMarketplaces(claude);
  assert.deepEqual(empty, { marketplaces: [] });

  const unavailable = await answer({ method: 'GET', path: '/marketplaces' }, {});
  assert.equal(unavailable.status, 503);
});

test('M4 — a registry that cannot be read answers 503 naming the file, never an empty list', async () => {
  const claude = join(scratch(), '.claude');
  write(join(claude, 'plugins', 'known_marketplaces.json'), '{ not json');

  const res = await answer({ method: 'GET', path: '/marketplaces' }, { claudeHome: claude });
  assert.equal(res.status, 503);
  assert.match(String((res.json as { error: string }).error), /known_marketplaces\.json/);
});

test('M5 — GET /marketplaces writes nothing under Claude’s home', async () => {
  const { claude } = claudeTree();
  const before = snapshot(claude);
  await getMarketplaces(claude);
  assert.deepEqual(snapshot(claude), before);
});
