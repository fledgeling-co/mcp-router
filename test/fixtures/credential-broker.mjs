import readline from 'node:readline';
import { appendFileSync } from 'node:fs';
for await (const line of readline.createInterface({ input: process.stdin })) {
  const message = JSON.parse(line);
  const reply = (result) => process.stdout.write(JSON.stringify({jsonrpc:'2.0', id:message.id, result})+'\n');
  if (message.method === 'initialize') {
    reply({protocolVersion:'2025-06-18',capabilities:{tools:{}},serverInfo:{name:'warden-mcp',version:'fixture'}});
  } else if (message.method === 'tools/call') {
    const args = message.params.arguments;
    appendFileSync(process.env.AUDIT, JSON.stringify({name:args.name,reason:args.reason,project:args.project,session:process.env.FIXTURE_SESSION})+'\n');
    if (process.env.MODE === 'hang') continue;
    if (process.env.MODE === 'unavailable') process.exit(3);
    const payload = process.env.MODE === 'malformed' ? '{not-json:'+process.env.VALUE : JSON.stringify({
      status: process.env.MODE === 'denied' ? 'Denied' : 'SuccessGetKey',
      payload: {key_name:process.env.MODE==='wrong-name'?'some-other-key':args.name,secret_value:process.env.MODE==='empty'?'':process.env.VALUE,grant_id:'00000000-0000-4000-8000-000000000001',reason:process.env.VALUE},
    });
    reply({content:[{type:'text',text:payload}],isError:process.env.MODE==='denied'});
  }
}
