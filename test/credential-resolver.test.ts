import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createServer } from 'node:http';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { WardenCredentialResolver, credentialReference, type BrokerFactory } from '../src/credentials.js';
import { UpstreamPool } from '../src/pool.js';
import type { StdioUpstream, HttpUpstream } from '../src/config.js';
import { configureLogging } from '../src/log.js';

const brokerFixture = resolve('test/fixtures/credential-broker.mjs');
const targetFixture = resolve('test/fixtures/credential-target.mjs');
function fixture(directory: string, mode = 'ok', values = ['synthetic-credential-12345']): BrokerFactory {
  let invocation = 0;
  return async (session, project) => {
    const transport = new StdioClientTransport({ command: process.execPath, args: [brokerFixture],
      env: { MODE: mode, VALUE: values[Math.min(invocation++, values.length-1)], AUDIT: join(directory,'audit'), FIXTURE_SESSION: session }, stderr:'pipe' });
    transport.stderr?.on('data',()=>{});
    assert.equal(project, directory);
    return { transport, client: new Client({name:'fixture-client',version:'1'},{capabilities:{}}) };
  };
}
function target(directory: string): StdioUpstream {
  return { transport:'stdio',name:'test',command:process.execPath,args:[targetFixture],
    cwd:directory,envFiles:[],env:{TEST_KEY:'warden://exact%2Fkey',OTHER:'literal',RECEIPT:join(directory,'receipt')} };
}
function scratch() { return realpathSync(mkdtempSync(join(tmpdir(),'mcpr-credentials-'))); }

