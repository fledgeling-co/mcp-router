import { existsSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { extname, isAbsolute, join, resolve, sep } from 'node:path';

/**
 * A capability's own documentation, read out of the package the router starts it from.
 *
 * The router is the only process that may read a package: the Mac app talks to it over the
 * loopback control API and nothing else, which is what lets the router be replaced underneath
 * the app. So the files, the image bytes and every refusal are decided here, and what crosses
 * the wire is bytes the app cannot mistake for a path.
 *
 * `planning/specs/spec-M30.md` owns the reasoning; this file is the reference implementation the
 * Swift port is diffed against, and the parity vectors are generated from these exact functions.
 */

/** The three documents a package may publish, in the panel's tab order. */
export const DOCUMENT_FILES: Array<{ tab: string; file: string }> = [
  { tab: 'readMe', file: 'README.md' },
  { tab: 'changelog', file: 'CHANGELOG.md' },
  { tab: 'capabilities', file: 'CAPABILITIES.md' },
];

/**
 * The transport's own caps, which are not `MarkdownLimits`.
 *
 * `MarkdownLimits` caps the parse, in the app, after the bytes have already crossed. A README is
 * unbounded on disk, so the wire needs a bound of its own — and a refusal that says which of the
 * three it hit, because "too large" without a cap name tells a reader nothing they can act on.
 */
export const DOCUMENT_CAPS = {
  /** One markdown file. Over this, the whole request refuses rather than truncating. */
  documentBytes: 524_288,
  /** One image. Over this, that image travels as a refusal and the document still travels. */
  imageBytes: 2_097_152,
  /** Every image in one response, together. Once spent, the rest are refused in document order. */
  imageBudgetBytes: 8_388_608,
} as const;

/**
 * What the app will render as an image, by extension.
 *
 * A boundary rather than a convenience: an image reference is a request to read a file, and the
 * document making it is untrusted. `svg` is deliberately outside the set — it is a document format
 * that can carry script, and nothing in this panel needs one.
 */
export const IMAGE_MEDIA_TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};

export type ImageRefusal =
  | { reason: 'remote'; scheme: string }
  | { reason: 'absolutePath' }
  | { reason: 'escapesPackage' }
  | { reason: 'notInPackage' }
  | { reason: 'unsupportedType'; extension: string }
  | { reason: 'tooLarge'; limit: number }
  | { reason: 'budgetExhausted' };

export type Resolution = { ok: true; path: string } | { ok: false; refusal: ImageRefusal };

/**
 * Every `![alt](reference)` in one run of text, in order, as the document spelled it.
 *
 * Hand-scanned rather than regexed, and the reason is the app's: a reference may contain balanced
 * parentheses — generated badge paths and Wikipedia URLs both do — and `\(([^)]*)\)` closes on the
 * first one, yielding a reference the document never wrote. A title after the reference is dropped
 * at the first space, because carrying it would make the reference unresolvable.
 *
 * This is the same scan `MarkdownParser.inlineImages` performs in the app. It has to be: the router
 * decides which files to read, so a router that extracts a different set of references sends a
 * different set of bytes, and the app cannot see that it happened.
 */
export function imageReferencesInRun(text: string): string[] {
  const refs: string[] = [];
  let i = 0;
  while (i < text.length) {
    const bang = text.indexOf('!', i);
    if (bang < 0) break;
    if (text[bang + 1] !== '[') {
      i = bang + 1;
      continue;
    }
    const close = text.indexOf(']', bang + 1);
    if (close < 0) break;
    if (text[close + 1] !== '(') {
      i = close + 1;
      continue;
    }
    let depth = 0;
    let closeParen = -1;
    for (let c = close + 1; c < text.length; c++) {
      if (text[c] === '(') depth += 1;
      if (text[c] === ')') {
        depth -= 1;
        if (depth === 0) {
          closeParen = c;
          break;
        }
      }
    }
    if (closeParen < 0) break;
    const inside = text.slice(close + 2, closeParen);
    const space = inside.indexOf(' ');
    refs.push(space < 0 ? inside : inside.slice(0, space));
    i = closeParen + 1;
  }
  return refs;
}

