import { writeFileSync } from 'node:fs';
// PAGE copied VERBATIM from src/auth.ts — these vectors are reference-derived, not hand-typed.
const PAGE = (title, detail) =>
  `<!doctype html><meta charset="utf-8"><title>${title}</title>` +
  `<style>body{font:15px/1.6 -apple-system,system-ui,sans-serif;background:#141220;color:#eae8f5;` +
  `display:grid;place-items:center;height:100vh;margin:0;text-align:center}` +
  `h1{font-size:19px;margin:0 0 6px}p{margin:0;color:#a6a2c4}</style>` +
  `<div><h1>${title}</h1><p>${detail}</p></div>`;

const cases = [
  { id: "connected",            kind: "connected", server: "linear",  detail: "",                     title: "linear is connected",  d: "You can close this tab and return to mcp-router." },
  { id: "connected-unicode",    kind: "connected", server: "a-b_9",   detail: "",                     title: "a-b_9 is connected",   d: "You can close this tab and return to mcp-router." },
  { id: "provider-refused",     kind: "failed",    server: "",        detail: "access_denied",        title: "Authorization failed", d: "access_denied" },
  { id: "no-code",             kind: "failed",    server: "",        detail: "the provider returned no code", title: "Authorization failed", d: "the provider returned no code" },
  { id: "exchange-failed",      kind: "failed",    server: "",        detail: "token endpoint returned 401 invalid_client", title: "Authorization failed", d: "token endpoint returned 401 invalid_client" },
  { id: "empty-error-detail",   kind: "failed",    server: "",        detail: "",                     title: "Authorization failed", d: "" },
];

const out = {
  description: "The bytes src/auth.ts's PAGE() emits, generated from the reference's own template literal. R4 diffs these.",
  cases: cases.map(c => ({
    id: c.id,
    kind: c.kind,
    server: c.server,
    detail: c.detail,
    html: PAGE(c.title, c.d),
  })),
};
writeFileSync('app/Tests/RouterCoreTests/Vectors/auth-pages.json', JSON.stringify(out, null, 2) + '\n');
console.log(`${out.cases.length} cases`);
