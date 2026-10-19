import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { ControlDeps } from '../src/control.js';
import type { UpstreamConfig } from '../src/config.js';
import { ExtensionStore } from '../src/extensions.js';

/*
 * GET /skills, through handleControl. The Mac Skills board decodes this route, so the shape is checked against
 * the fields its model requires (app/Sources/MCPRouterKit/Control/SkillModels.swift), and Keep is checked against
 * the record POST /extensions/plugins/<plugin>@<marketplace>/keep writes.
 *
 * The router home is set before control.ts loads, because config.ts reads it at import.
 */
const made: string[] = [];
after(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

const home = mkdtempSync(join(tmpdir(), 'skills-route-home-'));
made.push(home);
process.env.MCP_ROUTER_HOME = home;

const { handleControl } = await import('../src/control.js');

const TOKEN = 'test-token';

const UPSTREAMS = new Map<string, UpstreamConfig>();

interface WireSkill {
  name: string;
  description: string | null;
  path: string;
  source: Record<string, unknown>;
  presence: Record<string, string>;
  held: Record<string, unknown> | null;
  provenance: unknown;
}

interface WireClient {
  id: string;
  displayName: string;
  supportsSkills: boolean;
  root: string | null;
  status: string;
  reason: string | null;
}

interface SkillsBody {
  skills: WireSkill[];
  clients: WireClient[];
}

function scratch(): string {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'skills-route-')));
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

/** The marketplace offers `version` of the demo plugin. Claude keeps this catalogue under plugins/marketplaces. */
function offer(claude: string, version: string): void {
  write(
    join(claude, 'plugins', 'marketplaces', 'market', '.claude-plugin', 'marketplace.json'),
    JSON.stringify({ name: 'market', plugins: [{ name: 'demo', version }] })
  );
}

/**
 * A Claude tree with one plugin skill, reached through a symlink the way Claude lays it out, one standalone skill,
 * and an installed demo plugin at 1.0.0 whose marketplace offers `offered`.
 */
function claudeTree(offered: string): string {
  const claude = join(scratch(), '.claude');
  const install = join(claude, 'plugins', 'cache', 'market', 'demo', '1.0.0');
  write(join(install, 'skills', 'alpha', 'SKILL.md'), skillFile('alpha', 'a plugin skill'));
  write(join(claude, 'skills', 'solo', 'SKILL.md'), skillFile('solo', 'a standalone skill'));
  mkdirSync(join(claude, 'skills'), { recursive: true });
  symlinkSync(join(install, 'skills', 'alpha'), join(claude, 'skills', 'alpha'));
  write(
    join(claude, 'plugins', 'installed_plugins.json'),
    JSON.stringify({ version: 2, plugins: { 'demo@market': [{ scope: 'user', installPath: install, version: '1.0.0' }] } })
  );
  offer(claude, offered);
  return claude;
}

function scratchStore(): ExtensionStore {
  return new ExtensionStore(join(scratch(), 'extensions'), () => 1000);
}

interface Call {
  method: string;
  path: string;
  body?: unknown;
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
  const handled = await handleControl(
    req,
    res,
    url,
    call.body,
    { upstreams: UPSTREAMS, ...deps } as unknown as ControlDeps,
    TOKEN
  );
  assert.equal(handled, true, `${call.method} ${call.path} was not claimed by the control API`);
  return { status, json: text ? JSON.parse(text) : undefined };
}

async function getSkills(claude: string, store: ExtensionStore = scratchStore()): Promise<SkillsBody> {
  const res = await answer({ method: 'GET', path: '/skills' }, { claudeHome: claude, extensions: store });
  assert.equal(res.status, 200);
  return res.json as SkillsBody;
}

