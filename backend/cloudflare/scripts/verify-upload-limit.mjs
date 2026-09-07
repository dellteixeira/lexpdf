import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

const required = [
  'class UploadLimitExceededError',
  'function boundedUploadBody',
  'bytesSeen += chunk.byteLength',
  'if (bytesSeen > max)',
  'reader.cancel("payload_too_large")',
  'boundedUploadBody(request, env)',
  'return json({ error: "payload_too_large" }, 413, requestId)',
];

for (const token of required) {
  if (!source.includes(token)) {
    throw new Error(`Cloudflare upload-limit invariant missing: ${token}`);
  }
}

const boundedUses = source.match(/DOCUMENTS\.put\([^\n]+boundedUploadBody\(request, env\)/g) ?? [];
if (boundedUses.length < 2) {
  throw new Error('Both upload and replace R2 writes must use the bounded upload stream.');
}

console.log('Cloudflare streaming upload-limit invariants OK.');
