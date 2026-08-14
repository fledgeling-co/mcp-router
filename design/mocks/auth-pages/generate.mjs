import { writeFileSync } from 'node:fs';
// PAGE copied VERBATIM from src/auth.ts so the emitted bytes are reference-derived,
// not hand-transcribed.
const PAGE = (title, detail) =>
  `<!doctype html><meta charset="utf-8"><title>${title}</title>` +
  `<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;` +
  `display:grid;place-items:center;height:100vh;margin:0;text-align:center}` +
  `h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>` +
  `<div><h1>${title}</h1><p>${detail}</p></div>`;

const out = 'design/mocks/auth-pages';
const pages = {
  'success':          PAGE('linear is connected', 'You can close this tab and return to mcp-router.'),
  'provider-refused': PAGE('Authorization failed', 'access_denied'),
  'no-code':          PAGE('Authorization failed', 'the provider returned no code'),
  'exchange-failed':  PAGE('Authorization failed', 'token endpoint returned 401 invalid_client'),
  'overflow':         PAGE('internal-platform-observability-gateway-staging-eu-west-1 is connected',
                           'You can close this tab and return to mcp-router.'),
};
for (const [name, html] of Object.entries(pages)) {
  writeFileSync(`${out}/${name}.html`, html);
  console.log(`${name}.html  ${Buffer.byteLength(html)} bytes`);
}