function skillNamed(body: SkillsBody, name: string): WireSkill {
  const found = body.skills.find((skill) => skill.name === name);
  assert.ok(found, `no skill named ${name} in ${JSON.stringify(body.skills.map((s) => s.name))}`);
  return found;
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

const PRESENCE_VALUES = ['present', 'absent', 'unreadable'];
const CLIENT_STATUSES = ['read', 'absent', 'unreadable', 'unsupported'];

test('S1 — GET /skills answers the members the board decodes, each with the fields its model requires', async () => {
  const claude = claudeTree('1.1.0');
  const body = await getSkills(claude);

  // promoteFromCache is the one member the router adds beside the two the board read before it: Promote is enabled on it.
  assert.deepEqual(Object.keys(body).sort(), ['clients', 'promoteFromCache', 'skills']);
  assert.ok(body.skills.length >= 2);
  for (const skill of body.skills) {
    // SkillModels.swift: Skill has name, path, source and presence required; description, held and provenance optional.
    for (const field of ['name', 'path', 'source', 'presence']) {
      assert.ok(field in skill, `skill ${skill.name} lacks ${field}`);
    }
    for (const value of Object.values(skill.presence)) assert.ok(PRESENCE_VALUES.includes(value), value);
    // SkillSource is a closed set on `kind`. A plugin origin is PluginOrigin's fields in the same object.
    const kind = skill.source.kind;
    assert.ok(kind === 'plugin' || kind === 'standalone', `unknown source kind ${String(kind)}`);
    if (kind === 'plugin') {
      for (const field of ['plugin', 'marketplace', 'pluginVersion', 'siblingSkillCount']) {
        assert.ok(field in skill.source, `plugin source of ${skill.name} lacks ${field}`);
      }
    } else {
      assert.ok('path' in skill.source, `standalone source of ${skill.name} lacks path`);
    }
    // HeldVersion: all three members are required, and addedCapabilities is an array rather than absent.
    if (skill.held !== null) {
      for (const field of ['pluginVersion', 'addedCapabilities', 'affectedSkillCount']) {
        assert.ok(field in skill.held, `held of ${skill.name} lacks ${field}`);
      }
      assert.ok(Array.isArray(skill.held.addedCapabilities));
    }
  }
  for (const client of body.clients) {
    // SkillClient: id, displayName, supportsSkills and status are required; root and reason are optional.
    for (const field of ['id', 'displayName', 'supportsSkills', 'status']) {
      assert.ok(field in client, `client ${client.id} lacks ${field}`);
    }
    assert.ok(CLIENT_STATUSES.includes(client.status), client.status);
  }
});

test('S2 — a skill reached through a symlink into an installed plugin reports that plugin, at its real path', async () => {
  const claude = claudeTree('1.0.0');
  const alpha = skillNamed(await getSkills(claude), 'alpha');

  assert.equal(alpha.path, join(claude, 'plugins', 'cache', 'market', 'demo', '1.0.0', 'skills', 'alpha'));
  assert.deepEqual(alpha.source, {
    kind: 'plugin',
    plugin: 'demo',
    marketplace: 'market',
    pluginVersion: '1.0.0',
    installedAt: null,
    lastUpdated: null,
    commit: null,
    siblingSkillCount: 1,
  });
  assert.equal(alpha.presence.claudeCode, 'present');
  assert.equal(alpha.description, 'a plugin skill');
});

test('S3 — a skill no plugin owns is standalone, has no version, and is never held', async () => {
  const claude = claudeTree('1.1.0');
  const solo = skillNamed(await getSkills(claude), 'solo');

  assert.deepEqual(solo.source, { kind: 'standalone', path: join(claude, 'skills', 'solo') });
  assert.equal(solo.held, null);
  assert.equal(solo.provenance, null);
});

test('S4 — a plugin whose marketplace offers a newer version is held, with the version and a count of what promoting would move', async () => {
  const claude = claudeTree('1.1.0');
  const alpha = skillNamed(await getSkills(claude), 'alpha');

  assert.equal(alpha.held?.pluginVersion, '1.1.0');
  assert.equal(alpha.held?.affectedSkillCount, 1);
  // A held version that adds nothing is trusted, so a held version must name what it adds. The router does not yet
  // compare capabilities, so it names that instead of an empty list that would read as "asks for nothing".
  assert.ok(Array.isArray(alpha.held?.addedCapabilities) && alpha.held.addedCapabilities.length > 0);
});

test('S5 — a plugin whose marketplace offers nothing newer is not held', async () => {
  const claude = claudeTree('1.0.0');
  const alpha = skillNamed(await getSkills(claude), 'alpha');
  assert.equal(alpha.held, null);
});

test('S6 — clients: Claude Code is read; the two with no skills mechanism say so; the rest are unknown, never absent', async () => {
  const claude = claudeTree('1.0.0');
  const body = await getSkills(claude);
  const clientNamed = (id: string): WireClient => {
    const found = body.clients.find((client) => client.id === id);
    assert.ok(found, `no client ${id}`);
    return found;
  };

  assert.equal(clientNamed('claudeCode').status, 'read');
  assert.equal(clientNamed('claudeCode').root, join(claude, 'skills'));
  assert.equal(clientNamed('claudeDesktop').supportsSkills, false);
  assert.equal(clientNamed('claudeDesktop').status, 'unsupported');
  assert.equal(clientNamed('grokCLI').status, 'unsupported');
  assert.equal(clientNamed('codexCLI').supportsSkills, true);
  // This router reads Claude's directories only. Another client's directory is unknown here, and presence must say
  // so: the board draws a missing key as absent, which would assert the skill is not installed where nobody looked.
  assert.equal(clientNamed('codexCLI').status, 'unreadable');
  assert.equal(skillNamed(body, 'alpha').presence.codexCLI, 'unreadable');
});

test('S7 — a Claude tree with no skills directory is absent, not unreadable, and lists no skills', async () => {
  const claude = join(scratch(), '.claude');
  mkdirSync(claude, { recursive: true });
  const body = await getSkills(claude);

  assert.equal(body.skills.length, 0);
  assert.equal(body.clients.find((client) => client.id === 'claudeCode')?.status, 'absent');
});

test('S8 — a plugin register that cannot be read is reported on Claude Code, with the register named as the reason', async () => {
  const claude = claudeTree('1.0.0');
  write(join(claude, 'plugins', 'installed_plugins.json'), '{ not json');
  const body = await getSkills(claude);

  const claudeCode = body.clients.find((client) => client.id === 'claudeCode');
  assert.equal(claudeCode?.status, 'unreadable');
  assert.match(claudeCode?.reason ?? '', /installed_plugins\.json/);
});

test('S9 — a dangling symlink and a directory with no SKILL.md are left out, without failing the listing', async () => {
  const claude = claudeTree('1.0.0');
  symlinkSync(join(claude, 'nowhere'), join(claude, 'skills', 'gone'));
  write(join(claude, 'skills', 'bare', 'README.md'), 'no descriptor here\n');
  const body = await getSkills(claude);

  assert.deepEqual(body.skills.map((skill) => skill.name).sort(), ['alpha', 'solo']);
});

test('S10 — GET /skills needs the token, and any other method on it is 405', async () => {
  const claude = claudeTree('1.0.0');
  const deps = { claudeHome: claude, extensions: scratchStore() };

  const unauthorised = await answer({ method: 'GET', path: '/skills', token: false }, deps);
  assert.equal(unauthorised.status, 401);

  const wrongVerb = await answer({ method: 'POST', path: '/skills', body: {} }, deps);
  assert.equal(wrongVerb.status, 405);
});

test('S11 — with no store or no Claude home the route says the capability is missing rather than answering empty', async () => {
  const claude = claudeTree('1.0.0');
  const noStore = await answer({ method: 'GET', path: '/skills' }, { claudeHome: claude });
  assert.equal(noStore.status, 503);
  const noHome = await answer({ method: 'GET', path: '/skills' }, { extensions: scratchStore() });
  assert.equal(noHome.status, 503);
});

test('S12 — reading the skills changes no byte and no entry under Claude\'s tree', async () => {
  const claude = claudeTree('1.1.0');
  const before = snapshot(claude);
  await getSkills(claude);
  await getSkills(claude);
  assert.deepEqual(snapshot(claude), before);
});

test('K1 — keeping a held version stops it being reported as held', async () => {
  const claude = claudeTree('1.1.0');
  const store = scratchStore();
  const deps = { claudeHome: claude, extensions: store };

  const kept = await answer(
    { method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: '1.1.0' } },
    deps
  );
  assert.equal(kept.status, 200);

  const alpha = skillNamed(await getSkills(claude, store), 'alpha');
  assert.equal(alpha.held, null);
});

