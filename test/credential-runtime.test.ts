import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, realpathSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { runtimeReceiptMatches } from '../src/credential-runtime.js';
import { CredentialProtectedTransport } from '../src/credentials.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';

const pause = (ms: number) => new Promise(resolve=>setTimeout(resolve,ms));
test('running-daemon receipt is token-gated, binds the config, and detects disk updated without restart',async()=>{
  const root=realpathSync(mkdtempSync(join(tmpdir(),'mcpr-runtime-proof-')));
  const home=join(root,'state');mkdirSync(home);
  const compiled=dirname(fileURLToPath(new URL('../src/index.js',import.meta.url)));
  cpSync(compiled,join(root,'dist'),{recursive:true});
  writeFileSync(join(root,'package.json'),JSON.stringify({type:'module'}));
  symlinkSync(resolve('node_modules'),join(root,'node_modules'),'dir');
  const probe=createServer();await new Promise<void>(resolve=>probe.listen(0,'127.0.0.1',resolve));
  const port=(probe.address() as {port:number}).port;
  await new Promise<void>(resolve=>probe.close(()=>resolve()));
  const config=join(home,'servers.json');writeFileSync(config,JSON.stringify({port,mcpServers:{scratch:{command:process.execPath,args:['--version']}}}));
  const child=spawn(process.execPath,[join(root,'dist/index.js'),'serve'],{
    env:{...process.env,HOME:home,MCP_ROUTER_HOME:home},stdio:['ignore','ignore','ignore'],
  });
  const ended=new Promise<void>(resolve=>child.once('exit',()=>resolve()));
  try {
    let ready=false;
    for(let i=0;i<100;i++) {
      try {if((await fetch(`http://127.0.0.1:${port}/health`)).ok){ready=true;break;}}catch{}
      await pause(50);
    }
    assert.equal(ready,true,'isolated daemon must start');
    const url=`http://127.0.0.1:${port}/runtime/credentials`;
    assert.equal((await fetch(url)).status,401);
    const headers={'x-mcpr-token':readFileSync(join(home,'control.token'),'utf8').trim()};
    let receipt=await (await fetch(url,{headers})).json();
    assert.equal(runtimeReceiptMatches(receipt,root,config),true);
    assert.equal((receipt as {pid:number}).pid,child.pid);
    assert.equal(runtimeReceiptMatches(receipt,root,join(root,'other-config')),false);
    const initialReceipt=receipt;
    const disabled=await fetch(`http://127.0.0.1:${port}/servers/scratch`,{
      method:'PATCH',headers:{...headers,'content-type':'application/json'},body:JSON.stringify({disabled:true})});
    assert.equal(disabled.status,200);
    receipt=await (await fetch(url,{headers})).json();
    assert.equal(runtimeReceiptMatches(initialReceipt,root,config),false,'pre-reload receipt must no longer certify the loaded config');
    assert.equal(runtimeReceiptMatches(receipt,root,config),true,'control reload must refresh the loaded configuration receipt without a restart');

    const originalConfig=readFileSync(config);
    writeFileSync(config,Buffer.concat([originalConfig,Buffer.from('\n')]));
    assert.equal(runtimeReceiptMatches(receipt,root,config),false,'receipt must match the configuration actually loaded');
    writeFileSync(config,originalConfig);
    assert.equal(runtimeReceiptMatches(receipt,root,config),true);
    writeFileSync(join(root,'dist/credentials.js'),readFileSync(join(root,'dist/credentials.js'),'utf8')+'\n// changed after daemon load\n');
    const stale=await (await fetch(url,{headers})).json();
    assert.deepEqual(stale,receipt,'receipt must retain the startup hashes');
    assert.equal(runtimeReceiptMatches(stale,root,config),false,'new disk files cannot certify old running code');
  } finally {
    child.kill('SIGTERM');await Promise.race([ended,pause(3000)]);if(child.exitCode===null)child.kill('SIGKILL');
    await ended;rmSync(root,{recursive:true,force:true});
  }
});

test('credential-bound transport drops incoming extra metadata and masks out-of-band errors',()=>{
  const inner:Transport={async start(){},async close(){},async send(){}};
  const protectedTransport=new CredentialProtectedTransport(inner,['private-synthetic-value']);
  let extra:unknown='unset';let message:unknown;let failure='';
  protectedTransport.onmessage=(value,metadata)=>{message=value;extra=metadata;};
  protectedTransport.onerror=error=>{failure=error.message;};
  inner.onmessage?.({jsonrpc:'2.0',id:1,result:{text:'private-synthetic-value'}},
    {authInfo:{token:'private-synthetic-value',clientId:'fixture',scopes:[]}});
  inner.onerror?.(new Error('unauthorized private-synthetic-value'));
  assert.equal(extra,undefined);
  assert.equal(JSON.stringify(message).includes('private-synthetic-value'),false);
  assert.equal(failure.includes('private-synthetic-value'),false);
});
