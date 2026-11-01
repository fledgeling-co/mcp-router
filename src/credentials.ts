import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { promisify } from 'node:util';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import type { JSONRPCMessage } from '@modelcontextprotocol/sdk/types.js';
import { IS_DARWIN } from './platform.js';

const exec = promisify(execFile);
const WARDEN_APP = '/Applications/Warden.app';
const WARDEN_HELPER = `${WARDEN_APP}/Contents/MacOS/warden-mcp`;
const WARDEN_TEAM = 'H4HGFL52W7';
export const CREDENTIAL_CONSENT_MS = 300_000;
const CONNECT_MS = 5_000;
const MAX_BROKER_BYTES = 65_536;

export class CredentialError extends Error {
  constructor(readonly reason: 'unsupported' | 'project' | 'untrusted' | 'denied' | 'unavailable' | 'malformed' | 'timeout' | 'cancelled') {
    super(`Warden credential resolution refused: ${reason}. ${reason === 'project' ? 'Configure an absolute credentialProject before connecting. ' : ''}No target upstream was started.`);
    this.name = 'CredentialError';
  }
}

/** An exact key name, not a vault/title/field lookup. Literals remain literals. */
export function credentialReference(value: string): { name: string; bearer: boolean } | null {
  const bearer = /^Bearer\s+/i.test(value);
  const uri = bearer ? value.replace(/^Bearer\s+/i, '') : value;
  if (/^op:\/\//i.test(uri)) throw new CredentialError('unsupported');
  if (!/^warden:\/\//i.test(uri)) return null;
  let name: string;
  try { name = decodeURIComponent(uri.slice('warden://'.length)); }
  catch { throw new CredentialError('malformed'); }
  if (!name || name.length > 256 || name !== name.trim() || /[\x00-\x1f\x7f?#<>]/.test(name)) {
    throw new CredentialError('malformed');
  }
  return { name, bearer };
}

/** Gatekeeper plus exact Developer ID identity; no metadata reaches an unverifiable helper. */
export async function verifyWardenRuntime(): Promise<void> {
  if (!IS_DARWIN) throw new CredentialError('unsupported');
  try {
    if (realpathSync(WARDEN_APP) !== WARDEN_APP || realpathSync(WARDEN_HELPER) !== WARDEN_HELPER) {
      throw new Error('unexpected installation');
    }
    const requirement = `anchor apple generic and certificate leaf[subject.OU] = "${WARDEN_TEAM}"`;
    const options = { timeout: CONNECT_MS, maxBuffer: MAX_BROKER_BYTES };
    await exec('/usr/bin/codesign', ['--verify', '--deep', '--strict', '-R',
      `=identifier "app.fledgeling.warden" and ${requirement}`, WARDEN_APP], options);
    await exec('/usr/bin/codesign', ['--verify', '--strict', '-R',
      `=identifier "warden-mcp" and ${requirement}`, WARDEN_HELPER], options);
    await exec('/usr/sbin/spctl', ['--assess', '--type', 'execute', WARDEN_APP], options);
    await exec('/usr/sbin/spctl', ['--assess', '--type', 'execute', WARDEN_HELPER], options);
  } catch { throw new CredentialError('untrusted'); }
}

export interface CredentialContext { upstream: string; project?: string; signal?: AbortSignal }
export interface ResolvedCredentials { values: Record<string, string>; secrets: string[] }
export interface CredentialResolver {
  resolve(values: Record<string, string>, context: CredentialContext): Promise<ResolvedCredentials>;
}
export interface BrokerConnection { client: Client; transport: Transport }
export type BrokerFactory = (session: string, project: string) => Promise<BrokerConnection>;

async function installedBroker(session: string, project: string): Promise<BrokerConnection> {
  await verifyWardenRuntime();
  // An explicit environment prevents inherited socket overrides, old session grants and project
  // guesses from changing this connection's identity. No credential is given to the helper.
  const env: Record<string, string> = {
    HOME: process.env.HOME ?? '', PATH: '/usr/bin:/bin:/usr/sbin:/sbin',
    CLAUDE_CODE_SESSION_ID: session, CLAUDE_PROJECT_DIR: project,
    WARDEN_CLIENT_NAME: 'mcp-router credential connection',
  };
  const transport = new StdioClientTransport({ command: WARDEN_HELPER, args: [], env,
    stderr: 'pipe', maxBufferSize: MAX_BROKER_BYTES });
  // Broker stderr is never forwarded: errors can contain secret material or private metadata.
  transport.stderr?.on('data', () => {});
  return { client: new Client({ name: 'mcp-router-credentials', version: '0.1.0' }, { capabilities: {} }), transport };
}

/** One short-lived, independently bootstrapped broker connection per target connection. */
export class WardenCredentialResolver implements CredentialResolver {
  constructor(private readonly broker: BrokerFactory = installedBroker,
    private readonly deadlineMs = CREDENTIAL_CONSENT_MS) {}

  async resolve(values: Record<string, string>, context: CredentialContext): Promise<ResolvedCredentials> {
    const refs = Object.entries(values).flatMap(([key, value]) => {
      const ref = credentialReference(value);
      return ref ? [{ key, ...ref }] : [];
    });
    if (!refs.length) return { values: { ...values }, secrets: [] };
    if (context.signal?.aborted) throw new CredentialError('cancelled');
    if (!context.project) throw new CredentialError('project');
    let project: string;
    try { project = realpathSync(context.project); }
    catch { throw new CredentialError('malformed'); }
    let connection: BrokerConnection | undefined;
    let expired = false;
    const abort = new AbortController();
    let timer: NodeJS.Timeout | undefined;
    let rejectDeadline: (error: CredentialError) => void = () => {};
    const deadline = new Promise<never>((_, reject) => { rejectDeadline = reject; });
    const stop = (reason: 'timeout' | 'cancelled') => {
      expired = true;
      abort.abort();
      void connection?.transport.close().catch(() => {});
      rejectDeadline(new CredentialError(reason));
    };
    const cancel = () => stop('cancelled');
    context.signal?.addEventListener('abort', cancel, { once: true });
    timer = setTimeout(() => stop('timeout'), this.deadlineMs);
    try {
      const work = (async () => {
        connection = await this.broker(`mcpr-credential-${randomUUID()}`, project);
        if (expired) { await connection.transport.close(); throw new CredentialError('cancelled'); }
        await connection.client.connect(connection.transport, { timeout: Math.min(CONNECT_MS, this.deadlineMs), signal: abort.signal });
        const resolved = { ...values };
        const secrets: string[] = [];
        const byName = new Map<string, string>();
        for (const ref of refs) {
          if (expired) throw new CredentialError('cancelled');
          let secret = byName.get(ref.name);
          if (secret === undefined) {
            const response = await connection.client.callTool({ name: 'warden_get_key', arguments: {
              name: ref.name, project,
              reason: `Connect the router's shared upstream ${context.upstream}; use this key only in that connection`,
            } }, undefined, { timeout: this.deadlineMs, signal: abort.signal });
            if (expired) throw new CredentialError('cancelled');
            // Only the known JSON envelope is admitted. Never quote raw broker content or errors.
            const content = response.content;
            if (response.isError || !Array.isArray(content) || content.length !== 1 ||
                content[0].type !== 'text' || typeof content[0].text !== 'string' ||
                Buffer.byteLength(content[0].text) > MAX_BROKER_BYTES) throw new CredentialError('denied');
            let parsed: unknown;
            try { parsed = JSON.parse(content[0].text); }
            catch { throw new CredentialError('malformed'); }
            if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new CredentialError('malformed');
            const envelope = parsed as Record<string, unknown>;
            if (envelope.status === 'Denied') throw new CredentialError('denied');
            if (!envelope.payload || typeof envelope.payload !== 'object' || Array.isArray(envelope.payload)) {
              throw new CredentialError('malformed');
            }
            const payload = envelope.payload as Record<string, unknown>;
            if (envelope.status !== 'SuccessGetKey' || payload.key_name !== ref.name ||
                typeof payload.secret_value !== 'string' || !payload.secret_value || payload.secret_value.includes('\0') ||
                typeof payload.grant_id !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(payload.grant_id)) {
              throw new CredentialError('malformed');
            }
            secret = payload.secret_value;
            byName.set(ref.name, secret as string);
            secrets.push(secret as string);
          }
          resolved[ref.key] = ref.bearer ? `Bearer ${secret}` : secret as string;
        }
        return { values: resolved, secrets };
      })();
      return await Promise.race([work, deadline]);
    } catch (error) {
      if (error instanceof CredentialError) throw error;
      throw new CredentialError('unavailable');
    } finally {
      if (timer) clearTimeout(timer);
      context.signal?.removeEventListener('abort', cancel);
      // Closing is best-effort and is not on the consent deadline's critical return path.
      void connection?.client.close().catch(() => {});
      void connection?.transport.close().catch(() => {});
    }
  }
}

export function scrubCredentialText(value: string, secrets: string[]): string {
  let clean = value;
  for (const secret of secrets) {
    for (const form of new Set([secret, encodeURIComponent(secret), Buffer.from(secret).toString('base64')])) {
      if (form) clean = clean.split(form).join('<redacted:warden>');
    }
  }
  return clean;
}

/** Incoming metadata/results/errors cannot echo connection credentials into a manifest or model. */
export class CredentialProtectedTransport implements Transport {
  onclose?: Transport['onclose'];
  onerror?: Transport['onerror'];
  onmessage?: Transport['onmessage'];
  constructor(private readonly inner: Transport, private readonly secrets: string[]) {
    inner.onclose = () => this.onclose?.();
    inner.onerror = () => this.onerror?.(new Error('Credential-bound upstream transport failed'));
    inner.onmessage = (message) => {
      try { this.onmessage?.(this.scrub(message) as JSONRPCMessage); }
      catch { this.onerror?.(new Error('Credential-bound upstream response was refused')); }
    };
  }
  get pid(): number | null | undefined { return (this.inner as { pid?: number | null }).pid; }
  get sessionId(): string | undefined { return this.inner.sessionId; }
  async start(): Promise<void> {
    try { await this.inner.start(); }
    catch { throw new Error('Credential-bound upstream could not start'); }
  }
  async send(message: JSONRPCMessage, options?: Parameters<Transport['send']>[1]): Promise<void> {
    try { await this.inner.send(message, options); }
    catch { throw new Error('Credential-bound upstream request failed'); }
  }
  async close(): Promise<void> { try { await this.inner.close(); } catch { /* no raw diagnostics */ } }
  private scrub(value: unknown): unknown {
    if (typeof value === 'string') return scrubCredentialText(value, this.secrets);
    if (Array.isArray(value)) return value.map((entry) => this.scrub(entry));
    if (value && typeof value === 'object') {
      return Object.fromEntries(Object.entries(value).map(([key, entry]) => [this.scrub(key), this.scrub(entry)]));
    }
    return value;
  }
}
