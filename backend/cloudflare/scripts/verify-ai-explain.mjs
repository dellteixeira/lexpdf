import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const worker = readFileSync(resolve(root, 'src/index.ts'), 'utf8');
const wrangler = readFileSync(resolve(root, 'wrangler.toml'), 'utf8');
const legacyMigration = readFileSync(
  resolve(root, '../supabase/migrations/20260917210000_add_ai_usage_quota.sql'),
  'utf8',
);
const principalMigration = readFileSync(
  resolve(root, '../supabase/migrations/20260922143000_add_accountless_ai_principal_quota.sql'),
  'utf8',
);

for (const expected of [
  '/v1/ai/explain',
  '@cf/zai-org/glm-4.7-flash',
  '@cf/google/gemma-4-26b-a4b-it',
  '@cf/qwen/qwen3-30b-a3b-fp8',
  '@cf/meta/llama-3.2-3b-instruct',
  'rejectIfBusy: true',
  'modelCandidates',
  'uniqueStrings',
  'consumeAiQuota',
  'SUPABASE_SECRET_KEY',
  'fallbackUsed',
  'crossStudy',
  'FONTES INDEXADAS',
  'Não use conhecimento externo',
  'reviewTutor',
  'FLASHCARD EM REVISÃO',
  'O flashcard original não deve ser alterado',
  '/v1/ai/embed',
  '@cf/baai/bge-m3',
  'libraryRag',
  'BIBLIOTECA RECUPERADA',
  'Cada afirmação substantiva deve citar ao menos um marcador [F#]',
  'contextChat',
  'CHAT CONTEXTUAL COM FONTES',
  'O histórico é contexto conversacional, não evidência',
  '/v1/ai/vision',
  'DEFAULT_AI_VISION_MODEL',
  'Descreva somente o que é sustentado pela imagem',
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
  if (!legacyMigration.includes(expected)) {
    throw new Error(`Missing legacy AI quota invariant: ${expected}`);
  }
}

for (const expected of [
  'ai_principal_daily_usage',
  'ai_global_daily_usage',
  'consume_ai_principal_quota',
  'p_global_daily_limit',
  'to service_role',
]) {
  if (!principalMigration.includes(expected)) {
    throw new Error(`Missing accountless AI quota invariant: ${expected}`);
  }
}

console.log('Workers AI explanation contracts verified.');
