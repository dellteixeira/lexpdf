import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const worker = readFileSync(resolve(root, 'src/index.ts'), 'utf8');
const wrangler = readFileSync(resolve(root, 'wrangler.toml'), 'utf8');
const migration = readFileSync(
  resolve(root, '../supabase/migrations/20260917210000_add_ai_usage_quota.sql'),
  'utf8',
);

for (const expected of [
  '/v1/ai/explain',
  '@cf/zai-org/glm-4.7-flash',
  '@cf/google/gemma-4-26b-a4b-it',
  'consumeAiQuota',
  'SUPABASE_SECRET_KEY',
  'fallbackUsed',
]) {
  if (!worker.includes(expected)) {
    throw new Error(`Missing AI worker contract: ${expected}`);
  }
}

if (!wrangler.includes('[ai]') || !wrangler.includes('binding = "AI"')) {
  throw new Error('Workers AI binding is missing from wrangler.toml');
}

for (const expected of [
  'enable row level security',
  'revoke all on public.ai_daily_usage from public, anon, authenticated',
  'security definer',
  'consume_ai_daily_quota',
  'to service_role',
]) {
  if (!migration.includes(expected)) {
    throw new Error(`Missing AI quota invariant: ${expected}`);
  }
}

console.log('Workers AI explanation contracts verified.');