test('K2 — a version newer than the kept one reappears as held', async () => {
  const claude = claudeTree('1.1.0');
  const store = scratchStore();
  const deps = { claudeHome: claude, extensions: store };
  await answer({ method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: '1.1.0' } }, deps);

  offer(claude, '1.2.0');
  const alpha = skillNamed(await getSkills(claude, store), 'alpha');
  assert.equal(alpha.held?.pluginVersion, '1.2.0');
});

test('K3 — a catalogue that falls back to a version not newer than the kept one stays suppressed', async () => {
  const claude = claudeTree('1.2.0');
  const store = scratchStore();
  const deps = { claudeHome: claude, extensions: store };
  await answer({ method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: '1.2.0' } }, deps);

  offer(claude, '1.1.0');
  assert.equal(skillNamed(await getSkills(claude, store), 'alpha').held, null);
  offer(claude, '1.2.0');
  assert.equal(skillNamed(await getSkills(claude, store), 'alpha').held, null);
});

test('K4 — a kept version that cannot be ordered against the offer does not suppress it', async () => {
  const claude = claudeTree('1.1.0');
  const store = scratchStore();
  const deps = { claudeHome: claude, extensions: store };
  await answer({ method: 'POST', path: '/extensions/plugins/demo@market/keep', body: { pluginVersion: 'nightly' } }, deps);

  // Neither side is orderable, so "newer than the kept one" cannot be said, and a held update that asks for more is
  // shown rather than hidden on a guess.
  assert.equal(skillNamed(await getSkills(claude, store), 'alpha').held?.pluginVersion, '1.1.0');
});