describe('connection-time Warden credential resolution',()=>{
  test('keeps literals, preserves bearer wrapping, rejects ambiguous schemes and malformed names',()=>{
    assert.equal(credentialReference('https://example.test'),null);
    assert.deepEqual(credentialReference('Bearer warden://exact%2Fkey'),{name:'exact/key',bearer:true});
    for(const value of ['op://vault/item/field','Bearer op://vault/item/field','warden://','warden://%00','warden://%zz','WARDEN://<CHOOSE>','OP://vault/item/field']) {
      assert.throws(()=>credentialReference(value),/credential resolution refused/);
    }
  });

  test('real target gets resolved envFile values; manifests, responses and split stderr get no plaintext',async()=>{
    const directory=scratch(), secret='synthetic-credential-12345', u=target(directory);
    u.env={OTHER:'literal',RECEIPT:join(directory,'receipt')};
    u.envFiles=[join(directory,'.env')];
    writeFileSync(u.envFiles[0],'TEST_KEY=warden://exact%2Fkey\n');
    const log=join(directory,'router.log');
    configureLogging(log,true);
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory)));
    try {
      const handle=await pool.acquire(u.name);
      assert.equal(JSON.parse(readFileSync(join(directory,'receipt'),'utf8')).key,secret);
      assert.equal((await handle.client.listTools()).tools[0].description,'Bound <redacted:warden>');
      assert.equal(JSON.stringify(await pool.call(u.name,{name:'echo'})).includes(secret),false);
      assert.equal(readFileSync(log,'utf8').includes(secret),false);
      const audit=JSON.parse(readFileSync(join(directory,'audit'),'utf8'));
      assert.equal(audit.name,'exact/key');
      assert.match(audit.session,/^mcpr-credential-/);
      assert.equal(audit.project,directory);
      assert.match(audit.reason,/shared upstream test/);
      assert.equal(readFileSync(u.envFiles[0],'utf8'),'TEST_KEY=warden://exact%2Fkey\n');
    } finally { await pool.shutdown();configureLogging(undefined,false);rmSync(directory,{recursive:true,force:true}); }
  });

  for(const mode of ['denied','malformed','wrong-name','empty','unavailable','hang']) {
    test(`${mode} broker never starts target and never exposes raw payload`,async()=>{
      const directory=scratch(),u=target(directory),secret='synthetic-error-private';
      const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory,mode,[secret]),mode==='hang'?150:3000));
      const start=Date.now();
      try {
        await assert.rejects(pool.acquire(u.name),error=>{
          assert.equal(String(error).includes(secret),false);
          assert.match(String(error),/Warden credential resolution refused/);return true;
        });
        assert.equal(existsSync(join(directory,'receipt')),false);
        if(mode==='hang') assert.ok(Date.now()-start<1500,'total consent deadline must bound target startup');
      } finally { await pool.shutdown();rmSync(directory,{recursive:true,force:true}); }
    });
  }

  test('inherited URI-shaped values are not fetched or allowed to block unrelated configured credentials',async()=>{
    const directory=scratch(),u=target(directory);
    const oldWarden=process.env.INHERITED_WARDEN_REFERENCE,oldOp=process.env.INHERITED_OP_REFERENCE;
    process.env.INHERITED_WARDEN_REFERENCE='warden://must-not-be-fetched';
    process.env.INHERITED_OP_REFERENCE='op://must-not-block';
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory)));
    try {
      await pool.acquire(u.name);
      const receipt=JSON.parse(readFileSync(join(directory,'receipt'),'utf8'));
      assert.equal(receipt.inheritedWarden,'warden://must-not-be-fetched');
      assert.equal(receipt.inheritedOp,'op://must-not-block');
      assert.equal(readFileSync(join(directory,'audit'),'utf8').trim().split('\n').length,1);
    } finally {
      await pool.shutdown();
      if(oldWarden===undefined)delete process.env.INHERITED_WARDEN_REFERENCE;else process.env.INHERITED_WARDEN_REFERENCE=oldWarden;
      if(oldOp===undefined)delete process.env.INHERITED_OP_REFERENCE;else process.env.INHERITED_OP_REFERENCE=oldOp;
      rmSync(directory,{recursive:true,force:true});
    }
  });

  test('a missing explicit project prevents broker access rather than borrowing daemon cwd',async()=>{
    const directory=scratch();let called=false;
    const resolver=new WardenCredentialResolver(async()=>{called=true;throw new Error('not reached');});
    await assert.rejects(resolver.resolve({KEY:'warden://key'},{upstream:'unscoped'}),/credentialProject/);
    assert.equal(called,false);
    rmSync(directory,{recursive:true,force:true});
  });

  test('eight concurrent cold acquires share one broker and one target; chatty broker stderr is drained',async()=>{
    const directory=scratch(),u=target(directory);
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory,'chatty')));
    try {
      const handles=await Promise.all(Array.from({length:8},()=>pool.acquire(u.name)));
      assert.equal(new Set(handles).size,1);
      assert.equal(readFileSync(join(directory,'audit'),'utf8').trim().split('\n').length,1);
      assert.equal(readFileSync(join(directory,'receipt'),'utf8').trim().split('\n').length,1);
    } finally {await pool.shutdown();rmSync(directory,{recursive:true,force:true});}
  });

  test('each fresh target connection re-resolves and gets a distinct broker session',async()=>{
    const directory=scratch(),u=target(directory);
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory,'ok',['first-rotating-key','second-rotating-key'])));
    try {
      await (await pool.acquire(u.name)).client.close();
      await pool.acquire(u.name);
      const rows=readFileSync(join(directory,'receipt'),'utf8').trim().split('\n').map(line=>JSON.parse(line));
      assert.deepEqual(rows.map(row=>row.key),['first-rotating-key','second-rotating-key']);
      const sessions=readFileSync(join(directory,'audit'),'utf8').trim().split('\n').map(line=>JSON.parse(line).session);
      assert.equal(new Set(sessions).size,2);
    } finally { await pool.shutdown();rmSync(directory,{recursive:true,force:true}); }
  });

  test('cancellation closes consent and prevents target start',async()=>{
    const directory=scratch(),u=target(directory);
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory,'hang'),3000));
    const pending=pool.acquire(u.name);
    setTimeout(()=>void pool.shutdown(),75);
    await assert.rejects(pending,/cancelled/);
    assert.equal(existsSync(join(directory,'receipt')),false);
    rmSync(directory,{recursive:true,force:true});
  });

  test('HTTP401 replay of a resolved header never reaches pending auth or log diagnostics',async()=>{
    const directory=scratch(),secret='synthetic-credential-12345';
    const server=createServer((_req,res)=>res.writeHead(401,{'content-type':'text/plain'}).end('unauthorized '+secret));
    await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
    const port=(server.address() as {port:number}).port;
    const u:HttpUpstream={transport:'http',name:'refused-http',url:`http://127.0.0.1:${port}`,oauth:false,
      credentialProject:directory,headers:{Authorization:'Bearer warden://http-key'}};
    const logfile=join(directory,'diagnostics');configureLogging(logfile,true);
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory)));
    try {
      await assert.rejects(pool.acquire(u.name),error=>{assert.equal(String(error).includes(secret),false);return true;});
      assert.equal(JSON.stringify(pool.pending()).includes(secret),false);
      assert.equal(readFileSync(logfile,'utf8').includes(secret),false);
    } finally {
      await pool.shutdown();configureLogging(undefined,false);server.closeAllConnections();
      await new Promise<void>(resolve=>server.close(()=>resolve()));rmSync(directory,{recursive:true,force:true});
    }
  });

  test('HTTP initialize receives a resolved bearer header without changing its configured URI',async()=>{
    const directory=scratch();let received='';
    const server=createServer(async(req,res)=>{
      received=String(req.headers.authorization??'');
      if(req.method!=='POST'){res.writeHead(405).end();return;}
      let data='';for await(const chunk of req)data+=chunk;
      const m=JSON.parse(data);
      if(!('id'in m)){res.writeHead(202).end();return;}
      res.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify({jsonrpc:'2.0',id:m.id,result:{protocolVersion:'2025-06-18',capabilities:{tools:{}},serverInfo:{name:'http-target',version:'1'}}}));
    });
    await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
    const address=server.address() as {port:number};
    const u:HttpUpstream={transport:'http',name:'http',url:`http://127.0.0.1:${address.port}`,oauth:false,credentialProject:directory,headers:{Authorization:'Bearer warden://http-key'}};
    const pool=new UpstreamPool(new Map([[u.name,u]]),0,3000,new WardenCredentialResolver(fixture(directory)));
    try {
      await pool.acquire(u.name);
      assert.equal(received,'Bearer synthetic-credential-12345');
      assert.equal(u.headers.Authorization,'Bearer warden://http-key');
    } finally {await pool.shutdown();server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));rmSync(directory,{recursive:true,force:true});}
  });
});
