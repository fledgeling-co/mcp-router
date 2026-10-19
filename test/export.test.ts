import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildExport } from '../src/export.js';
import type { RawServer } from '../src/config.js';

// Planted values, one per secret position. Every one is a fake string shaped like the real thing.
const PLANTED = {
  envLong: 'env-secret-value-0001',
  envShort: 'Sx9',
  headerValue: 'hdr-bearer-9f8e7d6c5b4a',
  urlPassword: 'url-pass-7d7d7d7d',
  urlUserPosition: 'ghtoken-user-position-0099',
  argEquals: 'argtok-aaaa1111bbbb',
  argNext: 'sk-live-argkey-2222',
  argUrlPassword: 'pg-pass-cafe0123',
  argObject: 'obj-token-value-5150',
  queryValue: 'qk-secret-4444ffff',
  bareQuery: 'bare-query-token-6161',
  bearerArg: 'bearer-tok-55556666',
  sharedAcrossServers: 'shared-literal-8888aaaa',
  controlToken: 'ctl_planted_control_token_3333',
};

const SERVERS: Record<string, RawServer> = {
  alpha: {
    command: 'node',
    args: [
      '/opt/alpha/index.js',
      `--token=${PLANTED.argEquals}`,
      '--api-key',
      PLANTED.argNext,
      `postgres://dbuser:${PLANTED.argUrlPassword}@db.internal:5432/app`,
      `--header=Authorization: Bearer ${PLANTED.bearerArg}`,
      `--note=${PLANTED.sharedAcrossServers}`,
      { token: PLANTED.argObject } as unknown as string,
    ],
    env: {
      API_KEY: PLANTED.envLong,
      TINY: PLANTED.envShort,
      MODE: 'production',
    },
    cwd: '/opt/alpha',
    envFile: '/opt/alpha/.env',
    warm: true,
    projects: ['/Users/me/Dev/app'],
  },
  beta: {
    url: `https://beta.example.com/mcp?api_key=${PLANTED.queryValue}`,
    headers: {
      Authorization: `Bearer ${PLANTED.headerValue}`,
      'X-Team': 'platform',
    },
    oauth: false,
  },
  gamma: {
    url: `https://${PLANTED.urlUserPosition}@github.com/acme/repo.git`,
    headers: {},
    placard: { reason: 'upstream is down', substitute: 'alpha' },
  },
  delta: {
    url: `https://user:${PLANTED.urlPassword}@delta.example.com/mcp`,
    headers: {},
    disabled: true,
  },
  echo: {
    command: 'node',
    args: ['/opt/echo/index.js', `--shared=${PLANTED.sharedAcrossServers}`, `--control=${PLANTED.controlToken}`],
    env: { SHARED: PLANTED.sharedAcrossServers },
  },
};

const ALL_SECRETS = Object.values(PLANTED);

test('the exported document carries no planted secret, in any position', () => {
  const doc = JSON.stringify(buildExport(SERVERS, PLANTED.controlToken));
  for (const secret of ALL_SECRETS) {
    assert.ok(!doc.includes(secret), `a planted secret survived the export: ${secret}`);
  }
});

test('an env value becomes a placeholder naming its key, and the keys are kept', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.deepEqual(doc.mcpServers.alpha.env, {
    API_KEY: '<redacted:env.API_KEY>',
    TINY: '<redacted:env.TINY>',
    MODE: '<redacted:env.MODE>',
  });
});

test('a header value becomes a placeholder naming its header, and the header names are kept', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.deepEqual(doc.mcpServers.beta.headers, {
    Authorization: '<redacted:headers.Authorization>',
    'X-Team': '<redacted:headers.X-Team>',
  });
});

test('a URL keeps its scheme and host, and every part that can carry a credential is named in place', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.equal(
    doc.mcpServers.beta.url,
    'https://beta.example.com<redacted:url.path>?api_key=<redacted:url.query.api_key>',
  );
  assert.equal(doc.mcpServers.delta.url, 'https://<redacted:url.userinfo>@delta.example.com<redacted:url.path>');
  assert.equal(doc.mcpServers.gamma.url, 'https://<redacted:url.userinfo>@github.com<redacted:url.path>');
});

test('a bare query token is replaced whole, because its name is the secret', () => {
  const doc = buildExport(
    { x: { url: `https://x.example.com/mcp?${PLANTED.bareQuery}&team=platform`, headers: {} } },
    PLANTED.controlToken,
  );
  assert.equal(
    doc.mcpServers.x.url,
    'https://x.example.com<redacted:url.path>?<redacted:url.query.0>&team=<redacted:url.query.team>',
  );
  assert.ok(!JSON.stringify(doc).includes(PLANTED.bareQuery));
});

test('a kept field whose value has an unexpected shape is replaced, not copied', () => {
  const doc = buildExport(
    { x: { command: 'node', args: [], env: {}, cwd: { token: PLANTED.envLong } } as unknown as RawServer },
    PLANTED.controlToken,
  );
  assert.equal(doc.mcpServers.x.cwd, '<redacted:cwd>');
  assert.ok(!JSON.stringify(doc).includes(PLANTED.envLong));
});

test('argv keeps its shape, and each removed value is named by its argument index', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.deepEqual(doc.mcpServers.alpha.args, [
    '/opt/alpha/index.js',
    '--token=<redacted:args.1>',
    '--api-key',
    '<redacted:args.3>',
    'postgres://dbuser:<redacted:args.4>@db.internal:5432/app',
    '--header=Authorization: <redacted:args.5>',
    '--note=<redacted:args.6>',
    '<redacted:args.7>',
  ]);
});

test('a literal from one server is removed where it appears in another server', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.equal(doc.mcpServers.echo.args?.[1], '--shared=<redacted:args.1>');
  assert.equal(doc.mcpServers.echo.args?.[2], '--control=<redacted:args.2>');
});

test('non-secret structure is copied unchanged', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.equal(doc.mcpServers.alpha.command, 'node');
  assert.equal(doc.mcpServers.alpha.cwd, '/opt/alpha');
  assert.equal(doc.mcpServers.alpha.envFile, '/opt/alpha/.env');
  assert.equal(doc.mcpServers.alpha.warm, true);
  assert.deepEqual(doc.mcpServers.alpha.projects, ['/Users/me/Dev/app']);
  assert.equal(doc.mcpServers.beta.oauth, false);
  assert.equal(doc.mcpServers.delta.disabled, true);
  assert.deepEqual(doc.mcpServers.gamma.placard, { reason: 'upstream is down', substitute: 'alpha' });
});

test('an unrecognised key on a server entry is dropped rather than copied', () => {
  const doc = buildExport({ x: { command: 'node', args: [], env: {}, apiKey: PLANTED.envLong } as RawServer }, PLANTED.controlToken);
  assert.equal('apiKey' in doc.mcpServers.x, false);
  assert.ok(!JSON.stringify(doc).includes(PLANTED.envLong));
});

test('--only keeps the named servers and nothing else', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken, ['beta', 'echo']);
  assert.deepEqual(Object.keys(doc.mcpServers), ['beta', 'echo']);
});

test('--only with a name that is not in the list is an error, not an empty export', () => {
  assert.throws(() => buildExport(SERVERS, PLANTED.controlToken, ['beta', 'nope']), /"nope"/);
});

test('without --only every server is exported in its listed order', () => {
  const doc = buildExport(SERVERS, PLANTED.controlToken);
  assert.deepEqual(Object.keys(doc.mcpServers), Object.keys(SERVERS));
});