/**
 * Every image reference a document names, in document order, with duplicates collapsed.
 *
 * A **run** is a maximal group of consecutive non-blank lines outside a fenced code block, trimmed
 * and joined with one space — the same joining the app's parser performs before it scans, so a
 * reference split across two lines resolves to the same spelling on both sides.
 *
 * It is deliberately a coarser split than the parser's: the parser also breaks a run at a heading,
 * a list marker and a quote, and this does not. The consequence is stated rather than left to be
 * discovered — the router may extract a reference the app will never ask for, which costs bytes
 * and draws no wrong figure. It cannot go the other way, and a reference the app asks for and the
 * router never read is the failure that would matter.
 */
export function imageReferences(source: string): string[] {
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  const refs: string[] = [];
  const seen = new Set<string>();
  let run: string[] = [];
  let fenced = false;

  const flush = () => {
    if (run.length) {
      for (const ref of imageReferencesInRun(run.join(' '))) {
        if (!seen.has(ref)) {
          seen.add(ref);
          refs.push(ref);
        }
      }
      run = [];
    }
  };

  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      flush();
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    if (!line) {
      flush();
      continue;
    }
    run.push(line);
  }
  flush();
  return refs;
}

/**
 * Whether one reference may be read, and from where.
 *
 * Scheme first, because `path.resolve` will happily treat `https://example.com/a.png` as a
 * relative path and land it inside the package — a remote reference laundered into a local one.
 * Then absolute paths, which a document does not get to name whether or not they are inside the
 * package. Then containment, compared on **path segments** after resolving symlinks, because
 * `/pkg-evil/x.png` has `/pkg` as a string prefix and is not inside it, and because a downloaded
 * archive is exactly where a symlink pointing out of itself comes from.
 */
export function resolveInPackage(reference: string, root: string): Resolution {
  const trimmed = reference.trim();
  const scheme = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(trimmed);
  if (scheme) return { ok: false, refusal: { reason: 'remote', scheme: scheme[1].toLowerCase() } };
  if (trimmed.startsWith('/') || trimmed.startsWith('~') || isAbsolute(trimmed)) {
    return { ok: false, refusal: { reason: 'absolutePath' } };
  }

  const base = realPathOrResolved(root);
  const candidate = realPathOrResolved(resolve(base, trimmed));
  const baseParts = base.split(sep).filter(Boolean);
  const candidateParts = candidate.split(sep).filter(Boolean);
  const contained =
    candidateParts.length > baseParts.length &&
    baseParts.every((part, index) => candidateParts[index] === part);
  if (!contained) return { ok: false, refusal: { reason: 'escapesPackage' } };

  const ext = extname(candidate).toLowerCase();
  if (!IMAGE_MEDIA_TYPES[ext]) {
    return { ok: false, refusal: { reason: 'unsupportedType', extension: ext } };
  }
  if (!existsSync(candidate) || !statSync(candidate).isFile()) {
    return { ok: false, refusal: { reason: 'notInPackage' } };
  }
  return { ok: true, path: candidate };
}

/** `realpathSync` where the path exists, and the lexically resolved path where it does not. */
function realPathOrResolved(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
}

/** Whether one markdown file is over the transport's per-document cap. */
export function documentOverCap(size: number): boolean {
  return size > DOCUMENT_CAPS.documentBytes;
}

export type CapDecision = 'send' | 'tooLarge' | 'budgetExhausted';

/**
 * What happens to each image, in document order, given only their sizes.
 *
 * Pure arithmetic, and separated from the reading for that reason: it is the half a parity vector
 * can pin exactly, and the order matters — an oversized image is refused on its own terms and does
 * **not** spend the shared budget, so one 9 MiB figure cannot silently refuse every figure after
 * it for the wrong reason.
 */
