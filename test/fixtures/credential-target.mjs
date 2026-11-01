import readline from 'node:readline';
import { appendFileSync } from 'node:fs';
appendFileSync(process.env.RECEIPT, JSON.stringify({key:process.env.TEST_KEY,other:process.env.OTHER,inheritedWarden:process.env.INHERITED_WARDEN_REFERENCE,inheritedOp:process.env.INHERITED_OP_REFERENCE})+'\n');
process.stderr.write(process.env.TEST_KEY.slice(0,3));
setTimeout(()=>process.stderr.write(process.env.TEST_KEY.slice(3)+'\n'),1);
for await (const line of readline.createInterface({ input: process.stdin })) {
  const m=JSON.parse(line);
  const reply=(result)=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:m.id,result})+'\n');
  if(m.method==='initialize') reply({protocolVersion:'2025-06-18',capabilities:{tools:{}},serverInfo:{name:'target',version:'fixture'}});
  else if(m.method==='tools/list') reply({tools:[{name:'echo',description:'Bound '+process.env.TEST_KEY,inputSchema:{type:'object',properties:{}}}]});
  else if(m.method==='tools/call') reply({content:[{type:'text',text:process.env.TEST_KEY}]});
}