export function imageCapDecisions(sizes: number[]): CapDecision[] {
  let spent = 0;
  return sizes.map((size) => {
    if (size > DOCUMENT_CAPS.imageBytes) return 'tooLarge';
    if (spent + size > DOCUMENT_CAPS.imageBudgetBytes) return 'budgetExhausted';
    spent += size;
    return 'send';
  });
}

export type DocumentRefusal = {
  status: number;
  error: string;
  reason: string;
  cap?: string;
  limit?: number;
  actual?: number;
  file?: string;
};

export interface DocumentBody {
  documents: Array<{ tab: string; text: string }>;
  images: Array<{ reference: string; media: string; base64: string }>;
  refusedImages: Array<{ reference: string } & ImageRefusal>;
}

/**
 * Read one package's documents and every image they name.
 *
 * Returns a refusal rather than a partial body for anything that makes the whole answer wrong —
 * no package, no documents, a document over its cap. An image that cannot be read is not one of
 * those: the reader learns the document pointed somewhere the router would not go, which is worth
 * knowing about a package you are deciding whether to trust.
 */
export function readPackageDocuments(root: string): DocumentBody | DocumentRefusal {
  if (!existsSync(root) || !statSync(root).isDirectory()) {
    return {
      status: 404,
      error: `the directory this server declares is not there: ${root}`,
      reason: 'packageUnreadable',
    };
  }

  const documents: DocumentBody['documents'] = [];
  for (const { tab, file } of DOCUMENT_FILES) {
    const path = join(root, file);
    if (!existsSync(path) || !statSync(path).isFile()) continue;
    const size = statSync(path).size;
    if (documentOverCap(size)) {
      return {
        status: 413,
        error: `${file} is ${size} bytes, over the ${DOCUMENT_CAPS.documentBytes}-byte transport cap for one document`,
        reason: 'documentTooLarge',
        cap: 'documentBytes',
        limit: DOCUMENT_CAPS.documentBytes,
        actual: size,
        file,
      };
    }
    documents.push({ tab, text: readFileSync(path, 'utf8') });
  }
  if (!documents.length) {
    return {
      status: 404,
      error: 'the package carries no read me, changelog or capability list',
      reason: 'noDocuments',
    };
  }

  const images: DocumentBody['images'] = [];
  const refusedImages: DocumentBody['refusedImages'] = [];
  const seen = new Set<string>();

  // Resolve every reference first, then decide the sizes in one pass. The budget is a property of
  // the whole response rather than of any one image, so the arithmetic that spends it is the pure
  // function `imageCapDecisions` and not a running total buried in a read loop.
  const readable: Array<{ reference: string; path: string; size: number }> = [];
  for (const { text } of documents) {
    for (const reference of imageReferences(text)) {
      if (seen.has(reference)) continue;
      seen.add(reference);
      const resolution = resolveInPackage(reference, root);
      if (!resolution.ok) {
        refusedImages.push({ reference, ...resolution.refusal });
        continue;
      }
      readable.push({ reference, path: resolution.path, size: statSync(resolution.path).size });
    }
  }

  const decisions = imageCapDecisions(readable.map((r) => r.size));
  readable.forEach((entry, index) => {
    if (decisions[index] === 'tooLarge') {
      refusedImages.push({ reference: entry.reference, reason: 'tooLarge', limit: DOCUMENT_CAPS.imageBytes });
      return;
    }
    if (decisions[index] === 'budgetExhausted') {
      refusedImages.push({ reference: entry.reference, reason: 'budgetExhausted' });
      return;
    }
    images.push({
      reference: entry.reference,
      media: IMAGE_MEDIA_TYPES[extname(entry.path).toLowerCase()]!,
      base64: readFileSync(entry.path).toString('base64'),
    });
  });

  return { documents, images, refusedImages };
}

/** True when a refusal was returned rather than a body. */
export function isRefusal(value: DocumentBody | DocumentRefusal): value is DocumentRefusal {
  return 'status' in value;
}
